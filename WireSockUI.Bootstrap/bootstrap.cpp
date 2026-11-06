#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <aclapi.h>
#include <bcrypt.h>
#include <metahost.h>
#include <mscoree.h>
#include <sddl.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstddef>
#include <cwctype>
#include <exception>
#include <limits>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace
{
    constexpr int PayloadManifestResourceId = 201;
    constexpr wchar_t ManagedAssemblyName[] = L"WireSockUI.Managed.dll";
    constexpr wchar_t ApplicationConfigurationName[] = L"WireSockUI.exe.config";
    constexpr wchar_t NativeLauncherName[] = L"WireSockUI.exe";
    constexpr wchar_t RuntimeVersion[] = L"v4.0.30319";
    constexpr wchar_t ManagedTypeName[] = L"WireSockUI.Program";
    constexpr wchar_t ManagedMethodName[] = L"HostedMain";
    constexpr wchar_t NativeHostSelfTestCommandLine[] =
        L"--native-host-self-test \"argument with spaces\"";
    constexpr wchar_t ManagedNativeHostSelfTestToken[] =
        L"WireSockUI.NativeHostSelfTest.v1";
    constexpr int PayloadValidationFailureExitCode = 40;
    constexpr size_t Sha256Length = 32;
    constexpr size_t MaximumManifestEntries = 4096;
    constexpr size_t MaximumPayloadDepth = 32;
    constexpr unsigned long long MaximumPayloadFileBytes = 512ULL * 1024ULL * 1024ULL;
    constexpr unsigned long long MaximumPayloadBytes = 2ULL * 1024ULL * 1024ULL * 1024ULL;
#if defined(_M_ARM64)
    constexpr DWORD MinimumNetFrameworkRelease = 533320;
    constexpr wchar_t RequiredNetFrameworkName[] =
        L"Microsoft .NET Framework 4.8.1";
#else
    constexpr DWORD MinimumNetFrameworkRelease = 461808;
    constexpr wchar_t RequiredNetFrameworkName[] =
        L"Microsoft .NET Framework 4.7.2";
#endif

    const CLSID ClsidClrMetaHost =
        {0x9280188d, 0x0e8e, 0x4867, {0xb3, 0x0c, 0x7f, 0xa8, 0x38, 0x84, 0xe8, 0xde}};
    const IID IidClrMetaHost =
        {0xd332db9e, 0xb9b3, 0x4125, {0x82, 0x07, 0xa1, 0x48, 0x84, 0xf5, 0x32, 0x16}};
    const CLSID ClsidClrRuntimeHost =
        {0x90f1a06e, 0x7712, 0x4762, {0x86, 0xb5, 0x7a, 0x5e, 0xba, 0x6b, 0xdb, 0x02}};
    const IID IidClrRuntimeHost =
        {0x90f1a06c, 0x7712, 0x4762, {0x86, 0xb5, 0x7a, 0x5e, 0xba, 0x6b, 0xdb, 0x02}};

    class Handle final
    {
    public:
        Handle() noexcept = default;
        explicit Handle(HANDLE value) noexcept : value_(value) {}
        ~Handle() { Reset(); }

        Handle(const Handle&) = delete;
        Handle& operator=(const Handle&) = delete;

        Handle(Handle&& other) noexcept : value_(other.value_)
        {
            other.value_ = INVALID_HANDLE_VALUE;
        }

        Handle& operator=(Handle&& other) noexcept
        {
            if (this != &other)
            {
                Reset();
                value_ = other.value_;
                other.value_ = INVALID_HANDLE_VALUE;
            }
            return *this;
        }

        HANDLE get() const noexcept { return value_; }
        bool valid() const noexcept
        {
            return value_ != nullptr && value_ != INVALID_HANDLE_VALUE;
        }

    private:
        void Reset() noexcept
        {
            if (valid())
                CloseHandle(value_);
            value_ = INVALID_HANDLE_VALUE;
        }

        HANDLE value_ = INVALID_HANDLE_VALUE;
    };

    class LocalMemory final
    {
    public:
        explicit LocalMemory(HLOCAL value = nullptr) noexcept : value_(value) {}
        ~LocalMemory()
        {
            if (value_ != nullptr)
                LocalFree(value_);
        }

        LocalMemory(const LocalMemory&) = delete;
        LocalMemory& operator=(const LocalMemory&) = delete;

        HLOCAL get() const noexcept { return value_; }

    private:
        HLOCAL value_;
    };

    class FindHandle final
    {
    public:
        explicit FindHandle(HANDLE value = INVALID_HANDLE_VALUE) noexcept
            : value_(value) {}
        ~FindHandle()
        {
            if (value_ != INVALID_HANDLE_VALUE)
                FindClose(value_);
        }

        FindHandle(const FindHandle&) = delete;
        FindHandle& operator=(const FindHandle&) = delete;

        HANDLE get() const noexcept { return value_; }
        bool valid() const noexcept { return value_ != INVALID_HANDLE_VALUE; }

    private:
        HANDLE value_;
    };

    class RegistryKey final
    {
    public:
        explicit RegistryKey(HKEY value = nullptr) noexcept : value_(value) {}
        ~RegistryKey()
        {
            if (value_ != nullptr)
                RegCloseKey(value_);
        }

        RegistryKey(const RegistryKey&) = delete;
        RegistryKey& operator=(const RegistryKey&) = delete;

        HKEY get() const noexcept { return value_; }

    private:
        HKEY value_;
    };

    class SecurityDescriptor final
    {
    public:
        ~SecurityDescriptor()
        {
            if (value_ != nullptr)
                LocalFree(value_);
        }

        SecurityDescriptor(const SecurityDescriptor&) = delete;
        SecurityDescriptor& operator=(const SecurityDescriptor&) = delete;
        SecurityDescriptor() noexcept = default;

        PSECURITY_DESCRIPTOR* address() noexcept { return &value_; }

    private:
        PSECURITY_DESCRIPTOR value_ = nullptr;
    };

    class Module final
    {
    public:
        explicit Module(HMODULE value = nullptr) noexcept : value_(value) {}
        ~Module()
        {
            if (value_ != nullptr)
                FreeLibrary(value_);
        }

        Module(const Module&) = delete;
        Module& operator=(const Module&) = delete;

        HMODULE get() const noexcept { return value_; }

    private:
        HMODULE value_;
    };

    template<typename T>
    class ComPointer final
    {
    public:
        ComPointer() noexcept = default;
        ~ComPointer()
        {
            if (value_ != nullptr)
                value_->Release();
        }

        ComPointer(const ComPointer&) = delete;
        ComPointer& operator=(const ComPointer&) = delete;

        T* get() const noexcept { return value_; }
        T** address() noexcept { return &value_; }

    private:
        T* value_ = nullptr;
    };

    class BCryptAlgorithm final
    {
    public:
        ~BCryptAlgorithm()
        {
            if (value_ != nullptr)
                BCryptCloseAlgorithmProvider(value_, 0);
        }

        BCryptAlgorithm(const BCryptAlgorithm&) = delete;
        BCryptAlgorithm& operator=(const BCryptAlgorithm&) = delete;
        BCryptAlgorithm() noexcept = default;

        BCRYPT_ALG_HANDLE get() const noexcept { return value_; }
        BCRYPT_ALG_HANDLE* address() noexcept { return &value_; }

    private:
        BCRYPT_ALG_HANDLE value_ = nullptr;
    };

    class BCryptHash final
    {
    public:
        ~BCryptHash()
        {
            if (value_ != nullptr)
                BCryptDestroyHash(value_);
        }

        BCryptHash(const BCryptHash&) = delete;
        BCryptHash& operator=(const BCryptHash&) = delete;
        BCryptHash() noexcept = default;

        BCRYPT_HASH_HANDLE get() const noexcept { return value_; }
        BCRYPT_HASH_HANDLE* address() noexcept { return &value_; }

    private:
        BCRYPT_HASH_HANDLE value_ = nullptr;
    };

    struct CaseInsensitiveLess
    {
        bool operator()(const std::wstring& left, const std::wstring& right) const noexcept
        {
            const int result = CompareStringOrdinal(
                left.data(),
                static_cast<int>(left.size()),
                right.data(),
                static_cast<int>(right.size()),
                TRUE);
            if (result == CSTR_LESS_THAN)
                return true;
            if (result == CSTR_EQUAL || result == CSTR_GREATER_THAN)
                return false;

            // CompareStringOrdinal cannot fail for the bounded paths accepted
            // by IsCanonicalRelativePath. Keep the comparator strict even if a
            // future caller violates that invariant.
            return left < right;
        }
    };

    struct ManifestEntry
    {
        std::wstring relativePath;
        unsigned long long size = 0;
        std::array<BYTE, Sha256Length> hash = {};
    };

    std::wstring WindowsErrorMessage(DWORD error)
    {
        wchar_t* buffer = nullptr;
        const DWORD length = FormatMessageW(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                FORMAT_MESSAGE_IGNORE_INSERTS,
            nullptr,
            error,
            0,
            reinterpret_cast<wchar_t*>(&buffer),
            0,
            nullptr);
        LocalMemory allocation(buffer);
        if (length == 0 || buffer == nullptr)
            return L"Windows error " + std::to_wstring(error);

        std::wstring message(buffer, length);
        while (!message.empty() && std::iswspace(message.back()) != 0)
            message.pop_back();
        return message;
    }

    std::wstring HResultMessage(HRESULT result)
    {
        return WindowsErrorMessage(static_cast<DWORD>(result));
    }

    void WriteNativeHostSelfTestDiagnostic(const std::wstring& diagnostic)
    {
        const HANDLE standardError = GetStdHandle(STD_ERROR_HANDLE);
        if (standardError == nullptr || standardError == INVALID_HANDLE_VALUE)
            return;

        constexpr char prefix[] = "WireSockUI native self-test: ";
        constexpr char newline[] = "\r\n";
        DWORD written = 0;
        WriteFile(
            standardError,
            prefix,
            static_cast<DWORD>(sizeof(prefix) - 1),
            &written,
            nullptr);

        constexpr size_t maximumDiagnosticCharacters = 2048;
        const size_t characterCount =
            (std::min)(diagnostic.size(), maximumDiagnosticCharacters);
        std::array<char, maximumDiagnosticCharacters * 4> utf8 = {};
        const int byteCount = WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            diagnostic.data(),
            static_cast<int>(characterCount),
            utf8.data(),
            static_cast<int>(utf8.size()),
            nullptr,
            nullptr);
        if (byteCount > 0)
        {
            WriteFile(
                standardError,
                utf8.data(),
                static_cast<DWORD>(byteCount),
                &written,
                nullptr);
        }
        WriteFile(
            standardError,
            newline,
            static_cast<DWORD>(sizeof(newline) - 1),
            &written,
            nullptr);
    }

    bool IsNativeHostSelfTestDiagnosticsEnabled()
    {
        wchar_t enabled[2] = {};
        return GetEnvironmentVariableW(
                   L"WIRESOCKUI_NATIVE_SELF_TEST_DIAGNOSTICS",
                   enabled,
                   static_cast<DWORD>(_countof(enabled))) == 1 &&
               enabled[0] == L'1';
    }

    void WriteNativeHostSelfTestPhase(
        bool diagnosticsEnabled,
        const wchar_t* phase)
    {
        if (diagnosticsEnabled)
            WriteNativeHostSelfTestDiagnostic(
                std::wstring(L"phase: ") + phase);
    }

    void ShowStartupError(
        const std::wstring& diagnostic,
        bool nativeHostSelfTestRequested)
    {
        if (nativeHostSelfTestRequested)
        {
            WriteNativeHostSelfTestDiagnostic(diagnostic);
            return;
        }
#ifdef WIRESOCKUI_DEVELOPMENT_BUILD
        wchar_t suppressUi[2] = {};
        if (GetEnvironmentVariableW(
                L"WIRESOCKUI_DEVELOPMENT_SELF_TEST_NO_UI",
                suppressUi,
                static_cast<DWORD>(_countof(suppressUi))) == 1 &&
            suppressUi[0] == L'1')
            return;
#endif
        const std::wstring message =
            L"WireSock UI cannot start safely.\r\n\r\n" + diagnostic +
            L"\r\n\r\nRepair or reinstall WireSock UI using its official installer and retry.";
        MessageBoxW(
            nullptr,
            message.c_str(),
            L"WireSock UI startup error",
            MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
    }

    bool StartsWithIgnoreCase(const std::wstring& value, const wchar_t* prefix)
    {
        const size_t prefixLength = wcslen(prefix);
        return value.size() >= prefixLength &&
               _wcsnicmp(value.c_str(), prefix, prefixLength) == 0;
    }

    #ifdef WIRESOCKUI_DEVELOPMENT_BUILD
        bool EndsWithIgnoreCase(const std::wstring& value, const wchar_t* suffix)
        {
            const size_t suffixLength = wcslen(suffix);
            return value.size() >= suffixLength &&
                   _wcsicmp(
                       value.c_str() + value.size() - suffixLength,
                       suffix) == 0;
        }
    #endif

    bool EqualsIgnoreCase(const std::wstring& left, const wchar_t* right)
    {
        return _wcsicmp(left.c_str(), right) == 0;
    }

    bool IsNativeHostSelfTestCommandLine(const wchar_t* commandLine)
    {
        if (commandLine == nullptr)
            return false;

        const std::wstring value(commandLine);
        const size_t first = value.find_first_not_of(L" \t");
        if (first == std::wstring::npos)
            return false;
        const size_t last = value.find_last_not_of(L" \t");
        return value.compare(
                   first,
                   last - first + 1,
                   NativeHostSelfTestCommandLine) == 0;
    }

    std::wstring ParentPath(const std::wstring& path)
    {
        if (path.empty())
            return {};

        std::wstring trimmed = path;
        while (trimmed.size() > 3 &&
               (trimmed.back() == L'\\' || trimmed.back() == L'/'))
            trimmed.pop_back();

        const size_t separator = trimmed.find_last_of(L"\\/");
        if (separator == std::wstring::npos)
            return {};
        if (separator == 2 && trimmed.size() >= 3 && trimmed[1] == L':')
            return trimmed.substr(0, 3);
        return trimmed.substr(0, separator);
    }

    std::wstring CombinePath(const std::wstring& directory, const std::wstring& relativePath)
    {
        std::wstring result = directory;
        if (!result.empty() && result.back() != L'\\')
            result.push_back(L'\\');
        for (const wchar_t character : relativePath)
            result.push_back(character == L'/' ? L'\\' : character);
        return result;
    }

    bool IsCurrentProcessAdministrator()
    {
        BYTE administratorsBuffer[SECURITY_MAX_SID_SIZE] = {};
        DWORD administratorsSize = sizeof(administratorsBuffer);
        if (!CreateWellKnownSid(
                WinBuiltinAdministratorsSid,
                nullptr,
                administratorsBuffer,
                &administratorsSize))
            return false;

        BOOL isMember = FALSE;
        return CheckTokenMembership(nullptr, administratorsBuffer, &isMember) &&
               isMember != FALSE;
    }

#ifdef WIRESOCKUI_DEVELOPMENT_BUILD
    bool IsCurrentProcessUserSid(PSID sid)
    {
        HANDLE rawToken = nullptr;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &rawToken))
            return false;
        Handle token(rawToken);

        DWORD required = 0;
        GetTokenInformation(token.get(), TokenUser, nullptr, 0, &required);
        if (required == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER)
            return false;

        std::vector<BYTE> buffer(required);
        if (!GetTokenInformation(
                token.get(), TokenUser, buffer.data(), required, &required))
            return false;

        const auto user = reinterpret_cast<TOKEN_USER*>(buffer.data());
        return user->User.Sid != nullptr && EqualSid(sid, user->User.Sid) != FALSE;
    }
