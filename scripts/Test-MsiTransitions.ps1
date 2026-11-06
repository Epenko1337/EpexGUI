[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaselineX64UwpMsiPath,

    [Parameter(Mandatory = $true)]
    [string]$BaselineX64UwpValidationMetadataPath,

    [Parameter(Mandatory = $true)]
    [string]$CurrentX64NoUwpMsiPath,

    [Parameter(Mandatory = $true)]
    [string]$CurrentX64NoUwpValidationMetadataPath,

    [Parameter(Mandatory = $true)]
    [string]$CurrentX64UwpMsiPath,

    [Parameter(Mandatory = $true)]
    [string]$CurrentX64UwpValidationMetadataPath,

    [Parameter(Mandatory = $true)]
    [string]$BaselineX86NoUwpMsiPath,

    [Parameter(Mandatory = $true)]
    [string]$BaselineX86NoUwpValidationMetadataPath,

    [Parameter(Mandatory = $true)]
    [switch]$EphemeralMachine
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'MsiTest.AccessControl.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'MsiTest.Diagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'MsiTest.KnownFolders.psm1') -Force

$upgradeCode = '{5C1DDAE5-6681-41BF-B153-AB2952AA6DF1}'
$applicationDirectoryName = 'WireSock Foundation WireSock UI'
$validationScriptPath = Join-Path $PSScriptRoot 'Test-MsiPackage.ps1'
$operationTimeoutMilliseconds = 600000
$maximumMsiBytes = 2GB - 1

