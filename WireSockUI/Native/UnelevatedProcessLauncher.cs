using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace WireSockUI.Native
{
    /// <summary>
    /// Starts trusted Windows shell operations with the interactive shell's medium-integrity
    /// token. The application itself is elevated, so ordinary shell activation would otherwise
    /// give protocol handlers and shell extensions administrator privileges.
    /// </summary>
    internal static class UnelevatedProcessLauncher
    {
        private const uint ProcessQueryLimitedInformation = 0x1000;
        private const uint TokenAssignPrimary = 0x0001;
        private const uint TokenDuplicate = 0x0002;
        private const uint TokenQuery = 0x0008;
        private const uint TokenAdjustDefault = 0x0080;
        private const uint TokenAdjustSessionId = 0x0100;
        private const uint CreateUnicodeEnvironment = 0x00000400;
        private const uint LogonWithProfile = 0x00000001;
        private const int SecurityImpersonation = 2;
        private const int TokenPrimary = 1;
        private const int TokenElevationInformationClass = 20;
        private const int MaximumTargetLength = 4096;

        internal static bool OpenHttpsUrl(string value, out string diagnostic)
        {
            if (!TryValidateHttpsUrl(value, out var uri, out diagnostic))
                return false;

            return TryStartExplorer(uri.AbsoluteUri, out diagnostic);
        }

        internal static bool TryValidateHttpsUrl(string value, out Uri uri, out string diagnostic)
        {
            uri = null;
            diagnostic = null;
            if (string.IsNullOrWhiteSpace(value) || value.Length > MaximumTargetLength)
            {
                diagnostic = "The web address is empty or exceeds the supported length.";
                return false;
            }

            foreach (var character in value)
            {
                if (char.IsControl(character) || char.IsSurrogate(character))
                {
                    diagnostic = "The web address contains unsupported control characters.";
                    return false;
                }
            }

            if (!Uri.TryCreate(value, UriKind.Absolute, out var parsed) ||
                !string.Equals(parsed.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrWhiteSpace(parsed.Host) ||
                parsed.HostNameType == UriHostNameType.Unknown ||
                !string.IsNullOrEmpty(parsed.UserInfo) ||
                parsed.IsFile)
            {
                diagnostic = "Only absolute HTTPS addresses without embedded credentials are allowed.";
                return false;
            }

            uri = parsed;
            return true;
        }

        private static bool TryStartExplorer(string target, out string diagnostic)
        {
            diagnostic = null;
            IntPtr shellProcess = IntPtr.Zero;
            IntPtr shellToken = IntPtr.Zero;
            IntPtr primaryToken = IntPtr.Zero;
            IntPtr environment = IntPtr.Zero;
            try
            {
                var shellWindow = GetShellWindow();
                if (shellWindow == IntPtr.Zero)
                {
                    diagnostic = "The interactive Windows shell is not available.";
                    return false;
                }

                GetWindowThreadProcessId(shellWindow, out var shellProcessId);
                if (shellProcessId == 0)
                {
                    diagnostic = "The interactive Windows shell process could not be identified.";
                    return false;
                }

                shellProcess = OpenProcess(ProcessQueryLimitedInformation, false, shellProcessId);
                if (shellProcess == IntPtr.Zero)
                {
                    diagnostic =
                        $"The interactive Windows shell could not be opened: {LastWin32ErrorMessage()}";
                    return false;
                }

                if (!TryGetWindowsExplorerPath(out var explorerPath, out diagnostic) ||
                    !TryVerifyShellImage(shellProcess, explorerPath, out diagnostic))
                    return false;

                if (!OpenProcessToken(
                        shellProcess,
                        TokenAssignPrimary | TokenDuplicate | TokenQuery,
                        out shellToken))
                {
                    diagnostic =
                        $"The interactive Windows shell token could not be opened: {LastWin32ErrorMessage()}";
                    return false;
                }

                if (!TryEnsureTokenIsUnelevated(shellToken, out diagnostic))
                    return false;

                if (!DuplicateTokenEx(
                        shellToken,
                        TokenAssignPrimary | TokenDuplicate | TokenQuery |
                        TokenAdjustDefault | TokenAdjustSessionId,
                        IntPtr.Zero,
                        SecurityImpersonation,
                        TokenPrimary,
                        out primaryToken))
                {
                    diagnostic =
                        $"The interactive Windows shell token could not be duplicated: {LastWin32ErrorMessage()}";
                    return false;
                }

                if (!CreateEnvironmentBlock(out environment, primaryToken, false))
                {
                    diagnostic =
                        $"The interactive user environment could not be created: {LastWin32ErrorMessage()}";
                    return false;
                }

                var startup = new StartupInfo
                {
                    Size = Marshal.SizeOf(typeof(StartupInfo)),
                    Desktop = @"winsta0\default"
                };
                var commandLine = new StringBuilder(
                    QuoteWindowsArgument(explorerPath) + " " + QuoteWindowsArgument(target));
                if (!CreateProcessWithTokenW(
                        primaryToken,
                        LogonWithProfile,
                        explorerPath,
                        commandLine,
                        CreateUnicodeEnvironment,
                        environment,
                        Path.GetDirectoryName(explorerPath),
                        ref startup,
                        out var processInformation))
                {
                    diagnostic =
                        $"Windows Explorer could not be started without elevation: {LastWin32ErrorMessage()}";
                    return false;
                }

                CloseHandle(processInformation.Thread);
                CloseHandle(processInformation.Process);
                return true;
            }
            catch (Exception ex)
            {
                diagnostic = $"The shell operation could not be started safely: {ex.Message}";
                return false;
            }
            finally
            {
                if (environment != IntPtr.Zero)
                    DestroyEnvironmentBlock(environment);
                if (primaryToken != IntPtr.Zero)
                    CloseHandle(primaryToken);
                if (shellToken != IntPtr.Zero)
                    CloseHandle(shellToken);
                if (shellProcess != IntPtr.Zero)
                    CloseHandle(shellProcess);
            }
        }

        private static bool TryGetWindowsExplorerPath(out string explorerPath, out string diagnostic)
        {
            explorerPath = null;
            diagnostic = null;
            var buffer = new StringBuilder(32768);
            var length = GetWindowsDirectory(buffer, (uint)buffer.Capacity);
            if (length == 0 || length >= buffer.Capacity)
            {
                diagnostic = $"The Windows directory could not be resolved: {LastWin32ErrorMessage()}";
                return false;
            }

            explorerPath = Path.Combine(buffer.ToString(), "explorer.exe");
            if (!Program.TryValidateTrustedFilePath(explorerPath, "Windows Explorer", out diagnostic))
                return false;

            return true;
        }

        private static bool TryVerifyShellImage(
            IntPtr shellProcess,
            string expectedExplorerPath,
            out string diagnostic)
        {
            diagnostic = null;
            var capacity = 32768;
            var imagePath = new StringBuilder(capacity);
            if (!QueryFullProcessImageName(shellProcess, 0, imagePath, ref capacity))
            {
                diagnostic =
                    $"The interactive Windows shell image could not be verified: {LastWin32ErrorMessage()}";
                return false;
            }

            string actualPath;
            string expectedPath;
            try
            {
                actualPath = Path.GetFullPath(imagePath.ToString());
                expectedPath = Path.GetFullPath(expectedExplorerPath);
            }
            catch (Exception ex)
            {
                diagnostic = $"The interactive Windows shell image path is invalid: {ex.Message}";
                return false;
            }

            if (string.Equals(actualPath, expectedPath, StringComparison.OrdinalIgnoreCase))
                return true;

            diagnostic =
                $"The interactive Windows shell is '{actualPath}', not the trusted Windows Explorer executable.";
            return false;
        }

        private static bool TryEnsureTokenIsUnelevated(IntPtr token, out string diagnostic)
        {
            diagnostic = null;
            var elevation = new TokenElevation();
            if (!GetTokenInformation(
                    token,
                    TokenElevationInformationClass,
                    ref elevation,
                    Marshal.SizeOf(typeof(TokenElevation)),
                    out _))
            {
                diagnostic =
                    $"The interactive Windows shell integrity could not be verified: {LastWin32ErrorMessage()}";
                return false;
            }

            if (elevation.IsElevated == 0)
                return true;

            diagnostic =
                "The interactive Windows shell is elevated, so the requested shell operation was blocked.";
            return false;
        }

        internal static string QuoteWindowsArgument(string value)
        {
            if (value == null)
                throw new ArgumentNullException(nameof(value));
            if (value.Length == 0)
                return "\"\"";
            if (value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
                return value;

            var result = new StringBuilder(value.Length + 2);
            result.Append('"');
            var backslashes = 0;
            foreach (var character in value)
            {
                if (character == '\\')
                {
                    backslashes++;
                    continue;
                }
                if (character == '"')
                {
                    result.Append('\\', backslashes * 2 + 1);
                    result.Append('"');
                    backslashes = 0;
                    continue;
                }

                result.Append('\\', backslashes);
                backslashes = 0;
                result.Append(character);
            }

            result.Append('\\', backslashes * 2);
            result.Append('"');
            return result.ToString();
        }

        private static string LastWin32ErrorMessage()
        {
            return new Win32Exception(Marshal.GetLastWin32Error()).Message;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo
        {
            public int Size;
            public string Reserved;
            public string Desktop;
            public string Title;
            public int X;
            public int Y;
            public int XSize;
            public int YSize;
            public int XCountChars;
            public int YCountChars;
            public int FillAttribute;
            public int Flags;
            public short ShowWindow;
            public short Reserved2;
            public IntPtr Reserved2Pointer;
            public IntPtr StandardInput;
            public IntPtr StandardOutput;
            public IntPtr StandardError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation
        {
            public IntPtr Process;
            public IntPtr Thread;
            public uint ProcessId;
            public uint ThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TokenElevation
        {
            public int IsElevated;
        }

        [DllImport("user32.dll")]
        private static extern IntPtr GetShellWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(
            IntPtr process,
            uint flags,
            StringBuilder executableName,
            ref int size);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr process, uint desiredAccess, out IntPtr token);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DuplicateTokenEx(
            IntPtr existingToken,
            uint desiredAccess,
            IntPtr tokenAttributes,
            int impersonationLevel,
            int tokenType,
            out IntPtr newToken);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(
            IntPtr token,
            int informationClass,
            ref TokenElevation information,
            int informationLength,
            out int returnLength);

        [DllImport("userenv.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateEnvironmentBlock(
            out IntPtr environment,
            IntPtr token,
            [MarshalAs(UnmanagedType.Bool)] bool inherit);

        [DllImport("userenv.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyEnvironmentBlock(IntPtr environment);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessWithTokenW(
            IntPtr token,
            uint logonFlags,
            string applicationName,
            StringBuilder commandLine,
            uint creationFlags,
            IntPtr environment,
            string currentDirectory,
            ref StartupInfo startupInfo,
            out ProcessInformation processInformation);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetWindowsDirectory(StringBuilder buffer, uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }
}