#endif

    bool IsTrustedSid(PSID sid)
    {
        if (sid == nullptr || IsValidSid(sid) == FALSE)
            return false;

        BYTE systemBuffer[SECURITY_MAX_SID_SIZE] = {};
        DWORD systemSize = sizeof(systemBuffer);
        BYTE administratorsBuffer[SECURITY_MAX_SID_SIZE] = {};
        DWORD administratorsSize = sizeof(administratorsBuffer);
        if (!CreateWellKnownSid(
                WinLocalSystemSid, nullptr, systemBuffer, &systemSize) ||
            !CreateWellKnownSid(
                WinBuiltinAdministratorsSid,
                nullptr,
                administratorsBuffer,
                &administratorsSize))
            return false;

        if (EqualSid(sid, systemBuffer) != FALSE ||
            EqualSid(sid, administratorsBuffer) != FALSE)
            return true;

        PSID trustedInstaller = nullptr;
        if (ConvertStringSidToSidW(
                L"S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464",
                &trustedInstaller) != FALSE)
        {
            LocalMemory allocation(trustedInstaller);
            if (EqualSid(sid, trustedInstaller) != FALSE)
                return true;
        }

#ifdef WIRESOCKUI_DEVELOPMENT_BUILD
        return IsCurrentProcessUserSid(sid);
#else
        return false;
#endif
    }

    bool TryGetAllowedAce(PACE_HEADER header, ACCESS_MASK& mask, PSID& sid)
    {
        mask = 0;
        sid = nullptr;
        if (header == nullptr || header->AceSize < sizeof(ACE_HEADER) + sizeof(ACCESS_MASK))
            return false;

        size_t sidOffset = 0;
        switch (header->AceType)
        {
        case ACCESS_ALLOWED_ACE_TYPE:
        case ACCESS_ALLOWED_CALLBACK_ACE_TYPE:
            sidOffset = offsetof(ACCESS_ALLOWED_ACE, SidStart);
            break;

        case ACCESS_ALLOWED_OBJECT_ACE_TYPE:
        case ACCESS_ALLOWED_CALLBACK_OBJECT_ACE_TYPE:
        {
            if (header->AceSize < offsetof(ACCESS_ALLOWED_OBJECT_ACE, ObjectType))
                return false;
            const auto objectAce = reinterpret_cast<ACCESS_ALLOWED_OBJECT_ACE*>(header);
            sidOffset = offsetof(ACCESS_ALLOWED_OBJECT_ACE, ObjectType);
            if ((objectAce->Flags & ACE_OBJECT_TYPE_PRESENT) != 0)
                sidOffset += sizeof(GUID);
            if ((objectAce->Flags & ACE_INHERITED_OBJECT_TYPE_PRESENT) != 0)
                sidOffset += sizeof(GUID);
            break;
        }

        default:
            return false;
        }

        if (sidOffset >= header->AceSize)
            return false;
        mask = *reinterpret_cast<ACCESS_MASK*>(
            reinterpret_cast<BYTE*>(header) + sizeof(ACE_HEADER));
        sid = reinterpret_cast<PSID>(reinterpret_cast<BYTE*>(header) + sidOffset);
        if (IsValidSid(sid) == FALSE ||
            sidOffset + GetLengthSid(sid) > header->AceSize)
        {
            sid = nullptr;
            return false;
        }
        return true;
    }

    bool IsAllowAceType(BYTE aceType)
    {
        return aceType == ACCESS_ALLOWED_ACE_TYPE ||
               aceType == ACCESS_ALLOWED_OBJECT_ACE_TYPE ||
               aceType == ACCESS_ALLOWED_CALLBACK_ACE_TYPE ||
               aceType == ACCESS_ALLOWED_CALLBACK_OBJECT_ACE_TYPE ||
               aceType == ACCESS_ALLOWED_COMPOUND_ACE_TYPE;
    }

    bool HasUnsafeAllowAce(
        PACL dacl,
        bool directory,
        bool containingEntry,
        std::wstring& diagnostic)
    {
        if (dacl == nullptr)
        {
            diagnostic = L"The object has an unrestricted null DACL.";
            return true;
        }

        ACL_SIZE_INFORMATION information = {};
        if (!GetAclInformation(
                dacl, &information, sizeof(information), AclSizeInformation))
        {
            diagnostic =
                L"Unable to inspect the object DACL: " +
                WindowsErrorMessage(GetLastError());
            return true;
        }

        ACCESS_MASK unsafeMask =
            DELETE | WRITE_DAC | WRITE_OWNER | GENERIC_WRITE | GENERIC_ALL |
            MAXIMUM_ALLOWED;
        if (containingEntry)
        {
            unsafeMask |= FILE_WRITE_DATA | FILE_APPEND_DATA |
                          FILE_WRITE_EA | FILE_WRITE_ATTRIBUTES;
            if (directory)
                unsafeMask |= FILE_ADD_SUBDIRECTORY | FILE_DELETE_CHILD;
        }
        else if (directory)
        {
            unsafeMask |= FILE_DELETE_CHILD;
        }

        for (DWORD index = 0; index < information.AceCount; ++index)
        {
            void* rawAce = nullptr;
            if (!GetAce(dacl, index, &rawAce))
            {
                diagnostic =
                    L"Unable to inspect an object access rule: " +
                    WindowsErrorMessage(GetLastError());
                return true;
            }

            const auto header = static_cast<PACE_HEADER>(rawAce);
            if ((header->AceFlags & INHERIT_ONLY_ACE) != 0)
                continue;
            if (!IsAllowAceType(header->AceType))
                continue;
            if (header->AceType == ACCESS_ALLOWED_COMPOUND_ACE_TYPE)
            {
                diagnostic =
                    L"The object contains an unsupported compound allow ACE.";
                return true;
            }

            ACCESS_MASK mask = 0;
            PSID sid = nullptr;
            if (!TryGetAllowedAce(header, mask, sid))
            {
                diagnostic =
                    L"The object contains a malformed or unsupported allow ACE.";
                return true;
            }
            if ((mask & unsafeMask) == 0)
                continue;
            if (!IsTrustedSid(sid))
            {
                diagnostic =
                    L"The object grants write or replacement rights to an "
                    L"untrusted identity.";
                return true;
            }
        }

        return false;
    }

    bool ValidateOpenedPath(
        HANDLE handle,
        const std::wstring& path,
        bool expectedDirectory,
        bool containingEntry,
        std::wstring& diagnostic)
    {
        FILE_ATTRIBUTE_TAG_INFO attributes = {};
        if (!GetFileInformationByHandleEx(
                handle, FileAttributeTagInfo, &attributes, sizeof(attributes)))
        {
            diagnostic =
                L"Unable to inspect '" + path + L"': " +
                WindowsErrorMessage(GetLastError());
            return false;
        }

        const bool isDirectory =
            (attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        if (isDirectory != expectedDirectory)
        {
            diagnostic =
                L"Application payload entry '" + path +
                L"' has the wrong object type.";
            return false;
        }
        if ((attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
        {
            diagnostic =
                L"Application payload entry '" + path +
                L"' is a reparse point.";
            return false;
        }

        if (!expectedDirectory)
        {
            BY_HANDLE_FILE_INFORMATION information = {};
            if (!GetFileInformationByHandle(handle, &information))
            {
                diagnostic =
                    L"Unable to inspect file identity for '" + path + L"': " +
                    WindowsErrorMessage(GetLastError());
                return false;
            }
            if (information.nNumberOfLinks != 1)
            {
                diagnostic =
                    L"Application payload entry '" + path +
                    L"' is hard-linked.";
                return false;
            }
        }

        PSID owner = nullptr;
        PACL dacl = nullptr;
        SecurityDescriptor descriptor;
        const DWORD securityResult = GetSecurityInfo(
            handle,
            SE_FILE_OBJECT,
            OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
            &owner,
            nullptr,
            &dacl,
            nullptr,
            descriptor.address());
        if (securityResult != ERROR_SUCCESS)
        {
            diagnostic =
                L"Unable to inspect security for '" + path + L"': " +
                WindowsErrorMessage(securityResult);
            return false;
        }
        if (!IsTrustedSid(owner))
        {
            diagnostic =
                L"Application payload entry '" + path +
                L"' is not owned by SYSTEM, TrustedInstaller, or "
                L"BUILTIN\\Administrators.";
            return false;
        }

        std::wstring aclDiagnostic;
        if (HasUnsafeAllowAce(
                dacl, expectedDirectory, containingEntry, aclDiagnostic))
        {
            diagnostic =
                L"Application payload entry '" + path + L"' is unsafe. " +
                aclDiagnostic;
            return false;
        }
        return true;
    }

    bool OpenAndValidateDirectory(
        const std::wstring& path,
        bool containingEntry,
        bool holdMutationLock,
        Handle& result,
        std::wstring& diagnostic)
    {
        const DWORD sharing = holdMutationLock
            ? FILE_SHARE_READ
            : FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
        Handle handle(CreateFileW(
            path.c_str(),
            READ_CONTROL | FILE_READ_ATTRIBUTES,
            sharing,
            nullptr,
            OPEN_EXISTING,
            FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS,
            nullptr));
        if (!handle.valid())
        {
            diagnostic =
                L"Unable to open directory '" + path + L"' safely: " +
                WindowsErrorMessage(GetLastError());
            return false;
        }
        if (!ValidateOpenedPath(
                handle.get(), path, true, containingEntry, diagnostic))
            return false;

        result = std::move(handle);
        return true;
    }

    bool OpenAndValidateFile(
        const std::wstring& path,
        Handle& result,
        std::wstring& diagnostic)
    {
        Handle handle(CreateFileW(
            path.c_str(),
            GENERIC_READ | READ_CONTROL | FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ,
            nullptr,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT |
                FILE_FLAG_SEQUENTIAL_SCAN,
            nullptr));
        if (!handle.valid())
        {
            diagnostic =
                L"Unable to open payload file '" + path + L"' safely: " +
                WindowsErrorMessage(GetLastError());
            return false;
        }
        if (!ValidateOpenedPath(handle.get(), path, false, true, diagnostic))
            return false;

        result = std::move(handle);
        return true;
    }

    bool ValidateLocalFixedPath(
        const std::wstring& path,
        std::wstring& volumeRoot,
        std::wstring& diagnostic)
    {
        std::vector<wchar_t> buffer(32768);
        if (!GetVolumePathNameW(
                path.c_str(), buffer.data(), static_cast<DWORD>(buffer.size())))
        {
            diagnostic =
                L"Unable to resolve the application volume: " +
                WindowsErrorMessage(GetLastError());
            return false;
        }
        if (GetDriveTypeW(buffer.data()) != DRIVE_FIXED)
        {
            diagnostic =
                L"WireSock UI must be installed on a local fixed drive.";
            return false;
        }

        volumeRoot.assign(buffer.data());
        return true;
    }

    bool ValidateAncestorChain(
        const std::wstring& applicationDirectory,
        const std::wstring& volumeRoot,
        std::wstring& diagnostic)
    {
        std::wstring ancestor = ParentPath(applicationDirectory);
        while (!ancestor.empty())
        {
            Handle handle;
            if (!OpenAndValidateDirectory(
                    ancestor, false, false, handle, diagnostic))
                return false;
            if (_wcsicmp(ancestor.c_str(), volumeRoot.c_str()) == 0)
                return true;

            const std::wstring parent = ParentPath(ancestor);
            if (parent.empty() ||
                _wcsicmp(parent.c_str(), ancestor.c_str()) == 0)
                break;
            ancestor = parent;
        }

        diagnostic = L"The application volume root could not be validated.";
        return false;
    }

    bool IsReservedDeviceSegment(const std::wstring& segment)
    {
        const size_t dot = segment.find(L'.');
        const std::wstring name = segment.substr(0, dot);
        if (EqualsIgnoreCase(name, L"CON") ||
            EqualsIgnoreCase(name, L"PRN") ||
            EqualsIgnoreCase(name, L"AUX") ||
            EqualsIgnoreCase(name, L"NUL"))
            return true;

        if (name.size() == 4 &&
            (StartsWithIgnoreCase(name, L"COM") ||
             StartsWithIgnoreCase(name, L"LPT")) &&
            name[3] >= L'1' && name[3] <= L'9')
            return true;
        return false;
    }

    bool IsCanonicalRelativePath(const std::wstring& path)
    {
        if (path.empty() || path.front() == L'/' || path.front() == L'\\' ||
            path.find(L'\\') != std::wstring::npos ||
            path.find(L':') != std::wstring::npos ||
            path.size() >= 32700)
            return false;

        size_t start = 0;
        while (start < path.size())
        {
            const size_t separator = path.find(L'/', start);
            const size_t length =
                separator == std::wstring::npos
                    ? path.size() - start
                    : separator - start;
            if (length == 0)
                return false;
            const std::wstring segment = path.substr(start, length);
            if (segment == L"." || segment == L".." ||
                segment.back() == L'.' || segment.back() == L' ' ||
                IsReservedDeviceSegment(segment))
                return false;
            for (const wchar_t character : segment)
            {
                if (character < 32 || character == L'"' || character == L'<' ||
                    character == L'>' || character == L'|' ||
                    character == L'*' || character == L'?')
                    return false;
            }

            if (separator == std::wstring::npos)
                break;
            start = separator + 1;
        }
        return true;
    }

    bool TryParseHash(
        const std::wstring& text,
        std::array<BYTE, Sha256Length>& result)
    {
        if (text.size() != Sha256Length * 2)
            return false;
        for (size_t index = 0; index < Sha256Length; ++index)
        {
            const auto nibble = [](wchar_t character, BYTE& value)
            {
                if (character >= L'0' && character <= L'9')
                {
                    value = static_cast<BYTE>(character - L'0');
                    return true;
                }
                if (character >= L'a' && character <= L'f')
                {
                    value = static_cast<BYTE>(character - L'a' + 10);
                    return true;
                }
                return false;
            };

            BYTE high = 0;
            BYTE low = 0;
            if (!nibble(text[index * 2], high) ||
                !nibble(text[index * 2 + 1], low))
                return false;
            result[index] = static_cast<BYTE>((high << 4) | low);
        }
        return true;
    }

    bool ParsePayloadManifest(
        std::vector<ManifestEntry>& entries,
        std::wstring& diagnostic)
    {
        const HRSRC resource = FindResourceW(
            nullptr,
            MAKEINTRESOURCEW(PayloadManifestResourceId),
            RT_RCDATA);
        if (resource == nullptr)
        {
            diagnostic = L"The launcher has no embedded payload manifest.";
            return false;
        }
        const DWORD resourceSize = SizeofResource(nullptr, resource);
        if (resourceSize == 0 || resourceSize > 2U * 1024U * 1024U)
        {
            diagnostic = L"The embedded payload manifest has an invalid size.";
            return false;
        }
        const HGLOBAL loaded = LoadResource(nullptr, resource);
        const auto bytes = static_cast<const char*>(LockResource(loaded));
        if (loaded == nullptr || bytes == nullptr)
        {
            diagnostic = L"The embedded payload manifest cannot be read.";
            return false;
        }

        const int wideLength = MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            bytes,
            static_cast<int>(resourceSize),
            nullptr,
            0);
        if (wideLength <= 0)
        {
            diagnostic = L"The embedded payload manifest is not valid UTF-8.";
            return false;
        }
        std::wstring text(static_cast<size_t>(wideLength), L'\0');
        if (MultiByteToWideChar(
                CP_UTF8,
                MB_ERR_INVALID_CHARS,
                bytes,
                static_cast<int>(resourceSize),
                &text[0],
                wideLength) != wideLength)
        {
            diagnostic = L"The embedded payload manifest could not be decoded.";
            return false;
        }

        const std::wstring header = L"WireSockUI-Payload-v1\n";
        if (text.compare(0, header.size(), header) != 0)
        {
            diagnostic = L"The embedded payload manifest version is unsupported.";
            return false;
        }

        entries.clear();
        std::set<std::wstring, CaseInsensitiveLess> paths;
        unsigned long long totalBytes = 0;
        std::wstring previousPath;
        size_t cursor = header.size();
        while (cursor < text.size())
        {
            const size_t end = text.find(L'\n', cursor);
            if (end == std::wstring::npos)
            {
                diagnostic = L"The embedded payload manifest is not newline terminated.";
                return false;
            }
            if (end == cursor)
            {
                diagnostic = L"The embedded payload manifest contains a blank entry.";
                return false;
            }

            const std::wstring line = text.substr(cursor, end - cursor);
            cursor = end + 1;
            const size_t firstTab = line.find(L'\t');
            const size_t secondTab =
                firstTab == std::wstring::npos
                    ? std::wstring::npos
                    : line.find(L'\t', firstTab + 1);
            if (firstTab == std::wstring::npos ||
                secondTab == std::wstring::npos ||
                line.find(L'\t', secondTab + 1) != std::wstring::npos)
            {
                diagnostic = L"The embedded payload manifest has an invalid entry.";
                return false;
            }

            ManifestEntry entry;
            const std::wstring hashText = line.substr(0, firstTab);
            const std::wstring sizeText =
                line.substr(firstTab + 1, secondTab - firstTab - 1);
            entry.relativePath = line.substr(secondTab + 1);
            if (!TryParseHash(hashText, entry.hash) ||
                !IsCanonicalRelativePath(entry.relativePath))
            {
                diagnostic =
                    L"The embedded payload manifest has a non-canonical entry.";
                return false;
            }
            if (sizeText.empty() ||
                (sizeText.size() > 1 && sizeText.front() == L'0') ||
                std::any_of(
                    sizeText.begin(),
                    sizeText.end(),
                    [](wchar_t character)
                    {
                        return character < L'0' || character > L'9';
                    }))
            {
                diagnostic =
                    L"The embedded payload manifest has a non-canonical file size.";
                return false;
            }

            wchar_t* sizeEnd = nullptr;
            errno = 0;
            entry.size = _wcstoui64(sizeText.c_str(), &sizeEnd, 10);
            if (errno == ERANGE || sizeText.empty() ||
                sizeEnd == nullptr || *sizeEnd != L'\0' ||
                entry.size > MaximumPayloadFileBytes ||
                totalBytes > MaximumPayloadBytes - entry.size)
            {
                diagnostic =
                    L"The embedded payload manifest has an invalid file size.";
                return false;
            }
            totalBytes += entry.size;

            if (!paths.insert(entry.relativePath).second ||
                EqualsIgnoreCase(entry.relativePath, NativeLauncherName) ||
                (!previousPath.empty() &&
                 !CaseInsensitiveLess{}(previousPath, entry.relativePath)))
            {
                diagnostic =
                    L"The embedded payload manifest is not uniquely and "
                    L"canonically ordered.";
                return false;
            }
            previousPath = entry.relativePath;
            entries.push_back(std::move(entry));
            if (entries.size() > MaximumManifestEntries)
            {
                diagnostic = L"The embedded payload manifest has too many entries.";
                return false;
            }
        }

        if (entries.empty())
        {
            diagnostic = L"The embedded payload manifest is empty.";
            return false;
        }
        if (paths.find(ManagedAssemblyName) == paths.end() ||
            paths.find(ApplicationConfigurationName) == paths.end())
        {
            diagnostic =
                L"The embedded payload manifest omits a required application file.";
            return false;
        }
        return true;
    }

    bool HashFile(
        BCRYPT_ALG_HANDLE algorithm,
        HANDLE file,
        unsigned long long expectedSize,
        std::array<BYTE, Sha256Length>& result,
        std::wstring& diagnostic)
    {
        DWORD objectLength = 0;
        DWORD hashLength = 0;
        DWORD received = 0;
        if (!BCRYPT_SUCCESS(BCryptGetProperty(
                algorithm,
                BCRYPT_OBJECT_LENGTH,
                reinterpret_cast<PUCHAR>(&objectLength),
                sizeof(objectLength),
                &received,
                0)) ||
            received != sizeof(objectLength) ||
            !BCRYPT_SUCCESS(BCryptGetProperty(
                algorithm,
                BCRYPT_HASH_LENGTH,
                reinterpret_cast<PUCHAR>(&hashLength),
                sizeof(hashLength),
                &received,
                0)) ||
            received != sizeof(hashLength) ||
            hashLength != Sha256Length)
        {
            diagnostic = L"Unable to configure SHA-256 payload validation.";
            return false;
        }

        std::vector<BYTE> hashObject(objectLength);
        BCryptHash hash;
        if (!BCRYPT_SUCCESS(BCryptCreateHash(
                algorithm,
                hash.address(),
                hashObject.data(),
                static_cast<ULONG>(hashObject.size()),
                nullptr,
                0,
                0)))
        {
            diagnostic = L"Unable to initialize SHA-256 payload validation.";
            return false;
        }

        LARGE_INTEGER beginning = {};
        if (!SetFilePointerEx(file, beginning, nullptr, FILE_BEGIN))
        {
            diagnostic =
                L"Unable to read a payload file: " +
                WindowsErrorMessage(GetLastError());
            return false;
        }

        std::array<BYTE, 64 * 1024> buffer = {};
        unsigned long long bytesReadTotal = 0;
        for (;;)
        {
            DWORD bytesRead = 0;
            if (!ReadFile(
                    file,
                    buffer.data(),
                    static_cast<DWORD>(buffer.size()),
                    &bytesRead,
                    nullptr))
            {
                diagnostic =
                    L"Unable to hash a payload file: " +
                    WindowsErrorMessage(GetLastError());
                return false;
            }
            if (bytesRead == 0)
                break;
            if (bytesReadTotal > expectedSize ||
                static_cast<unsigned long long>(bytesRead) >
                    expectedSize - bytesReadTotal)
            {
                diagnostic = L"A payload file changed size during validation.";
                return false;
            }
            bytesReadTotal += bytesRead;
            if (!BCRYPT_SUCCESS(BCryptHashData(
                    hash.get(), buffer.data(), bytesRead, 0)))
            {
                diagnostic = L"Unable to hash a payload file.";
                return false;
            }
        }
        if (bytesReadTotal != expectedSize)
        {
            diagnostic = L"A payload file has an unexpected size.";
            return false;
        }
        if (!BCRYPT_SUCCESS(BCryptFinishHash(
                hash.get(),
                result.data(),
                static_cast<ULONG>(result.size()),
                0)))
        {
            diagnostic = L"Unable to finish SHA-256 payload validation.";
            return false;
        }
        return true;
    }

    bool IsIgnoredDevelopmentMetadataFile(const std::wstring& relativePath)
    {
    #ifndef WIRESOCKUI_DEVELOPMENT_BUILD
        (void)relativePath;
        return false;
    #else
        const size_t separator = relativePath.find_last_of(L'/');
        const std::wstring name =
            separator == std::wstring::npos
                ? relativePath
                : relativePath.substr(separator + 1);
        const size_t dot = name.find_last_of(L'.');
        if (dot != std::wstring::npos)
        {
            const std::wstring extension = name.substr(dot);
            if (EqualsIgnoreCase(extension, L".pdb") ||
                EqualsIgnoreCase(extension, L".wixpdb") ||
                EqualsIgnoreCase(extension, L".msi") ||
                EqualsIgnoreCase(extension, L".msix") ||
                EqualsIgnoreCase(extension, L".msp") ||
                EqualsIgnoreCase(extension, L".cab") ||
                EqualsIgnoreCase(extension, L".zip") ||
                EqualsIgnoreCase(extension, L".nupkg") ||
                EqualsIgnoreCase(extension, L".snupkg") ||
                EqualsIgnoreCase(extension, L".sha256") ||
                EqualsIgnoreCase(extension, L".obj") ||
                EqualsIgnoreCase(extension, L".res") ||
                EqualsIgnoreCase(extension, L".exp") ||
                EqualsIgnoreCase(extension, L".lib") ||
                EqualsIgnoreCase(extension, L".ilk") ||
                EqualsIgnoreCase(extension, L".map"))
                return true;
        }
        if (EndsWithIgnoreCase(name, L".spdx.json") ||
            EndsWithIgnoreCase(name, L".sbom.json") ||
            EndsWithIgnoreCase(name, L".intoto.jsonl"))
            return true;

        constexpr wchar_t stagingPrefix[] = L".WireSockUI.";
        constexpr wchar_t stagingSuffix[] = L".staging.tmp";
        const size_t prefixLength = _countof(stagingPrefix) - 1;
        const size_t suffixLength = _countof(stagingSuffix) - 1;
        if (separator != std::wstring::npos ||
            name.size() != prefixLength + 32 + suffixLength ||
            name.compare(0, prefixLength, stagingPrefix) != 0 ||
            name.compare(
                name.size() - suffixLength,
                suffixLength,
                stagingSuffix) != 0)
            return false;
        return std::all_of(
            name.begin() + static_cast<std::ptrdiff_t>(prefixLength),
            name.end() - static_cast<std::ptrdiff_t>(suffixLength),
            [](wchar_t character)
            {
                return (character >= L'0' && character <= L'9') ||
                       (character >= L'a' && character <= L'f');
            });
    #endif
    }

    bool IsIgnoredMetadataSubtree(const std::wstring& relativePath)
    {
        const size_t separator = relativePath.find(L'/');
        const std::wstring root = relativePath.substr(0, separator);
        return EqualsIgnoreCase(root, L"_manifest") ||
               EqualsIgnoreCase(root, L"publish");
    }

    bool ScanPayloadDirectory(
        const std::wstring& applicationDirectory,
        const std::wstring& currentDirectory,
        const std::wstring& currentRelativePath,
        const std::set<std::wstring, CaseInsensitiveLess>& expectedFiles,
        std::set<std::wstring, CaseInsensitiveLess>& seenPayloadFiles,
        bool& sawLauncher,
        size_t depth,
        size_t& entryCount,
        std::vector<Handle>& heldDirectories,
        std::wstring& diagnostic)
    {
        if (depth > MaximumPayloadDepth)
        {
            diagnostic = L"The application payload directory nesting is too deep.";
            return false;
        }

        std::wstring searchPath = currentDirectory;
        if (!searchPath.empty() && searchPath.back() != L'\\')
            searchPath.push_back(L'\\');
        searchPath.push_back(L'*');

        WIN32_FIND_DATAW data = {};
        FindHandle enumeration(FindFirstFileExW(
            searchPath.c_str(),
            FindExInfoBasic,
            &data,
            FindExSearchNameMatch,
            nullptr,
            FIND_FIRST_EX_LARGE_FETCH));
        if (!enumeration.valid())
        {
            diagnostic =
                L"Unable to enumerate application payload directory '" +
                currentDirectory + L"': " +
                WindowsErrorMessage(GetLastError());
            return false;
        }

        for (;;)
        {
            const std::wstring name(data.cFileName);
            if (name != L"." && name != L"..")
            {
                if (++entryCount > MaximumManifestEntries * 2)
                {
                    diagnostic = L"The application payload has too many entries.";
                    return false;
                }

                const std::wstring relativePath = currentRelativePath.empty()
                    ? name
                    : currentRelativePath + L"/" + name;
                const std::wstring fullPath =
                    CombinePath(applicationDirectory, relativePath);
                if ((data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                {
                    diagnostic =
                        L"Application payload entry '" + fullPath +
                        L"' is a reparse point.";
                    return false;
                }

                if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
                {
                    if (IsIgnoredMetadataSubtree(relativePath))
                    {
#ifndef WIRESOCKUI_DEVELOPMENT_BUILD
                        diagnostic =
                            L"Production application payload contains reserved "
                            L"publish or _manifest metadata subtree '" +
                            fullPath + L"'.";
                        return false;
#else
                        Handle directoryHandle;
                        if (!OpenAndValidateDirectory(
                                fullPath,
                                true,
                                true,
                                directoryHandle,
                                diagnostic))
                            return false;
                        heldDirectories.push_back(std::move(directoryHandle));
#endif
                    }
                    else
                    {
                        Handle directoryHandle;
                        if (!OpenAndValidateDirectory(
                                fullPath,
                                true,
                                true,
                                directoryHandle,
                                diagnostic))
                            return false;
                        heldDirectories.push_back(std::move(directoryHandle));
                        if (!ScanPayloadDirectory(
                                applicationDirectory,
                                fullPath,
                                relativePath,
                                expectedFiles,
                                 seenPayloadFiles,
                                sawLauncher,
                                depth + 1,
                                entryCount,
                                heldDirectories,
                                diagnostic))
                            return false;
                    }
                }
                else if (!IsIgnoredDevelopmentMetadataFile(relativePath))
                {
                    if (!seenPayloadFiles.insert(relativePath).second)
                    {
                        diagnostic =
                            L"Application payload contains a case-insensitive "
                            L"path collision at '" + fullPath + L"'.";
                        return false;
                    }

                    const bool isLauncherName =
                        currentRelativePath.empty() &&
                        EqualsIgnoreCase(name, NativeLauncherName);
                    if (isLauncherName)
                    {
                        if (name != NativeLauncherName || sawLauncher)
                        {
                            diagnostic =
                                L"Application payload contains an ambiguous "
                                L"native launcher name at '" + fullPath + L"'.";
                            return false;
                        }
                        sawLauncher = true;
                    }
                    else if (
                        expectedFiles.find(relativePath) == expectedFiles.end())
                    {
                        diagnostic =
                            L"Unexpected payload file '" + fullPath +
                            L"' is not bound by the launcher manifest.";
                        return false;
                    }
                }
            }

            if (FindNextFileW(enumeration.get(), &data) == FALSE)
            {
                const DWORD error = GetLastError();
                if (error == ERROR_NO_MORE_FILES)
                    break;
                diagnostic =
                    L"Unable to finish enumerating application payload: " +
                    WindowsErrorMessage(error);
                return false;
            }
        }
        return true;
    }

    bool ValidateAndLockPayload(
        const std::wstring& launcherPath,
        const std::wstring& applicationDirectory,
        const std::vector<ManifestEntry>& entries,
        std::vector<Handle>& heldDirectories,
        std::vector<Handle>& heldFiles,
        std::wstring& diagnostic)
    {
        std::wstring volumeRoot;
        if (!ValidateLocalFixedPath(launcherPath, volumeRoot, diagnostic))
            return false;

        Handle applicationDirectoryHandle;
        if (!OpenAndValidateDirectory(
                applicationDirectory,
                true,
                true,
                applicationDirectoryHandle,
                diagnostic) ||
            !ValidateAncestorChain(
                applicationDirectory, volumeRoot, diagnostic))
            return false;
        heldDirectories.push_back(std::move(applicationDirectoryHandle));

        Handle launcherHandle;
        if (!OpenAndValidateFile(launcherPath, launcherHandle, diagnostic))
            return false;
        heldFiles.push_back(std::move(launcherHandle));

        std::set<std::wstring, CaseInsensitiveLess> expectedFiles;
        for (const auto& entry : entries)
            expectedFiles.insert(entry.relativePath);

        size_t entryCount = 0;
        bool sawLauncher = false;
        std::set<std::wstring, CaseInsensitiveLess> seenPayloadFiles;
        if (!ScanPayloadDirectory(
                applicationDirectory,
                applicationDirectory,
                L"",
                expectedFiles,
                seenPayloadFiles,
                sawLauncher,
                0,
                entryCount,
                heldDirectories,
                diagnostic))
            return false;
        if (!sawLauncher)
        {
            diagnostic =
                L"The application payload does not contain the native launcher.";
            return false;
        }

        BCryptAlgorithm algorithm;
        if (!BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(
                algorithm.address(), BCRYPT_SHA256_ALGORITHM, nullptr, 0)))
        {
            diagnostic = L"Unable to initialize SHA-256 payload validation.";
            return false;
        }

        for (const auto& entry : entries)
        {
            const std::wstring path =
                CombinePath(applicationDirectory, entry.relativePath);
            Handle file;
            if (!OpenAndValidateFile(path, file, diagnostic))
                return false;

            std::array<BYTE, Sha256Length> actualHash = {};
            if (!HashFile(
                    algorithm.get(),
                    file.get(),
                    entry.size,
                    actualHash,
                    diagnostic))
            {
                diagnostic =
                    L"Unable to validate payload file '" + path + L"'. " +
                    diagnostic;
                return false;
            }
            if (actualHash != entry.hash)
            {
                diagnostic =
                    L"Payload file '" + path +
                    L"' does not match the embedded launcher manifest.";
                return false;
            }
            heldFiles.push_back(std::move(file));
        }
        return true;
    }

    bool IsDangerousRuntimeVariableName(const std::wstring& name)
    {
        return StartsWithIgnoreCase(name, L"COR_") ||
               StartsWithIgnoreCase(name, L"CORECLR_") ||
               StartsWithIgnoreCase(name, L"COMPLUS_") ||
               StartsWithIgnoreCase(name, L"DOTNET_") ||
               EqualsIgnoreCase(name, L"CORPATH") ||
               EqualsIgnoreCase(name, L"APPDOMAIN_MANAGER_ASM") ||
               EqualsIgnoreCase(name, L"APPDOMAIN_MANAGER_TYPE") ||
               EqualsIgnoreCase(name, L"DEVPATH");
    }

    bool SanitizeRuntimeEnvironment(std::wstring& diagnostic)
    {
        LPWCH block = GetEnvironmentStringsW();
        if (block == nullptr)
        {
            diagnostic =
                L"Unable to read the process environment: " +
                WindowsErrorMessage(GetLastError());
            return false;
        }

        std::vector<std::wstring> names;
        for (const wchar_t* cursor = block;
             *cursor != L'\0';
             cursor += wcslen(cursor) + 1)
        {
            if (*cursor == L'=')
                continue;
            const wchar_t* separator = wcschr(cursor, L'=');
            const std::wstring name(
                cursor,
                separator == nullptr ? wcslen(cursor) :
                                       static_cast<size_t>(separator - cursor));
            if (IsDangerousRuntimeVariableName(name))
                names.push_back(name);
        }
        FreeEnvironmentStringsW(block);

        for (const auto& name : names)
        {
            if (SetEnvironmentVariableW(name.c_str(), nullptr) == FALSE &&
                GetLastError() != ERROR_ENVVAR_NOT_FOUND)
            {
                diagnostic =
                    L"Unable to remove unsafe runtime environment variable '" +
                    name + L"': " + WindowsErrorMessage(GetLastError());
                return false;
            }
        }
        return true;
    }

    bool HasRequiredNetFramework(std::wstring& diagnostic)
    {
        constexpr wchar_t keyPath[] =
            L"SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full";
        const REGSAM views[] = {KEY_WOW64_64KEY, KEY_WOW64_32KEY, 0};
        for (const REGSAM view : views)
        {
            HKEY rawKey = nullptr;
            if (RegOpenKeyExW(
                    HKEY_LOCAL_MACHINE,
                    keyPath,
                    0,
                    KEY_QUERY_VALUE | view,
                    &rawKey) != ERROR_SUCCESS)
                continue;
            RegistryKey key(rawKey);

            DWORD release = 0;
            DWORD type = 0;
            DWORD size = sizeof(release);
            const LSTATUS result = RegQueryValueExW(
                key.get(),
                L"Release",
                nullptr,
                &type,
                reinterpret_cast<BYTE*>(&release),
                &size);
            if (result == ERROR_SUCCESS && type == REG_DWORD &&
                size == sizeof(release) &&
                release >= MinimumNetFrameworkRelease)
                return true;
        }

        diagnostic =
            std::wstring(RequiredNetFrameworkName) + L" or later is required.";
        return false;
    }

    bool ConfigureRuntimeInfo(
        ICLRRuntimeInfo* runtimeInfo,
        const std::wstring& configurationPath,
        std::wstring& diagnostic)
    {
        DWORD startupFlags = 0;
        std::vector<wchar_t> defaultConfiguration(32768);
        DWORD configurationLength =
            static_cast<DWORD>(defaultConfiguration.size());
        HRESULT result = runtimeInfo->GetDefaultStartupFlags(
            &startupFlags,
            defaultConfiguration.data(),
            &configurationLength);
        if (FAILED(result))
        {
            diagnostic =
                L"Unable to read the CLR startup policy: " +
                HResultMessage(result);
            return false;
        }

        result = runtimeInfo->SetDefaultStartupFlags(
            startupFlags, configurationPath.c_str());
        if (FAILED(result))
        {
            diagnostic =
                L"Unable to bind the CLR to WireSock UI's validated "
                L"configuration: " + HResultMessage(result);
            return false;
        }
        return true;
    }

    bool ExecuteManagedApplication(
        const std::wstring& applicationDirectory,
        const std::wstring& managedArgument,
        bool nativeHostSelfTestDiagnosticsEnabled,
        DWORD& exitCode,
        std::wstring& diagnostic)
    {
        std::vector<wchar_t> systemDirectory(32768);
        const UINT systemLength = GetSystemDirectoryW(
            systemDirectory.data(),
            static_cast<UINT>(systemDirectory.size()));
        if (systemLength == 0 ||
            static_cast<size_t>(systemLength) >= systemDirectory.size())
        {
            diagnostic = L"Unable to resolve the Windows system directory.";
            return false;
        }
        const std::wstring mscoreePath =
            std::wstring(systemDirectory.data(), systemLength) +
            L"\\mscoree.dll";
        Module mscoree(LoadLibraryExW(
            mscoreePath.c_str(), nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32));
        if (mscoree.get() == nullptr)
        {
            diagnostic =
                L"Unable to load the system CLR host: " +
                WindowsErrorMessage(GetLastError());
            return false;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"system CLR host loaded");

        using ClrCreateInstanceFunction =
            HRESULT(STDAPICALLTYPE*)(REFCLSID, REFIID, LPVOID*);
        const auto createInstance =
            reinterpret_cast<ClrCreateInstanceFunction>(
                GetProcAddress(mscoree.get(), "CLRCreateInstance"));
        if (createInstance == nullptr)
        {
            diagnostic = L"The system CLR host has no CLRCreateInstance entry.";
            return false;
        }

        ComPointer<ICLRMetaHost> metaHost;
        HRESULT result = createInstance(
            ClsidClrMetaHost,
            IidClrMetaHost,
            reinterpret_cast<void**>(metaHost.address()));
        if (FAILED(result))
        {
            diagnostic =
                L"Unable to initialize the CLR meta-host: " +
                HResultMessage(result);
            return false;
        }

        ComPointer<ICLRRuntimeInfo> runtimeInfo;
        result = metaHost.get()->GetRuntime(
            RuntimeVersion,
            __uuidof(ICLRRuntimeInfo),
            reinterpret_cast<void**>(runtimeInfo.address()));
        if (FAILED(result))
        {
            diagnostic =
                L"Unable to locate .NET Framework CLR v4: " +
                HResultMessage(result);
            return false;
        }

        BOOL loadable = FALSE;
        result = runtimeInfo.get()->IsLoadable(&loadable);
        if (FAILED(result) || loadable == FALSE)
        {
            diagnostic = L".NET Framework CLR v4 cannot be loaded safely.";
            return false;
        }

        const std::wstring configurationPath =
            CombinePath(applicationDirectory, ApplicationConfigurationName);
        if (!ConfigureRuntimeInfo(
                runtimeInfo.get(), configurationPath, diagnostic))
            return false;

        ComPointer<ICLRRuntimeHost> runtimeHost;
        result = runtimeInfo.get()->GetInterface(
            ClsidClrRuntimeHost,
            IidClrRuntimeHost,
            reinterpret_cast<void**>(runtimeHost.address()));
        if (FAILED(result))
        {
            diagnostic =
                L"Unable to create the .NET Framework runtime host: " +
                HResultMessage(result);
            return false;
        }

        result = runtimeHost.get()->Start();
        if (FAILED(result))
        {
            diagnostic =
                L"Unable to start .NET Framework CLR v4: " +
                HResultMessage(result);
            return false;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"CLR started");

        const std::wstring managedAssemblyPath =
            CombinePath(applicationDirectory, ManagedAssemblyName);
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"managed entry point invoking");
        result = runtimeHost.get()->ExecuteInDefaultAppDomain(
            managedAssemblyPath.c_str(),
            ManagedTypeName,
            ManagedMethodName,
            managedArgument.c_str(),
            &exitCode);
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"managed entry point returned");
        if (FAILED(result))
        {
            diagnostic =
                L"The validated WireSock UI managed entry point failed: " +
                HResultMessage(result);
            return false;
        }
        return true;
    }
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR commandLine, int)
{
    bool nativeHostSelfTestRequested = false;
    try
    {
        nativeHostSelfTestRequested =
            IsNativeHostSelfTestCommandLine(commandLine);
        const bool nativeHostSelfTestDiagnosticsEnabled =
            nativeHostSelfTestRequested &&
            IsNativeHostSelfTestDiagnosticsEnabled();
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"command accepted");
        const std::wstring managedArgument =
            nativeHostSelfTestRequested
                ? ManagedNativeHostSelfTestToken
                : L"";
        if (SetDefaultDllDirectories(
                LOAD_LIBRARY_SEARCH_SYSTEM32 | LOAD_LIBRARY_SEARCH_USER_DIRS) ==
            FALSE)
        {
            ShowStartupError(
                L"Unable to restrict the process DLL search path: " +
                    WindowsErrorMessage(GetLastError()),
                nativeHostSelfTestRequested);
            return 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"DLL search policy restricted");
        if (!IsCurrentProcessAdministrator())
        {
            ShowStartupError(
                L"The native WireSock UI launcher is not running with an "
                L"administrator token.",
                nativeHostSelfTestRequested);
            return 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"administrator token verified");

        std::wstring diagnostic;
        if (!HasRequiredNetFramework(diagnostic))
        {
            ShowStartupError(diagnostic, nativeHostSelfTestRequested);
            return 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L".NET Framework prerequisite verified");

        std::vector<wchar_t> moduleBuffer(32768);
        const DWORD moduleLength = GetModuleFileNameW(
            nullptr,
            moduleBuffer.data(),
            static_cast<DWORD>(moduleBuffer.size()));
        if (moduleLength == 0 ||
            static_cast<size_t>(moduleLength) >= moduleBuffer.size())
        {
            ShowStartupError(
                L"Unable to resolve the WireSock UI launcher path.",
                nativeHostSelfTestRequested);
            return 1;
        }

        const std::wstring launcherPath(moduleBuffer.data(), moduleLength);
        const std::wstring applicationDirectory = ParentPath(launcherPath);
        if (applicationDirectory.empty())
        {
            ShowStartupError(
                L"Unable to resolve the WireSock UI application directory.",
                nativeHostSelfTestRequested);
            return 1;
        }

        std::vector<ManifestEntry> manifestEntries;
        if (!ParsePayloadManifest(manifestEntries, diagnostic))
        {
            ShowStartupError(diagnostic, nativeHostSelfTestRequested);
            return nativeHostSelfTestRequested
                ? PayloadValidationFailureExitCode
                : 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"payload manifest parsed");

        std::vector<Handle> heldDirectories;
        std::vector<Handle> heldFiles;
        if (!ValidateAndLockPayload(
                launcherPath,
                applicationDirectory,
                manifestEntries,
                heldDirectories,
                heldFiles,
                diagnostic))
        {
            ShowStartupError(diagnostic, nativeHostSelfTestRequested);
            return nativeHostSelfTestRequested
                ? PayloadValidationFailureExitCode
                : 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"payload validated and locked");

        if (!SanitizeRuntimeEnvironment(diagnostic))
        {
            ShowStartupError(diagnostic, nativeHostSelfTestRequested);
            return 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"runtime environment sanitized");
        if (SetCurrentDirectoryW(applicationDirectory.c_str()) == FALSE)
        {
            ShowStartupError(
                L"Unable to select the validated application directory: " +
                    WindowsErrorMessage(GetLastError()),
                nativeHostSelfTestRequested);
            return 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"validated working directory selected");

        const HRESULT comResult =
            CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (FAILED(comResult))
        {
            ShowStartupError(
                L"Unable to initialize the UI apartment: " +
                    HResultMessage(comResult),
                nativeHostSelfTestRequested);
            return 1;
        }
        WriteNativeHostSelfTestPhase(
            nativeHostSelfTestDiagnosticsEnabled,
            L"UI apartment initialized");

        DWORD exitCode = 1;
        const bool executed = ExecuteManagedApplication(
            applicationDirectory,
            managedArgument,
            nativeHostSelfTestDiagnosticsEnabled,
            exitCode,
            diagnostic);
        CoUninitialize();
        if (!executed)
        {
            ShowStartupError(diagnostic, nativeHostSelfTestRequested);
            return 1;
        }
        return static_cast<int>(exitCode);
    }
    catch (const std::exception& exception)
    {
        const int required = MultiByteToWideChar(
            CP_UTF8, 0, exception.what(), -1, nullptr, 0);
        std::wstring detail = L"Unexpected native startup failure.";
        if (required > 1)
        {
            std::vector<wchar_t> converted(static_cast<size_t>(required));
            if (MultiByteToWideChar(
                    CP_UTF8,
                    0,
                    exception.what(),
                    -1,
                    converted.data(),
                    required) > 0)
                detail.assign(converted.data());
        }
        ShowStartupError(detail, nativeHostSelfTestRequested);
        return 1;
    }
    catch (...)
    {
        ShowStartupError(
            L"Unexpected native startup failure.",
            nativeHostSelfTestRequested);
        return 1;
    }
}