if (-not $EphemeralMachine) {
    throw 'This destructive transition test requires the explicit -EphemeralMachine guard.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The MSI transition test requires Windows.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'The x86-to-x64 transition test requires 64-bit Windows.'
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent(
    [Security.Principal.TokenAccessLevels]::Query -bor
    [Security.Principal.TokenAccessLevels]::Duplicate)
try {
    $principal =
        [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    if (-not $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator) -or
        $null -eq $currentIdentity.User) {
        throw 'The MSI transition test must run from an elevated administrator shell.'
    }
}
finally {
    $currentIdentity.Dispose()
}

if ($null -eq ('WireSockUI.MsiTransitionTest.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace WireSockUI.MsiTransitionTest
{
    public static class NativeMethods
    {
        private const uint ErrorNoMoreItems = 259;

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        public static extern int MsiQueryProductState(string productCode);

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern uint MsiEnumRelatedProducts(
            string upgradeCode,
            uint reserved,
            uint productIndex,
            StringBuilder productCode);

        public static string[] GetRelatedProducts(string upgradeCode)
        {
            var products = new System.Collections.Generic.List<string>();
            for (uint index = 0; index < 1024; ++index)
            {
                var productCode = new StringBuilder(39);
                uint result = MsiEnumRelatedProducts(
                    upgradeCode,
                    0,
                    index,
                    productCode);
                if (result == ErrorNoMoreItems)
                    return products.ToArray();
                if (result != 0)
                    throw new Win32Exception(
                        checked((int)result),
                        "Unable to enumerate related Windows Installer products.");
                products.Add(productCode.ToString().ToUpperInvariant());
            }

            throw new InvalidOperationException(
                "Related-product enumeration exceeded its 1,024-product bound.");
        }

    }
}
'@
}

function ConvertTo-WindowsCommandLineArgument {
    param([string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-ProductState {
    param([string]$ProductCode)

    return [WireSockUI.MsiTransitionTest.NativeMethods]::MsiQueryProductState(
        $ProductCode)
}

function Get-RelatedProducts {
    return @(
        [WireSockUI.MsiTransitionTest.NativeMethods]::GetRelatedProducts(
            $upgradeCode)
    )
}

function Get-TrustedNativeProgramFilesPath {
    if ([Environment]::Is64BitProcess) {
        return Get-MsiTrustedKnownFolderPath `
            -FolderId ([Guid]'6D809377-6AF0-444B-8957-A3773F02200E') `
            -Description 'native Program Files'
    }

    $baseKey = $null
    $currentVersionKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        $currentVersionKey = $baseKey.OpenSubKey(
            'SOFTWARE\Microsoft\Windows\CurrentVersion',
            $false)
        if ($null -eq $currentVersionKey) {
            throw 'The native Windows CurrentVersion registry key is missing.'
        }
        $programFilesPath =
            $currentVersionKey.GetValue(
                'ProgramFilesDir',
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($programFilesPath -isnot [string]) {
            throw 'The native ProgramFilesDir registry value is missing or has an invalid type.'
        }
        return Assert-MsiTrustedDirectoryPath `
            -Path $programFilesPath `
            -Description 'native Program Files'
    }
    finally {
        if ($null -ne $currentVersionKey) {
            $currentVersionKey.Dispose()
        }
        if ($null -ne $baseKey) {
            $baseKey.Dispose()
        }
    }
}

function Test-FileSystemEntryExists {
    param([string]$Path)

    try {
        [void][IO.File]::GetAttributes($Path)
        return $true
    }
    catch [IO.FileNotFoundException] {
        return $false
    }
    catch [IO.DirectoryNotFoundException] {
        return $false
    }
}

function Assert-RelatedProducts {
    param([string[]]$ExpectedProductCodes)

    $expected = @($ExpectedProductCodes | Sort-Object -Unique)
    $actual = @(Get-RelatedProducts | Sort-Object -Unique)
    $differences = @(
        Compare-Object -ReferenceObject $expected -DifferenceObject $actual
    )
    if ($differences.Count -ne 0) {
        $description = (
            $differences |
                ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }
        ) -join ', '
        throw "Related Windows Installer products differ from expectation: $description"
    }
}

function Assert-ProductInstalled {
    param([object]$Package)

    $state = Get-ProductState -ProductCode $Package.ProductCode
    if ($state -ne 5) {
        throw "Product $($Package.ProductCode) has installer state $state; expected installed state 5."
    }
}

function Assert-ProductAbsent {
    param([object]$Package)

    $state = Get-ProductState -ProductCode $Package.ProductCode
    if ($state -ne -1) {
        throw "Product $($Package.ProductCode) remains registered with installer state $state."
    }
}

function Read-PackageSpec {
    param(
        [string]$MsiPath,
        [string]$ValidationMetadataPath,
        [ValidateSet('x86', 'x64')]
        [string]$ExpectedArchitecture,
        [ValidateSet('uwp', 'no-uwp')]
        [string]$ExpectedFlavor,
        [string]$Label
    )

    $resolvedMsiPath = [IO.Path]::GetFullPath($MsiPath)
    $resolvedMetadataPath = [IO.Path]::GetFullPath($ValidationMetadataPath)
    if (-not [IO.File]::Exists($resolvedMsiPath) -or
        -not [IO.File]::Exists($resolvedMetadataPath)) {
        throw "$Label MSI and validation metadata must both exist."
    }
    $msiFile = Get-Item -LiteralPath $resolvedMsiPath -Force
    $metadataFile = Get-Item -LiteralPath $resolvedMetadataPath -Force
    if (($msiFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $msiFile.Length -lt 1 -or
        $msiFile.Length -gt $maximumMsiBytes) {
        throw "$Label MSI is a reparse point, empty, or larger than the supported MSI limit."
    }
    if (($metadataFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $metadataFile.Length -lt 1 -or
        $metadataFile.Length -gt 4MB) {
        throw "$Label validation metadata is a reparse point, empty, or larger than 4 MiB."
    }

    $metadata = Get-Content -LiteralPath $resolvedMetadataPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ($metadata.Schema -cne 'WireSockUI-Msi-Validation-v1' -or
        $metadata.ProductCode -cnotmatch '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$' -or
        $metadata.ProductVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or
        $metadata.Architecture -cne $ExpectedArchitecture -or
        $metadata.Flavor -cne $ExpectedFlavor -or
        $metadata.UpgradeCode -cne $upgradeCode) {
        throw "$Label validation metadata has an unexpected package identity."
    }

    $validationParameters = @{
        MsiPath = $resolvedMsiPath
        ValidationMetadataPath = $resolvedMetadataPath
        ExpectedArchitecture = $ExpectedArchitecture
        ExpectedVersion = [string]$metadata.ProductVersion
        ExpectedFlavor = $ExpectedFlavor
        ExpectedProductCode = [string]$metadata.ProductCode
    }
    & $validationScriptPath @validationParameters |
        ForEach-Object { Write-Host $_ }

    return [pscustomobject]@{
        Label = $Label
        MsiPath = $resolvedMsiPath
        MetadataPath = $resolvedMetadataPath
        Architecture = $ExpectedArchitecture
        Flavor = $ExpectedFlavor
        ProductVersion = [string]$metadata.ProductVersion
        ParsedVersion = [Version]([string]$metadata.ProductVersion)
        ProductCode = [string]$metadata.ProductCode
        Files = @($metadata.Files)
    }
}

$programFiles64 = Get-TrustedNativeProgramFilesPath
$programFilesX86 = Get-MsiTrustedKnownFolderPath `
    -FolderId ([Guid]'7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E') `
    -Description '32-bit Program Files'
if ([string]::Equals(
        $programFiles64,
        $programFilesX86,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Windows returned the same root for 32-bit and 64-bit Program Files.'
}

$x64InstallRoot = [IO.Path]::GetFullPath(
    (Join-Path $programFiles64 $applicationDirectoryName))
$x86InstallRoot = [IO.Path]::GetFullPath(
    (Join-Path $programFilesX86 $applicationDirectoryName))
$commonPrograms = Get-MsiTrustedKnownFolderPath `
    -FolderId (Get-MsiCommonProgramsFolderId) `
    -Description 'all-users Programs'
$commonDesktop = Get-MsiTrustedKnownFolderPath `
    -FolderId (Get-MsiCommonDesktopFolderId) `
    -Description 'all-users Desktop'
$shortcutPaths = @(
    [IO.Path]::GetFullPath((Join-Path $commonPrograms 'WireSock UI.lnk')),
    [IO.Path]::GetFullPath((Join-Path $commonDesktop 'WireSock UI.lnk'))
)
$windowsDirectory = Get-MsiTrustedKnownFolderPath `
    -FolderId ([Guid]'F38BF404-1D43-42F2-9305-67DE0B28FC23') `
    -Description 'Windows'
$systemDirectory = Assert-MsiTrustedDirectoryPath `
    -Path (Join-Path $windowsDirectory 'System32') `
    -Description 'Windows system directory'
$trustedMsiExecPath = Join-Path $systemDirectory 'msiexec.exe'
if (-not [IO.File]::Exists($trustedMsiExecPath)) {
    throw "Windows Installer client '$trustedMsiExecPath' does not exist."
}
$msiExecEntry = Get-Item -LiteralPath $trustedMsiExecPath -Force
if (($msiExecEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Windows Installer client '$trustedMsiExecPath' is a reparse point."
}
$allowedInstallRoots = New-Object 'System.Collections.Generic.HashSet[string]' (
    [StringComparer]::OrdinalIgnoreCase)
[void]$allowedInstallRoots.Add($x64InstallRoot)
[void]$allowedInstallRoots.Add($x86InstallRoot)

function Get-PackageInstallRoot {
    param([object]$Package)

    if ($Package.Architecture -eq 'x86') {
        return $x86InstallRoot
    }
    return $x64InstallRoot
}

function Assert-SafeInstallRoot {
    param([string]$Path)

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if (-not $allowedInstallRoots.Contains($resolvedPath)) {
        throw "Refusing an operation outside the exact MSI test roots: '$resolvedPath'."
    }
    return $resolvedPath
}

function Assert-NoReparseTree {
    param([string]$Root)

    if (-not [IO.Directory]::Exists($Root)) {
        return
    }
    $rootEntry = Get-Item -LiteralPath $Root -Force
    if (($rootEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Test installation root '$Root' is a reparse point."
    }
    foreach ($entry in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Installed entry '$($entry.FullName)' is a reparse point."
        }
    }
}

function Assert-ProtectedEntry {
    param(
        [string]$Path,
        [switch]$RequireExactPayloadAcl,
        [switch]$AllowDeleteOnly
    )

    $entry = Get-Item -LiteralPath $Path -Force
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Installed entry '$Path' is a reparse point."
    }

    $acl = Get-Acl -LiteralPath $Path
    if (-not (Test-MsiSecurityDescriptorHasNonNullDacl -Security $acl)) {
        throw "Installed entry '$Path' has an absent or unreadable DACL."
    }
    $ownerSid = $acl.GetOwner(
        [Security.Principal.SecurityIdentifier]).Value
    $privilegedOwnerSids = @(
        'S-1-5-18',
        'S-1-5-32-544',
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    )
    if (-not ($privilegedOwnerSids -contains $ownerSid)) {
        throw "Installed entry '$Path' has untrusted owner SID '$ownerSid'."
    }

    $accessRules = @(
        $acl.GetAccessRules(
            $true,
            $true,
            [Security.Principal.SecurityIdentifier])
    )
    foreach ($rule in $accessRules) {
        $ruleSid = $rule.IdentityReference.Value
        $rightsAreUnsafe = if ($AllowDeleteOnly) {
            Test-MsiReplacementCapableFileSystemRights `
                -Rights $rule.FileSystemRights
        }
        else {
            Test-MsiWriteCapableFileSystemRights `
                -Rights $rule.FileSystemRights
        }
        if ($rule.AccessControlType -eq
                [Security.AccessControl.AccessControlType]::Allow -and
            $rightsAreUnsafe -and
            -not ($privilegedOwnerSids -contains $ruleSid)) {
            throw "Installed entry '$Path' grants write-capable access to SID '$ruleSid'."
        }
    }

    if ($RequireExactPayloadAcl -and
        -not (Test-MsiExactPayloadAccessControl `
            -Security $acl `
            -Directory:$entry.PSIsContainer)) {
        $entryKind = if ($entry.PSIsContainer) { 'directory' } else { 'file' }
        throw "Installed payload $entryKind '$Path' does not have the exact protected ACL."
    }
}

function Assert-UnknownMarker {
    param(
        [string]$Path,
        [string]$ExpectedHash
    )

    if (-not [IO.File]::Exists($Path)) {
        throw "Unknown-file preservation marker '$Path' is missing."
    }
    $entry = Get-Item -LiteralPath $Path -Force
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne
            $ExpectedHash) {
        throw "Unknown-file preservation marker '$Path' was changed."
    }
}

function Assert-InstalledImage {
    param(
        [object]$Package,
        [string[]]$AllowedUnknownRelativePaths = @(),
        [switch]$RequireExactPayloadAcl
    )

    $root = Assert-SafeInstallRoot -Path (Get-PackageInstallRoot -Package $Package)
    if (-not [IO.Directory]::Exists($root)) {
        throw "$($Package.Label) did not create expected installation root '$root'."
    }
    Assert-NoReparseTree -Root $root
    # The baseline packages already harden their application root. Only current
    # packages contain per-object ACL authoring, so gate exact descendant checks.
    Assert-ProtectedEntry `
        -Path $root `
        -RequireExactPayloadAcl
    foreach ($directory in @(
            Get-ChildItem -LiteralPath $root -Recurse -Directory -Force)) {
        Assert-ProtectedEntry `
            -Path $directory.FullName `
            -RequireExactPayloadAcl:$RequireExactPayloadAcl
    }

    $expectedFiles = @{}
    foreach ($file in $Package.Files) {
        $relativePath = ([string]$file.Path).Replace('\', '/')
        if ($expectedFiles.ContainsKey($relativePath)) {
            throw "$($Package.Label) metadata duplicates '$relativePath'."
        }
        $expectedFiles[$relativePath] = $file
    }
    $allowedUnknown = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($relativePath in $AllowedUnknownRelativePaths) {
        [void]$allowedUnknown.Add($relativePath.Replace('\', '/'))
    }

    $actualFiles = @(
        Get-ChildItem -LiteralPath $root -Recurse -File -Force
    )
    if ($actualFiles.Count -ne $expectedFiles.Count + $allowedUnknown.Count) {
        throw "$($Package.Label) installed $($actualFiles.Count) files; expected $($expectedFiles.Count) MSI files and $($allowedUnknown.Count) preserved files."
    }
    foreach ($file in $actualFiles) {
        $relativePath = $file.FullName.Substring(
            $root.TrimEnd('\', '/').Length).TrimStart('\', '/').Replace('\', '/')
        if ($allowedUnknown.Contains($relativePath)) {
            continue
        }
        if (-not $expectedFiles.ContainsKey($relativePath)) {
            throw "$($Package.Label) installation contains unexpected file '$relativePath'."
        }
        $expectedFile = $expectedFiles[$relativePath]
        if ($file.Length -ne [Int64]$expectedFile.Size -or
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne
                [string]$expectedFile.Sha256) {
            throw "$($Package.Label) installed file '$relativePath' differs from validation metadata."
        }
        Assert-ProtectedEntry `
            -Path $file.FullName `
            -RequireExactPayloadAcl:$RequireExactPayloadAcl
    }
}

function Assert-ShortcutTarget {
    param([string]$ExpectedInstallRoot)

    foreach ($shortcutPath in $shortcutPaths) {
        if (-not [IO.File]::Exists($shortcutPath)) {
            throw "All-users shortcut '$shortcutPath' is missing."
        }
        # The validated parent denies untrusted creation, so inherited
        # delete-only access cannot be used to replace the shortcut.
        Assert-ProtectedEntry -Path $shortcutPath -AllowDeleteOnly
        $shell = $null
        $shortcut = $null
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $expectedTarget = [IO.Path]::GetFullPath(
                (Join-Path $ExpectedInstallRoot 'WireSockUI.exe'))
            $actualTarget = [IO.Path]::GetFullPath([string]$shortcut.TargetPath)
            $actualWorkingDirectory = [IO.Path]::GetFullPath(
                [string]$shortcut.WorkingDirectory)
            if (-not [string]::Equals(
                    $actualTarget,
                    $expectedTarget,
                    [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals(
                    $actualWorkingDirectory.TrimEnd('\'),
                    $ExpectedInstallRoot.TrimEnd('\'),
                    [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::IsNullOrEmpty([string]$shortcut.Arguments)) {
                throw "All-users shortcut '$shortcutPath' does not target '$expectedTarget' exactly."
            }
        }
        finally {
            if ($null -ne $shortcut) {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) |
                    Out-Null
            }
            if ($null -ne $shell) {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) |
                    Out-Null
            }
        }
    }
}

function Assert-PackageInstalled {
    param(
        [object]$Package,
        [string[]]$AllowedUnknownRelativePaths = @(),
        [switch]$RequireExactPayloadAcl
    )

    Assert-ProductInstalled -Package $Package
    Assert-RelatedProducts -ExpectedProductCodes @($Package.ProductCode)
    Assert-InstalledImage `
        -Package $Package `
        -AllowedUnknownRelativePaths $AllowedUnknownRelativePaths `
        -RequireExactPayloadAcl:$RequireExactPayloadAcl
    Assert-ShortcutTarget -ExpectedInstallRoot (
        Get-PackageInstallRoot -Package $Package)
}

function Get-InstalledFileSnapshot {
    param([string]$Root)

    $resolvedRoot = Assert-SafeInstallRoot -Path $Root
    if (-not [IO.Directory]::Exists($resolvedRoot)) {
        return '[]'
    }
    $snapshot = @(
        Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Force |
            ForEach-Object {
                [ordered]@{
                    Path = $_.FullName.Substring(
                        $resolvedRoot.TrimEnd('\', '/').Length
                    ).TrimStart('\', '/').Replace('\', '/')
                    Size = [Int64]$_.Length
                    Sha256 = (
                        Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
                    ).Hash.ToLowerInvariant()
                }
            } |
            Sort-Object -Property Path
    )
    return ($snapshot | ConvertTo-Json -Compress -Depth 3)
}

function Wait-WindowsInstallerExecutionIdle {
    param([int]$TimeoutMilliseconds = 120000)

    $mutex = $null
    $acquired = $false
    try {
        try {
            $mutex = [Threading.Mutex]::OpenExisting('Global\_MSIExecute')
        }
        catch [Threading.WaitHandleCannotBeOpenedException] {
            return $true
        }

        try {
            $acquired = $mutex.WaitOne($TimeoutMilliseconds)
        }
        catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        return $acquired
    }
    catch {
        return $false
    }
    finally {
        if ($acquired -and $null -ne $mutex) {
            try { $mutex.ReleaseMutex() } catch {}
        }
        if ($null -ne $mutex) {
            $mutex.Dispose()
        }
    }
}

function Invoke-MsiExec {
    param(
        [string]$Operation,
        [string[]]$Arguments
    )

    $script:operationIndex++
    $safeOperation = $Operation -replace '[^A-Za-z0-9_.-]', '-'
    $logPath = Join-Path $testRoot (
        '{0:D2}-{1}.log' -f $script:operationIndex, $safeOperation)
    $completeArguments = @($Arguments) + @('/l*vx!', $logPath)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $trustedMsiExecPath
    $startInfo.Arguments = (
        $completeArguments |
            ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value $_ }
    ) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) {
        throw "Unable to start Windows Installer for '$Operation'."
    }
    try {
        if (-not $process.WaitForExit($operationTimeoutMilliseconds)) {
            try {
                $process.Kill($true)
            }
            catch {
                try { $process.Kill() } catch {}
            }
            $clientExited = $process.WaitForExit(30000)
            $installerIdle = Wait-WindowsInstallerExecutionIdle
            if (-not $clientExited -or -not $installerIdle) {
                $script:installerStateSafeForCleanup = $false
            }
            $diagnostic = Get-BoundedMsiLogDiagnostic -Path $logPath
            throw (
                "Windows Installer operation '$Operation' timed out; cleanup " +
                'will be skipped unless the client exited and the execute ' +
                "mutex became idle. Log: $logPath$([Environment]::NewLine)" +
                $diagnostic)
        }
        $exitCode = $process.ExitCode
        if ($exitCode -in @(1641, 3010)) {
            $script:installerStateSafeForCleanup = $false
            $diagnostic = Get-BoundedMsiLogDiagnostic -Path $logPath
            throw (
                "Windows Installer operation '$Operation' initiated or " +
                "requested a reboot (exit code $exitCode). Refusing further " +
                "installer operations or filesystem cleanup. Log: $logPath" +
                "$([Environment]::NewLine)$diagnostic")
        }
        return [pscustomobject]@{
            ExitCode = $exitCode
            LogPath = $logPath
        }
    }
    finally {
        $process.Dispose()
    }
}

function Install-Package {
    param(
        [object]$Package,
        [string]$Operation
    )

    $result = Invoke-MsiExec -Operation $Operation -Arguments @(
        '/i',
        $Package.MsiPath,
        '/qn',
        '/norestart',
        'REBOOT=ReallySuppress'
    )
    if ($result.ExitCode -ne 0) {
        $diagnostic = Get-BoundedMsiLogDiagnostic -Path $result.LogPath
        throw (
            "$Operation failed with exit code $($result.ExitCode). Log: " +
            "$($result.LogPath)$([Environment]::NewLine)$diagnostic")
    }
}

function Uninstall-Package {
    param(
        [object]$Package,
        [string]$Operation
    )

    $result = Invoke-MsiExec -Operation $Operation -Arguments @(
        '/x',
        $Package.ProductCode,
        '/qn',
        '/norestart',
        'REBOOT=ReallySuppress'
    )
    if ($result.ExitCode -notin @(0, 1605)) {
        $diagnostic = Get-BoundedMsiLogDiagnostic -Path $result.LogPath
        throw (
            "$Operation failed with exit code $($result.ExitCode). Log: " +
            "$($result.LogPath)$([Environment]::NewLine)$diagnostic")
    }
}

function Invoke-ExpectedInstallFailure {
    param(
        [object]$Package,
        [string]$Operation,
        [int[]]$ExpectedExitCodes,
        [string[]]$RequiredLogPatterns
    )

    $result = Invoke-MsiExec -Operation $Operation -Arguments @(
        '/i',
        $Package.MsiPath,
        '/qn',
        '/norestart',
        'REBOOT=ReallySuppress'
    )
    if ($result.ExitCode -notin $ExpectedExitCodes) {
        $diagnostic = Get-BoundedMsiLogDiagnostic -Path $result.LogPath
        throw (
            "$Operation returned exit code $($result.ExitCode); expected " +
            "$($ExpectedExitCodes -join ', '). Log: $($result.LogPath)" +
            "$([Environment]::NewLine)$diagnostic")
    }
    $logEntry = Get-Item -LiteralPath $result.LogPath -Force
    if ($logEntry.Length -gt 32MB) {
        throw "$Operation produced an unexpectedly large MSI log. Log: $($result.LogPath)"
    }
    $logText = Get-Content -LiteralPath $result.LogPath -Raw
    foreach ($pattern in $RequiredLogPatterns) {
        if ($logText -notmatch [regex]::Escape($pattern)) {
            $diagnostic = Get-BoundedMsiLogDiagnostic -Path $result.LogPath
            throw (
                "$Operation log does not contain required evidence '$pattern'. " +
                "Log: $($result.LogPath)$([Environment]::NewLine)$diagnostic")
        }
    }
    Write-Host "$Operation failed as expected with exit code $($result.ExitCode)."
}

function Assert-MsiOwnedFilesAbsent {
    param(
        [object]$Package,
        [string]$Root
    )

    foreach ($file in $Package.Files) {
        $path = Join-Path $Root ([string]$file.Path).Replace(
            '/',
            [IO.Path]::DirectorySeparatorChar)
        if (Test-FileSystemEntryExists -Path $path) {
            throw "Obsolete or uninstalled MSI-owned file '$path' remains."
        }
    }
}

function New-RollbackConflict {
    param(
        [string]$Root,
        [string]$RelativeFilePath
    )

    $resolvedRoot = Assert-SafeInstallRoot -Path $Root
    $segments = $RelativeFilePath.Replace('\', '/').Split('/')
    if ($segments.Count -lt 1) {
        throw 'A rollback-conflict path is required.'
    }

    $createdDirectories = New-Object 'System.Collections.Generic.List[string]'
    $current = $resolvedRoot
    foreach ($segment in $segments) {
        $current = [IO.Path]::GetFullPath((Join-Path $current $segment))
        $normalizedRoot = $resolvedRoot.TrimEnd('\') + '\'
        if (-not $current.StartsWith(
                $normalizedRoot,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Rollback-conflict path '$RelativeFilePath' escapes '$resolvedRoot'."
        }
        if ([IO.File]::Exists($current)) {
            throw "Rollback-conflict path '$current' is already a file."
        }
        if (-not [IO.Directory]::Exists($current)) {
            [IO.Directory]::CreateDirectory($current) | Out-Null
            $createdDirectories.Add($current)
        }
    }

    if (-not [IO.Directory]::Exists($current)) {
        throw "Unable to create rollback-conflict directory '$current'."
    }
    return [pscustomobject]@{
        LeafPath = $current
        CreatedDirectories = $createdDirectories.ToArray()
    }
}

function Remove-RollbackConflict {
    param([object]$Conflict)

    if ($null -eq $Conflict) {
        return
    }
    foreach ($path in @(
            $Conflict.CreatedDirectories |
                Sort-Object -Property Length -Descending)) {
        if (-not [IO.Directory]::Exists($path)) {
            continue
        }
        $entry = Get-Item -LiteralPath $path -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove reparse-point rollback path '$path'."
        }
        if (@(Get-ChildItem -LiteralPath $path -Force).Count -ne 0) {
            throw "Rollback did not leave conflict directory '$path' empty."
        }
        [IO.Directory]::Delete($path, $false)
    }
}

function Remove-EmptyTestInstallRoot {
    param([string]$Root)

    $resolvedRoot = Assert-SafeInstallRoot -Path $Root
    if (-not [IO.Directory]::Exists($resolvedRoot)) {
        return
    }
    Assert-NoReparseTree -Root $resolvedRoot
    $remainingFiles = @(
        Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Force
    )
    if ($remainingFiles.Count -ne 0) {
        throw "Refusing to remove test root '$resolvedRoot' because files remain: $($remainingFiles[0].FullName)"
    }
    $directories = @(
        Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Directory -Force |
            Sort-Object -Property @{
                Expression = { $_.FullName.Length }
                Descending = $true
            }
    )
    foreach ($directory in $directories) {
        if (@(Get-ChildItem -LiteralPath $directory.FullName -Force).Count -eq 0) {
            [IO.Directory]::Delete($directory.FullName, $false)
        }
    }
    if (@(Get-ChildItem -LiteralPath $resolvedRoot -Force).Count -eq 0) {
        [IO.Directory]::Delete($resolvedRoot, $false)
    }
}

$baselineX64Uwp = Read-PackageSpec `
    -MsiPath $BaselineX64UwpMsiPath `
    -ValidationMetadataPath $BaselineX64UwpValidationMetadataPath `
    -ExpectedArchitecture x64 `
    -ExpectedFlavor uwp `
    -Label 'baseline x64 UWP'
$currentX64NoUwp = Read-PackageSpec `
    -MsiPath $CurrentX64NoUwpMsiPath `
    -ValidationMetadataPath $CurrentX64NoUwpValidationMetadataPath `
    -ExpectedArchitecture x64 `
    -ExpectedFlavor no-uwp `
    -Label 'current x64 no-UWP'
$currentX64Uwp = Read-PackageSpec `
    -MsiPath $CurrentX64UwpMsiPath `
    -ValidationMetadataPath $CurrentX64UwpValidationMetadataPath `
    -ExpectedArchitecture x64 `
    -ExpectedFlavor uwp `
    -Label 'current x64 UWP'
$baselineX86NoUwp = Read-PackageSpec `
    -MsiPath $BaselineX86NoUwpMsiPath `
    -ValidationMetadataPath $BaselineX86NoUwpValidationMetadataPath `
    -ExpectedArchitecture x86 `
    -ExpectedFlavor no-uwp `
    -Label 'baseline x86 no-UWP'

$packages = @(
    $baselineX64Uwp,
    $currentX64NoUwp,
    $currentX64Uwp,
    $baselineX86NoUwp
)
if (@($packages.ProductCode | Sort-Object -Unique).Count -ne $packages.Count) {
    throw 'Transition packages must have four distinct ProductCodes.'
}
if ($baselineX64Uwp.ProductVersion -cne $baselineX86NoUwp.ProductVersion) {
    throw 'Baseline x64 UWP and x86 no-UWP packages must use the same version.'
}
if ($currentX64NoUwp.ProductVersion -cne $currentX64Uwp.ProductVersion) {
    throw 'Current x64 UWP and no-UWP packages must use the same version.'
}
if ($currentX64NoUwp.ParsedVersion -le $baselineX64Uwp.ParsedVersion) {
    throw 'Current package version must be newer than baseline package version.'
}

$currentNoUwpPaths = New-Object 'System.Collections.Generic.HashSet[string]' (
    [StringComparer]::OrdinalIgnoreCase)
foreach ($file in $currentX64NoUwp.Files) {
    [void]$currentNoUwpPaths.Add([string]$file.Path)
}
$obsoleteUwpPaths = @(
    $baselineX64Uwp.Files |
        ForEach-Object { [string]$_.Path } |
        Where-Object { -not $currentNoUwpPaths.Contains($_) } |
        Sort-Object
)
$currentUwpOnlyPaths = @(
    $currentX64Uwp.Files |
        ForEach-Object { [string]$_.Path } |
        Where-Object { -not $currentNoUwpPaths.Contains($_) } |
        Sort-Object -Property @{ Expression = { ($_ -split '/').Count } }, Length
)
if ($obsoleteUwpPaths.Count -eq 0) {
    throw 'Baseline UWP payload must contain at least one file absent from current no-UWP payload.'
}
if ($currentUwpOnlyPaths.Count -eq 0) {
    throw 'Current UWP payload must contain at least one file absent from current no-UWP payload.'
}

foreach ($root in @($x64InstallRoot, $x86InstallRoot)) {
    if (Test-FileSystemEntryExists -Path $root) {
        throw "The ephemeral machine is not clean: '$root' already exists."
    }
}
if (@($shortcutPaths | Where-Object {
            Test-FileSystemEntryExists -Path $_
        }).Count -ne 0) {
    throw 'The ephemeral machine is not clean: a WireSock UI shortcut already exists.'
}
Assert-RelatedProducts -ExpectedProductCodes @()
foreach ($package in $packages) {
    Assert-ProductAbsent -Package $package
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'WireSockUI.Msi.Transitions.' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$operationIndex = 0
$unknownMarkerPath = $null
$unknownMarkerHash = $null
$unknownMarkerRelativePath = $null
$rollbackConflict = $null
$installerStateSafeForCleanup = $true
$primaryError = $null
$cleanupErrors = New-Object 'System.Collections.Generic.List[string]'

try {
    # Version upgrade and obsolete-file removal: baseline UWP N -> no-UWP N+1.
    Install-Package `
        -Package $baselineX64Uwp `
        -Operation 'install-baseline-x64-uwp'
    Assert-PackageInstalled -Package $baselineX64Uwp

    $unknownMarkerRelativePath =
        'WireSockUI-transition-unknown-' + [Guid]::NewGuid().ToString('N') + '.txt'
    $unknownMarkerPath = Join-Path $x64InstallRoot $unknownMarkerRelativePath
    [IO.File]::WriteAllText(
        $unknownMarkerPath,
        'WireSock UI MSI transition unknown-file preservation marker',
        [Text.UTF8Encoding]::new($false))
    $unknownMarkerHash = (
        Get-FileHash -LiteralPath $unknownMarkerPath -Algorithm SHA256
    ).Hash

    Install-Package `
        -Package $currentX64NoUwp `
        -Operation 'upgrade-x64-version-and-remove-uwp'
    Assert-ProductAbsent -Package $baselineX64Uwp
    Assert-PackageInstalled `
        -Package $currentX64NoUwp `
        -AllowedUnknownRelativePaths @($unknownMarkerRelativePath) `
        -RequireExactPayloadAcl
    Assert-UnknownMarker `
        -Path $unknownMarkerPath `
        -ExpectedHash $unknownMarkerHash
    foreach ($relativePath in $obsoleteUwpPaths) {
        $obsoletePath = Join-Path $x64InstallRoot $relativePath.Replace(
            '/',
            [IO.Path]::DirectorySeparatorChar)
        if (Test-FileSystemEntryExists -Path $obsoletePath) {
            throw "Version upgrade retained obsolete MSI-owned file '$obsoletePath'."
        }
    }

    # A rejected downgrade must not change the installed product or any bytes.
    $preDowngradeSnapshot = Get-InstalledFileSnapshot -Root $x64InstallRoot
    Invoke-ExpectedInstallFailure `
        -Package $baselineX64Uwp `
        -Operation 'reject-x64-downgrade' `
        -ExpectedExitCodes @(1603) `
        -RequiredLogPatterns @('WIX_DOWNGRADE_DETECTED')
    Assert-ProductAbsent -Package $baselineX64Uwp
    Assert-PackageInstalled `
        -Package $currentX64NoUwp `
        -AllowedUnknownRelativePaths @($unknownMarkerRelativePath) `
        -RequireExactPayloadAcl
    $postDowngradeSnapshot = Get-InstalledFileSnapshot -Root $x64InstallRoot
    if ($postDowngradeSnapshot -cne $preDowngradeSnapshot) {
        throw 'Rejected downgrade changed the installed file image.'
    }

    # Force a failure during the transactional same-version flavor upgrade.
    # The UWP package must install a file where this empty, unknown directory
    # exists. RemoveExistingProducts has already run when InstallFiles fails, so
    # successful recovery proves Windows Installer rolled the old product back.
    $preRollbackSnapshot = Get-InstalledFileSnapshot -Root $x64InstallRoot
    $rollbackConflict = New-RollbackConflict `
        -Root $x64InstallRoot `
        -RelativeFilePath $currentUwpOnlyPaths[0]
    Invoke-ExpectedInstallFailure `
        -Package $currentX64Uwp `
        -Operation 'force-same-version-flavor-rollback' `
        -ExpectedExitCodes @(1603) `
        -RequiredLogPatterns @('RemoveExistingProducts', 'Rollback')
    Assert-ProductAbsent -Package $currentX64Uwp
    Assert-ProductInstalled -Package $currentX64NoUwp
    Assert-RelatedProducts `
        -ExpectedProductCodes @($currentX64NoUwp.ProductCode)
    Remove-RollbackConflict -Conflict $rollbackConflict
    $rollbackConflict = $null
    Assert-PackageInstalled `
        -Package $currentX64NoUwp `
        -AllowedUnknownRelativePaths @($unknownMarkerRelativePath) `
        -RequireExactPayloadAcl
    $postRollbackSnapshot = Get-InstalledFileSnapshot -Root $x64InstallRoot
    if ($postRollbackSnapshot -cne $preRollbackSnapshot) {
        throw 'Failed same-version flavor upgrade did not restore the prior file image.'
    }
    Assert-UnknownMarker `
        -Path $unknownMarkerPath `
        -ExpectedHash $unknownMarkerHash

    # Retry without the injected conflict and require the same-version flavor
    # transition to replace the old ProductCode rather than install side by side.
    Install-Package `
        -Package $currentX64Uwp `
        -Operation 'upgrade-same-version-no-uwp-to-uwp'
    Assert-ProductAbsent -Package $currentX64NoUwp
    Assert-PackageInstalled `
        -Package $currentX64Uwp `
        -AllowedUnknownRelativePaths @($unknownMarkerRelativePath) `
        -RequireExactPayloadAcl
    Assert-UnknownMarker `
        -Path $unknownMarkerPath `
        -ExpectedHash $unknownMarkerHash

    # Exercise the reverse same-version flavor transition too. UWP-only MSI
    # files must be removed while the unknown file remains untouched.
    Install-Package `
        -Package $currentX64NoUwp `
        -Operation 'upgrade-same-version-uwp-to-no-uwp'
    Assert-ProductAbsent -Package $currentX64Uwp
    Assert-PackageInstalled `
        -Package $currentX64NoUwp `
        -AllowedUnknownRelativePaths @($unknownMarkerRelativePath) `
        -RequireExactPayloadAcl
    Assert-UnknownMarker `
        -Path $unknownMarkerPath `
        -ExpectedHash $unknownMarkerHash
    foreach ($relativePath in $currentUwpOnlyPaths) {
        $obsoletePath = Join-Path $x64InstallRoot $relativePath.Replace(
            '/',
            [IO.Path]::DirectorySeparatorChar)
        if (Test-FileSystemEntryExists -Path $obsoletePath) {
            throw "Reverse flavor transition retained obsolete MSI-owned file '$obsoletePath'."
        }
    }

    # Unknown files survive uninstall; MSI-owned files and shortcut do not.
    Uninstall-Package `
        -Package $currentX64NoUwp `
        -Operation 'uninstall-current-x64-no-uwp-after-flavor-transitions'
    Assert-ProductAbsent -Package $currentX64NoUwp
    Assert-RelatedProducts -ExpectedProductCodes @()
    Assert-MsiOwnedFilesAbsent -Package $currentX64NoUwp -Root $x64InstallRoot
    Assert-UnknownMarker `
        -Path $unknownMarkerPath `
        -ExpectedHash $unknownMarkerHash
    if (@($shortcutPaths | Where-Object {
                Test-FileSystemEntryExists -Path $_
            }).Count -ne 0) {
        throw 'An all-users shortcut remained after flavor-transition uninstall.'
    }
    $remainingFiles = @(
        Get-ChildItem -LiteralPath $x64InstallRoot -Recurse -File -Force
    )
    if ($remainingFiles.Count -ne 1 -or
        -not [string]::Equals(
            $remainingFiles[0].FullName,
            $unknownMarkerPath,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Uninstall retained files other than the explicit unknown-file marker.'
    }
    [IO.File]::Delete($unknownMarkerPath)
    $unknownMarkerPath = $null
    Remove-EmptyTestInstallRoot -Root $x64InstallRoot
    if ([IO.Directory]::Exists($x64InstallRoot)) {
        throw 'x64 installation root remained after removing the preserved marker.'
    }

    # Cross-architecture major upgrade: x86 N -> x64 N+1.
    Install-Package `
        -Package $baselineX86NoUwp `
        -Operation 'install-baseline-x86-no-uwp'
    Assert-PackageInstalled -Package $baselineX86NoUwp
    Install-Package `
        -Package $currentX64NoUwp `
        -Operation 'upgrade-x86-to-x64'
    Assert-ProductAbsent -Package $baselineX86NoUwp
    Assert-PackageInstalled `
        -Package $currentX64NoUwp `
        -RequireExactPayloadAcl
    if (Test-FileSystemEntryExists -Path $x86InstallRoot) {
        throw "x86 installation root '$x86InstallRoot' remained after x64 transition."
    }

    Uninstall-Package `
        -Package $currentX64NoUwp `
        -Operation 'uninstall-current-x64-no-uwp'
    Assert-ProductAbsent -Package $currentX64NoUwp
    Assert-RelatedProducts -ExpectedProductCodes @()
    if ((Test-FileSystemEntryExists -Path $x64InstallRoot) -or
        (Test-FileSystemEntryExists -Path $x86InstallRoot) -or
        @($shortcutPaths | Where-Object {
                Test-FileSystemEntryExists -Path $_
            }).Count -ne 0) {
        throw 'Cross-architecture scenario did not clean all MSI-owned state.'
    }
}
catch {
    $primaryError = $_
}
finally {
    foreach ($package in @(
            $currentX64Uwp,
            $currentX64NoUwp,
            $baselineX64Uwp,
            $baselineX86NoUwp)) {
        if (-not $installerStateSafeForCleanup) {
            break
        }
        try {
            if ((Get-ProductState -ProductCode $package.ProductCode) -ne -1) {
                Uninstall-Package `
                    -Package $package `
                    -Operation "cleanup-$($package.Architecture)-$($package.Flavor)-$($package.ProductVersion)"
            }
        }
        catch {
            $cleanupErrors.Add($_.Exception.Message)
        }
    }

    if (-not $installerStateSafeForCleanup) {
        $cleanupErrors.Add(
            'Remaining cleanup was skipped because Windows Installer state is not known to be quiescent.')
    }
    else {
        try {
            if ($null -ne $rollbackConflict) {
                Remove-RollbackConflict -Conflict $rollbackConflict
            }
        }
        catch {
            $cleanupErrors.Add($_.Exception.Message)
        }

        try {
            if (-not [string]::IsNullOrEmpty($unknownMarkerPath) -and
                [IO.File]::Exists($unknownMarkerPath)) {
                Assert-UnknownMarker `
                    -Path $unknownMarkerPath `
                    -ExpectedHash $unknownMarkerHash
                [IO.File]::Delete($unknownMarkerPath)
            }
        }
        catch {
            $cleanupErrors.Add($_.Exception.Message)
        }

        foreach ($root in @($x64InstallRoot, $x86InstallRoot)) {
            try {
                Remove-EmptyTestInstallRoot -Root $root
            }
            catch {
                $cleanupErrors.Add($_.Exception.Message)
            }
        }
        try {
            Assert-RelatedProducts -ExpectedProductCodes @()
            foreach ($package in $packages) {
                Assert-ProductAbsent -Package $package
            }
            if (@($shortcutPaths | Where-Object {
                        Test-FileSystemEntryExists -Path $_
                    }).Count -ne 0) {
                throw 'An all-users WireSock UI shortcut remained after cleanup.'
            }
        }
        catch {
            $cleanupErrors.Add($_.Exception.Message)
        }
    }

    if ($null -eq $primaryError -and $cleanupErrors.Count -eq 0) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $normalizedTempRoot = [IO.Path]::GetFullPath(
            [IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolvedTestRoot.StartsWith(
                $normalizedTempRoot,
                [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolvedTestRoot).StartsWith(
                'WireSockUI.Msi.Transitions.',
                [StringComparison]::Ordinal)) {
            $cleanupErrors.Add(
                "Refusing to remove unexpected MSI test-log path '$resolvedTestRoot'.")
        }
        elseif ([IO.Directory]::Exists($resolvedTestRoot)) {
            $testRootEntry = Get-Item -LiteralPath $resolvedTestRoot -Force
            if (($testRootEntry.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $cleanupErrors.Add(
                    "Refusing to remove reparse-point MSI test-log path '$resolvedTestRoot'.")
            }
            else {
                [IO.Directory]::Delete($resolvedTestRoot, $true)
            }
        }
    }
}

if ($null -ne $primaryError) {
    $cleanupSuffix = if ($cleanupErrors.Count -gt 0) {
        "$([Environment]::NewLine)Cleanup errors: $($cleanupErrors -join ' | ')"
    }
    else {
        ''
    }
    throw [InvalidOperationException]::new(
        "$($primaryError.Exception.Message)$cleanupSuffix Logs: $testRoot",
        $primaryError.Exception)
}
if ($cleanupErrors.Count -gt 0) {
    throw "MSI transition scenarios passed, but cleanup failed: $($cleanupErrors -join ' | '). Logs: $testRoot"
}

Write-Output 'Validated x64 version/flavor upgrade, rollback, downgrade rejection, obsolete/unknown-file behavior, and x86-to-x64 transition.'
