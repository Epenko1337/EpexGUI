Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'MsiTest.AccessControl.psm1')

if ($null -eq ('WireSockUI.MsiTest.KnownFolderNativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace WireSockUI.MsiTest
{
    public static class KnownFolderNativeMethods
    {
        private const uint DriveFixed = 3;

        [DllImport("shell32.dll")]
        private static extern int SHGetKnownFolderPath(
            ref Guid folderId,
            uint flags,
            IntPtr token,
            out IntPtr path);

        [DllImport(
            "kernel32.dll",
            CharSet = CharSet.Unicode,
            SetLastError = true)]
        private static extern bool GetVolumePathNameW(
            string fileName,
            StringBuilder volumePathName,
            uint bufferLength);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern uint GetDriveTypeW(string rootPathName);

        [DllImport(
            "kernel32.dll",
            CharSet = CharSet.Unicode,
            SetLastError = true)]
        private static extern bool GetVolumeInformationW(
            string rootPathName,
            StringBuilder volumeName,
            uint volumeNameSize,
            out uint volumeSerialNumber,
            out uint maximumComponentLength,
            out uint fileSystemFlags,
            StringBuilder fileSystemName,
            uint fileSystemNameSize);

        public static string GetKnownFolderPath(Guid folderId)
        {
            IntPtr path = IntPtr.Zero;
            try
            {
                int result = SHGetKnownFolderPath(
                    ref folderId,
                    0,
                    IntPtr.Zero,
                    out path);
                if (result < 0)
                    Marshal.ThrowExceptionForHR(result);
                if (path == IntPtr.Zero)
                    throw new InvalidOperationException(
                        "SHGetKnownFolderPath returned a null path.");

                string value = Marshal.PtrToStringUni(path);
                if (String.IsNullOrWhiteSpace(value))
                    throw new InvalidOperationException(
                        "SHGetKnownFolderPath returned an empty path.");
                return value;
            }
            finally
            {
                if (path != IntPtr.Zero)
                    Marshal.FreeCoTaskMem(path);
            }
        }

        public static void AssertLocalFixedNtfsPath(string path)
        {
            var volumePath = new StringBuilder(32768);
            if (!GetVolumePathNameW(
                    path,
                    volumePath,
                    checked((uint)volumePath.Capacity)))
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Unable to resolve the path's volume.");
            if (GetDriveTypeW(volumePath.ToString()) != DriveFixed)
                throw new InvalidOperationException(
                    "The path is not on a local fixed drive.");

            var fileSystemName = new StringBuilder(64);
            uint serialNumber;
            uint maximumComponentLength;
            uint fileSystemFlags;
            if (!GetVolumeInformationW(
                    volumePath.ToString(),
                    null,
                    0,
                    out serialNumber,
                    out maximumComponentLength,
                    out fileSystemFlags,
                    fileSystemName,
                    checked((uint)fileSystemName.Capacity)))
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Unable to inspect the path's filesystem.");
            if (!String.Equals(
                    fileSystemName.ToString(),
                    "NTFS",
                    StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(
                    "The path is not on an NTFS volume.");
        }
    }
}
'@
}

function Get-MsiCommonProgramsFolderId {
    # FOLDERID_CommonPrograms is the machine-wide Start Menu Programs folder.
    return [Guid]'0139D44E-6AFE-49F2-8690-3DAFCAE6FFB8'
}

function Get-MsiCommonDesktopFolderId {
    # FOLDERID_PublicDesktop is the machine-wide desktop folder.
    return [Guid]'C4AA340D-F20F-4863-AFEF-F87EF2E6BA25'
}

function Get-MsiKnownFolderPath {
    param([Parameter(Mandatory = $true)][Guid]$FolderId)

    return [WireSockUI.MsiTest.KnownFolderNativeMethods]::GetKnownFolderPath(
        $FolderId)
}

function Test-MsiAncestorFileSystemRightsSafe {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemRights]$Rights
    )

    # An ancestor may allow creating sibling entries without making an existing
    # child replaceable. Delete, DELETE_CHILD, DACL/owner changes, GENERIC_ALL,
    # and any unknown access-mask bits remain fail-closed.
    [Int64]$safeAncestorRightsMask =
        [Int64][Security.AccessControl.FileSystemRights]::ReadAndExecute -bor
        [Int64][Security.AccessControl.FileSystemRights]::Synchronize -bor
        [Int64][Security.AccessControl.FileSystemRights]::Write -bor
        0x80000000L -bor
        0x40000000L -bor
        0x20000000L
    [Int64]$normalizedRights = [Int64]$Rights -band 0xffffffffL
    return (
        ($normalizedRights -band $safeAncestorRightsMask) -eq
        $normalizedRights)
}

function Test-MsiDirectoryCreationCapableFileSystemRights {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemRights]$Rights
    )

    # FILE_ADD_SUBDIRECTORY is the right that can recreate a deleted directory.
    # GENERIC_WRITE and GENERIC_ALL expand to it during an access check.
    [Int64]$directoryCreationMask =
        [Int64][Security.AccessControl.FileSystemRights]::AppendData -bor
        0x40000000L -bor
        0x10000000L
    [Int64]$normalizedRights = [Int64]$Rights -band 0xffffffffL
    return (($normalizedRights -band $directoryCreationMask) -ne 0)
}

function Test-MsiEntryDeleteCapableFileSystemRights {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemRights]$Rights
    )

    # DELETE applies to this directory. DELETE_CHILD only applies to entries
    # below it and therefore does not combine with parent creation rights to
    # replace the directory itself.
    [Int64]$deleteMask =
        [Int64][Security.AccessControl.FileSystemRights]::Delete
    [Int64]$normalizedRights = [Int64]$Rights -band 0xffffffffL
    return (($normalizedRights -band $deleteMask) -ne 0)
}

function Test-MsiDirectoryAccessRuleSafe {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemAccessRule]$Rule,
        [Parameter(Mandatory = $true)]
        [bool]$IsLeaf,
        [Parameter(Mandatory = $true)]
        [string[]]$TrustedWriterSids
    )

    if ($Rule.AccessControlType -ne
        [Security.AccessControl.AccessControlType]::Allow) {
        return $true
    }

    $ruleSid = $Rule.IdentityReference.Value
    if ($TrustedWriterSids -contains $ruleSid) {
        return $true
    }

    $isInheritOnly =
        ($Rule.PropagationFlags -band
            [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0
    if ($isInheritOnly) {
        if (-not $IsLeaf) {
            # The effective inherited rule is inspected on each descendant.
            return $true
        }
        if ($ruleSid -eq 'S-1-3-0') {
            # CREATOR OWNER does not grant creation. It only substitutes the
            # child's owner, and untrusted creation rights are rejected below.
            return $true
        }
        # At the leaf, an inherit-only ACE becomes effective on the file or
        # directory that Windows Installer creates.
        return -not (Test-MsiReplacementCapableFileSystemRights `
            -Rights $Rule.FileSystemRights)
    }

    if ($IsLeaf) {
        # Delete-only access can cause denial of service, but not replacement
        # while untrusted creation in this directory and its parent is denied.
        return -not (Test-MsiReplacementCapableFileSystemRights `
            -Rights $Rule.FileSystemRights)
    }
    return Test-MsiAncestorFileSystemRightsSafe `
        -Rights $Rule.FileSystemRights
}

function Assert-MsiTrustedDirectoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path -notmatch '^[A-Za-z]:[\\/]') {
        throw (
            "Windows did not expose a fully qualified local-drive " +
            "$Description path.")
    }
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if (-not [IO.Directory]::Exists($resolvedPath)) {
        throw "The $Description path '$resolvedPath' does not exist."
    }
    try {
        [WireSockUI.MsiTest.KnownFolderNativeMethods]::
            AssertLocalFixedNtfsPath($resolvedPath)
    }
    catch {
        throw (
            "The $Description path '$resolvedPath' must resolve through an " +
            "ordinary trusted-owner directory chain on local fixed NTFS: " +
            $_.Exception.Message)
    }

    $trustedOwnerSids = @(
        'S-1-5-18',
        'S-1-5-32-544',
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    )
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent(
        [Security.Principal.TokenAccessLevels]::Query -bor
        [Security.Principal.TokenAccessLevels]::Duplicate)
    try {
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        if (-not $principal.IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator) -or
            $null -eq $identity.User) {
            throw 'Trusted MSI path validation requires an elevated administrator.'
        }
        $trustedWriterSids = @($trustedOwnerSids)
    }
    finally {
        $identity.Dispose()
    }

    $currentPath = $resolvedPath
    $isLeaf = $true
    $isImmediateParent = $false
    $leafHasUntrustedDeleteRights = $false
    while (-not [string]::IsNullOrEmpty($currentPath)) {
        $entry = Get-Item -LiteralPath $currentPath -Force
        if (-not $entry.PSIsContainer -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw (
                "The $Description path traverses a non-directory or reparse " +
                "point at '$currentPath'.")
        }

        $acl = Get-Acl -LiteralPath $currentPath
        if (-not (Test-MsiSecurityDescriptorHasNonNullDacl `
                -Security $acl)) {
            throw (
                "The $Description path has an absent or unreadable DACL at " +
                "'$currentPath'.")
        }
        $ownerSid = $acl.GetOwner(
            [Security.Principal.SecurityIdentifier]).Value
        if (-not ($trustedOwnerSids -contains $ownerSid)) {
            throw (
                "The $Description path has an untrusted owner SID " +
                "'$ownerSid' at '$currentPath'.")
        }
        $accessRules = $acl.GetAccessRules(
            $true,
            $true,
            [Security.Principal.SecurityIdentifier])
        foreach ($rule in $accessRules) {
            $ruleSid = $rule.IdentityReference.Value
            if (-not (Test-MsiDirectoryAccessRuleSafe `
                    -Rule $rule `
                    -IsLeaf $isLeaf `
                    -TrustedWriterSids $trustedWriterSids)) {
                throw (
                    "The $Description path grants replaceable access to SID " +
                    "'$ruleSid' at '$currentPath'.")
            }

            $isUntrustedEffectiveAllow =
                $rule.AccessControlType -eq
                    [Security.AccessControl.AccessControlType]::Allow -and
                ($rule.PropagationFlags -band
                    [Security.AccessControl.PropagationFlags]::InheritOnly) -eq
                    0 -and
                -not ($trustedWriterSids -contains $ruleSid)
            if ($isUntrustedEffectiveAllow -and $isLeaf -and
                (Test-MsiEntryDeleteCapableFileSystemRights `
                    -Rights $rule.FileSystemRights)) {
                $leafHasUntrustedDeleteRights = $true
            }
            elseif ($isUntrustedEffectiveAllow -and $isImmediateParent -and
                $leafHasUntrustedDeleteRights -and
                (Test-MsiDirectoryCreationCapableFileSystemRights `
                    -Rights $rule.FileSystemRights)) {
                throw (
                    "The $Description path can be deleted and recreated by " +
                    "untrusted principals through '$currentPath'.")
            }
        }

        $parent = [IO.Directory]::GetParent($currentPath)
        if ($null -eq $parent) {
            break
        }
        $currentPath = $parent.FullName
        if ($isLeaf) {
            $isLeaf = $false
            $isImmediateParent = $true
        }
        else {
            $isImmediateParent = $false
        }
    }
    return $resolvedPath
}

function Get-MsiTrustedKnownFolderPath {
    param(
        [Parameter(Mandatory = $true)][Guid]$FolderId,
        [Parameter(Mandatory = $true)][string]$Description
    )

    return Assert-MsiTrustedDirectoryPath `
        -Path (Get-MsiKnownFolderPath -FolderId $FolderId) `
        -Description $Description
}

Export-ModuleMember -Function @(
    'Assert-MsiTrustedDirectoryPath',
    'Get-MsiCommonDesktopFolderId',
    'Get-MsiCommonProgramsFolderId',
    'Get-MsiKnownFolderPath',
    'Get-MsiTrustedKnownFolderPath'
)
