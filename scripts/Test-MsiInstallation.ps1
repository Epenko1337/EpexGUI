[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [Parameter(Mandatory = $true)]
    [string]$ValidationMetadataPath,

    [Parameter(Mandatory = $true)]
    [switch]$EphemeralMachine
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'MsiTest.AccessControl.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'MsiTest.Diagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'MsiTest.KnownFolders.psm1') -Force
$maximumMsiBytes = 2GB - 1
$maximumValidationMetadataBytes = 4MB

if (-not $EphemeralMachine) {
    throw 'This destructive installation test requires the explicit -EphemeralMachine guard.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The MSI installation test requires Windows.'
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
        throw 'The MSI installation test must run from an elevated administrator shell.'
    }
    $currentUserSid =
        [Security.Principal.SecurityIdentifier]::new(
            $currentIdentity.User.Value)
}
finally {
    $currentIdentity.Dispose()
}

$resolvedMsiPath = [IO.Path]::GetFullPath($MsiPath)
$resolvedMetadataPath = [IO.Path]::GetFullPath($ValidationMetadataPath)
if (-not [IO.File]::Exists($resolvedMsiPath) -or
    -not [IO.File]::Exists($resolvedMetadataPath)) {
    throw 'The MSI and its validation metadata sidecar must both exist.'
}
$msiFile = Get-Item -LiteralPath $resolvedMsiPath -Force
$metadataFile = Get-Item -LiteralPath $resolvedMetadataPath -Force
if (($msiFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    ($metadataFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The MSI and validation metadata must not be reparse points.'
}
if ($msiFile.Length -le 0 -or $msiFile.Length -gt $maximumMsiBytes) {
    throw "MSI has invalid length $($msiFile.Length)."
}
if ($metadataFile.Length -le 0 -or
    $metadataFile.Length -gt $maximumValidationMetadataBytes) {
    throw "Validation metadata has invalid length $($metadataFile.Length)."
}

$metadata = Get-Content -LiteralPath $resolvedMetadataPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($metadata.Schema -cne 'WireSockUI-Msi-Validation-v1' -or
    $metadata.ProductCode -cnotmatch '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$' -or
    $metadata.UpgradeCode -cne '{5C1DDAE5-6681-41BF-B153-AB2952AA6DF1}' -or
    $metadata.Architecture -cnotmatch '^(x86|x64|arm64)$' -or
    $metadata.Flavor -cnotmatch '^(uwp|no-uwp)$') {
    throw 'The validation metadata has an invalid product identity.'
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

function Get-MsiCompanionRelativePaths {
    param([string]$Path)

    function Invoke-InstallerMethod {
        param(
            [object]$Instance,
            [string]$Name,
            [object[]]$Arguments
        )

        return $Instance.GetType().InvokeMember(
            $Name,
            [Reflection.BindingFlags]::InvokeMethod,
            $null,
            $Instance,
            $Arguments)
    }

    function Get-Rows {
        param(
            [object]$Database,
            [string]$Sql,
            [int]$FieldCount
        )

        $view = $null
        $result = [Collections.Generic.List[object]]::new()
        try {
            $view = Invoke-InstallerMethod $Database OpenView @($Sql)
            Invoke-InstallerMethod $view Execute @() | Out-Null
            while ($true) {
                $record = Invoke-InstallerMethod $view Fetch @()
                if ($null -eq $record) {
                    break
                }
                try {
                    $fields = [string[]]::new($FieldCount)
                    for ($index = 0; $index -lt $FieldCount; $index++) {
                        $fields[$index] = [string]$record.StringData($index + 1)
                    }
                    $result.Add($fields)
                }
                finally {
                    [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                        $record) | Out-Null
                }
            }
        }
        finally {
            if ($null -ne $view) {
                try {
                    Invoke-InstallerMethod $view Close @() | Out-Null
                }
                finally {
                    [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                        $view) | Out-Null
                }
            }
        }
        return $result.ToArray()
    }

    function Get-LongMsiName {
        param(
            [string]$Value,
            [switch]$DirectoryName
        )

        $targetName = if ($DirectoryName) {
            ($Value -split ':', 2)[0]
        }
        else {
            $Value
        }
        $parts = $targetName -split '\|', 2
        return $parts[$parts.Count - 1]
    }

    $installer = $null
    $database = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = Invoke-InstallerMethod `
            $installer `
            OpenDatabase `
            @([string]$Path, [int]0)
        $directoryRows = @(
            Get-Rows `
                -Database $database `
                -Sql 'SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`' `
                -FieldCount 3)
        $componentRows = @(
            Get-Rows `
                -Database $database `
                -Sql 'SELECT `Component`, `Directory_` FROM `Component`' `
                -FieldCount 2)
        $fileRows = @(
            Get-Rows `
                -Database $database `
                -Sql 'SELECT `File`, `Component_`, `FileName`, `Version` FROM `File`' `
                -FieldCount 4)
    }
    finally {
        if ($null -ne $database) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $database) | Out-Null
        }
        if ($null -ne $installer) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $installer) | Out-Null
        }
    }

    $directories = @{}
    foreach ($row in $directoryRows) {
        $directories[[string]$row[0]] = [pscustomobject]@{
            Parent = [string]$row[1]
            Name = Get-LongMsiName `
                -Value ([string]$row[2]) `
                -DirectoryName
        }
    }
    $componentDirectories = @{}
    foreach ($row in $componentRows) {
        $componentDirectories[[string]$row[0]] = [string]$row[1]
    }
    $fileIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    foreach ($row in $fileRows) {
        [void]$fileIds.Add([string]$row[0])
    }

    $relativePaths = [Collections.Generic.List[string]]::new()
    foreach ($row in $fileRows) {
        $parentFileId = [string]$row[3]
        if (-not $fileIds.Contains($parentFileId)) {
            continue
        }

        $componentId = [string]$row[1]
        if (-not $componentDirectories.ContainsKey($componentId)) {
            throw "Companion file references unknown MSI component '$componentId'."
        }
        $segments = [Collections.Generic.List[string]]::new()
        $directoryId = [string]$componentDirectories[$componentId]
        $visited = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal)
        while ($directoryId -cne 'WireSockInstallFolder') {
            if (-not $visited.Add($directoryId) -or
                -not $directories.ContainsKey($directoryId)) {
                throw "Companion file has an invalid MSI directory chain at '$directoryId'."
            }
            $directory = $directories[$directoryId]
            if (-not [string]::IsNullOrEmpty($directory.Name) -and
                $directory.Name -cne '.') {
                $segments.Insert(0, [string]$directory.Name)
            }
            $directoryId = [string]$directory.Parent
        }
        $segments.Add((Get-LongMsiName -Value ([string]$row[2])))
        $relativePaths.Add([string]::Join('/', $segments))
    }

    if ($relativePaths.Count -eq 0) {
        throw 'The MSI does not contain any ordinary-repair companion files.'
    }
    return @($relativePaths | Sort-Object -Unique)
}

$architecture = [string]$metadata.Architecture
if ($architecture -ne 'x86' -and -not [Environment]::Is64BitOperatingSystem) {
    throw "A $architecture MSI cannot be installed on 32-bit Windows."
}
$programFilesRoot = if ($architecture -eq 'x86') {
    Get-MsiTrustedKnownFolderPath `
        -FolderId ([Guid]'7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E') `
        -Description '32-bit Program Files'
}
else {
    Get-TrustedNativeProgramFilesPath
}
if ($architecture -eq 'arm64') {
    $nativeArchitectures = @(
        [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE'),
        [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432')
    )
    if (-not ($nativeArchitectures -icontains 'ARM64')) {
        throw 'An ARM64 installation test requires an ARM64 Windows machine.'
    }
}

$installRoot = Join-Path $programFilesRoot 'WireSock Foundation WireSock UI'
$legacyInstallRoot = Join-Path $programFilesRoot 'WireSock UI'
$commonPrograms = Get-MsiTrustedKnownFolderPath `
    -FolderId (Get-MsiCommonProgramsFolderId) `
    -Description 'all-users Programs'
$commonDesktop = Get-MsiTrustedKnownFolderPath `
    -FolderId (Get-MsiCommonDesktopFolderId) `
    -Description 'all-users Desktop'
$shortcutPaths = @(
    (Join-Path $commonPrograms 'WireSock UI.lnk'),
    (Join-Path $commonDesktop 'WireSock UI.lnk')
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

if ((Test-FileSystemEntryExists -Path $installRoot) -or
    (Test-FileSystemEntryExists -Path $legacyInstallRoot) -or
    @($shortcutPaths | Where-Object {
            Test-FileSystemEntryExists -Path $_
        }).Count -ne 0) {
    throw 'The ephemeral machine is not clean: an installer destination, legacy path, or WireSock UI shortcut already exists.'
}

if ($null -eq ('WireSockUI.InstallerTest.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WireSockUI.InstallerTest
{
    public static class NativeMethods
    {
        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        public static extern int MsiQueryProductState(string productCode);

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        public static extern int MsiEnumRelatedProducts(
            string upgradeCode,
            int reserved,
            int productIndex,
            StringBuilder productCode);
    }
}
'@
}

function Get-ProductState {
    param([string]$ProductCode)

    return [WireSockUI.InstallerTest.NativeMethods]::MsiQueryProductState($ProductCode)
}

function Get-RelatedProductCodes {
    param([string]$UpgradeCode)

    $relatedProducts = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt 1024; $index++) {
        $productCode = New-Object Text.StringBuilder 39
        $result = [WireSockUI.InstallerTest.NativeMethods]::MsiEnumRelatedProducts(
            $UpgradeCode,
            0,
            $index,
            $productCode)
        if ($result -eq 259) {
            return $relatedProducts.ToArray()
        }
        if ($result -ne 0) {
            throw "MsiEnumRelatedProducts failed with Windows Installer error $result."
        }
        $value = $productCode.ToString()
        if ($value -cnotmatch '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$') {
            throw "Windows Installer returned invalid related ProductCode '$value'."
        }
        $relatedProducts.Add($value)
    }

    throw 'More than 1,024 related WireSock UI products are registered.'
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
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string[]]$Arguments
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
        throw 'Unable to start Windows Installer.'
    }
    try {
        if (-not $process.WaitForExit(300000)) {
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
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            LogPath = $logPath
        }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-MsiOperationSucceeded {
    param(
        [Parameter(Mandatory = $true)][object]$Result,
        [string]$Operation
    )

    if ($Result.ExitCode -in @(1641, 3010)) {
        $script:installerStateSafeForCleanup = $false
        $diagnostic = Get-BoundedMsiLogDiagnostic -Path $Result.LogPath
        throw (
            "$Operation initiated or requested a reboot (exit code " +
            "$($Result.ExitCode)). Refusing further installer operations or " +
            "filesystem cleanup. Log: $($Result.LogPath)" +
            "$([Environment]::NewLine)$diagnostic")
    }
    if ($Result.ExitCode -ne 0) {
        $diagnostic = Get-BoundedMsiLogDiagnostic -Path $Result.LogPath
        throw (
            "$Operation failed with exit code $($Result.ExitCode). Log: " +
            "$($Result.LogPath)$([Environment]::NewLine)$diagnostic")
    }
}

function Invoke-InstalledNativeHostSmoke {
    param([string]$Phase)

    $launcherPath = Join-Path $installRoot 'WireSockUI.exe'
    & (Join-Path $PSScriptRoot 'Test-NativeHost.ps1') `
        -LauncherPath $launcherPath `
        -SkipBcryptSentinel |
        ForEach-Object { Write-Host "$Phase`: $_" }
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
    $ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    $privilegedOwnerSids = @(
        'S-1-5-18',
        'S-1-5-32-544',
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    )
    if (-not ($privilegedOwnerSids -contains $ownerSid)) {
        throw "Installed entry '$Path' has untrusted owner SID '$ownerSid'."
    }

    $privilegedWriterSids = @(
        'S-1-5-18',
        'S-1-5-32-544',
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    )
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
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            $rightsAreUnsafe -and
            -not ($privilegedWriterSids -contains $ruleSid)) {
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

function Set-UntrustedWritableAcl {
    param(
        [string]$Path,
        [switch]$Directory
    )

    $acl = Get-Acl -LiteralPath $Path
    $acl.SetOwner($currentUserSid)
    $inheritanceFlags = if ($Directory) {
        [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [Security.AccessControl.InheritanceFlags]::ObjectInherit
    }
    else {
        [Security.AccessControl.InheritanceFlags]::None
    }
    $untrustedWriterSid =
        [Security.Principal.SecurityIdentifier]::new(
            'S-1-5-32-545')
    $unsafeRule = [Security.AccessControl.FileSystemAccessRule]::new(
        $untrustedWriterSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        $inheritanceFlags,
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($unsafeRule)
    Set-Acl -LiteralPath $Path -AclObject $acl

    $corruptedAcl = Get-Acl -LiteralPath $Path
    $corruptedOwnerSid = $corruptedAcl.GetOwner(
        [Security.Principal.SecurityIdentifier]).Value
    $hasUnsafeWriter = @(
        $corruptedAcl.GetAccessRules(
            $true,
            $true,
            [Security.Principal.SecurityIdentifier]) |
            Where-Object {
                $_.IdentityReference.Value -ceq
                    $untrustedWriterSid.Value -and
                $_.AccessControlType -eq
                    [Security.AccessControl.AccessControlType]::Allow -and
                (Test-MsiWriteCapableFileSystemRights `
                    -Rights $_.FileSystemRights)
            }
    ).Count -gt 0
    if ($corruptedOwnerSid -cne $currentUserSid.Value -or
        -not $hasUnsafeWriter) {
        throw "Failed to establish the unsafe ACL repair fixture at '$Path'."
    }
}

$productCode = [string]$metadata.ProductCode
if ((Get-ProductState -ProductCode $productCode) -ne -1) {
    throw "Product $productCode is already registered on the ephemeral machine."
}
$relatedProductCodes = @(
    Get-RelatedProductCodes -UpgradeCode ([string]$metadata.UpgradeCode)
)
if ($relatedProductCodes.Count -ne 0) {
    throw "The ephemeral machine has related WireSock UI product(s) registered: $($relatedProductCodes -join ', ')."
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'WireSockUI.Msi.InstallTest.' + [Guid]::NewGuid().ToString('N'))
$operationIndex = 0
$sentinelRoot = Join-Path $testRoot 'legacy-junction-target'
$sentinelPath = Join-Path $sentinelRoot 'must-not-change.txt'
$sentinelContent = 'WireSock UI MSI legacy-path sentinel'
$installed = $false
$legacyJunctionCreated = $false
$installerStateSafeForCleanup = $true
$primaryError = $null
$cleanupErrors = New-Object 'System.Collections.Generic.List[string]'

try {
    [IO.Directory]::CreateDirectory($sentinelRoot) | Out-Null
    [IO.File]::WriteAllText(
        $sentinelPath,
        $sentinelContent,
        [Text.UTF8Encoding]::new($false))
    $sentinelHash = (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash
    New-Item -ItemType Junction -Path $legacyInstallRoot -Target $sentinelRoot |
        Out-Null
    $legacyJunctionCreated = $true

    $packageValidationParameters = @{
        MsiPath = $resolvedMsiPath
        ValidationMetadataPath = $resolvedMetadataPath
        ExpectedArchitecture = $architecture
        ExpectedVersion = [string]$metadata.ProductVersion
        ExpectedFlavor = [string]$metadata.Flavor
        ExpectedProductCode = $productCode
    }
    & (Join-Path $PSScriptRoot 'Test-MsiPackage.ps1') @packageValidationParameters

    $installResult = Invoke-MsiExec -Operation 'install' -Arguments @(
        '/i',
        $resolvedMsiPath,
        '/qn',
        '/norestart',
        'REBOOT=ReallySuppress'
    )
    Assert-MsiOperationSucceeded `
        -Result $installResult `
        -Operation 'MSI installation'
    $installed = $true

    if ((Get-ProductState -ProductCode $productCode) -eq -1) {
        throw 'Windows Installer did not register the installed product.'
    }
    if (-not [IO.Directory]::Exists($installRoot)) {
        throw "MSI did not create expected application directory '$installRoot'."
    }

    $legacyEntry = Get-Item -LiteralPath $legacyInstallRoot -Force
    if (($legacyEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or
        -not [IO.File]::Exists($sentinelPath) -or
        (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash -cne $sentinelHash -or
        [IO.File]::ReadAllText($sentinelPath) -cne $sentinelContent -or
        @(Get-ChildItem -LiteralPath $sentinelRoot -Force).Count -ne 1) {
        throw 'MSI touched the hostile legacy-path junction or its sentinel target.'
    }

    Assert-ProtectedEntry -Path $installRoot -RequireExactPayloadAcl
    $installedEntries = @(Get-ChildItem -LiteralPath $installRoot -Recurse -Force)
    foreach ($entry in $installedEntries) {
        Assert-ProtectedEntry `
            -Path $entry.FullName `
            -RequireExactPayloadAcl
    }

    $expectedFiles = @{}
    foreach ($file in @($metadata.Files)) {
        $expectedFiles[[string]$file.Path] = $file
    }
    $actualFiles = @($installedEntries | Where-Object { -not $_.PSIsContainer })
    if ($actualFiles.Count -ne $expectedFiles.Count) {
        throw "Installed image contains $($actualFiles.Count) files; expected $($expectedFiles.Count)."
    }
    foreach ($file in $actualFiles) {
        $relativePath = $file.FullName.Substring(
            $installRoot.TrimEnd('\', '/').Length).TrimStart('\', '/').Replace('\', '/')
        if (-not $expectedFiles.ContainsKey($relativePath)) {
            throw "Installed image contains unexpected file '$relativePath'."
        }
        $expectedFile = $expectedFiles[$relativePath]
        if ($file.Length -ne [Int64]$expectedFile.Size -or
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne
                [string]$expectedFile.Sha256) {
            throw "Installed file '$relativePath' does not match validation metadata."
        }
    }

    foreach ($shortcutPath in $shortcutPaths) {
        if (-not [IO.File]::Exists($shortcutPath)) {
            throw "All-users shortcut '$shortcutPath' was not installed."
        }
        # The validated parent denies untrusted creation, so inherited
        # delete-only access cannot be used to replace the shortcut.
        Assert-ProtectedEntry -Path $shortcutPath -AllowDeleteOnly
        $shell = $null
        $shortcut = $null
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $actualTarget = [IO.Path]::GetFullPath(
                [string]$shortcut.TargetPath)
            $expectedTarget = [IO.Path]::GetFullPath(
                (Join-Path $installRoot 'WireSockUI.exe'))
            $actualWorkingDirectory = [IO.Path]::GetFullPath(
                [string]$shortcut.WorkingDirectory)
            if (-not [string]::Equals(
                    $actualTarget,
                    $expectedTarget,
                    [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals(
                    $actualWorkingDirectory.TrimEnd('\'),
                    [IO.Path]::GetFullPath($installRoot).TrimEnd('\'),
                    [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::IsNullOrEmpty([string]$shortcut.Arguments)) {
                throw "All-users shortcut '$shortcutPath' does not target the stable native launcher exactly."
            }
        }
        finally {
            if ($null -ne $shortcut) {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) | Out-Null
            }
            if ($null -ne $shell) {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
            }
        }
    }
    Invoke-InstalledNativeHostSmoke -Phase 'Installed native-host smoke'

    # Ordinary repair must restore every manifest-bound unversioned companion
    # from the cached MSI/source before the stronger force-all repair runs.
    $ordinaryRepairRelativePaths = @(
        Get-MsiCompanionRelativePaths -Path $resolvedMsiPath)
    foreach ($relativePath in $ordinaryRepairRelativePaths) {
        if (-not $expectedFiles.ContainsKey($relativePath)) {
            throw "Validation metadata does not contain companion '$relativePath'."
        }
        [IO.File]::WriteAllText(
            (Join-Path $installRoot $relativePath),
            "<tampered-companion path=`"$relativePath`" />",
            [Text.UTF8Encoding]::new($false))
    }
    $normalRepairResult = Invoke-MsiExec -Operation 'ordinary-repair' -Arguments @(
        '/fomus',
        $productCode,
        '/qn',
        '/norestart',
        'REBOOT=ReallySuppress'
    )
    Assert-MsiOperationSucceeded `
        -Result $normalRepairResult `
        -Operation 'MSI ordinary repair'
    foreach ($relativePath in $ordinaryRepairRelativePaths) {
        $expectedCompanion = $expectedFiles[$relativePath]
        $companionPath = Join-Path $installRoot $relativePath
        $repairedCompanion = Get-Item -LiteralPath $companionPath -Force
        if ($repairedCompanion.Length -ne [Int64]$expectedCompanion.Size -or
            (Get-FileHash -LiteralPath $companionPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
                [string]$expectedCompanion.Sha256) {
            throw "Ordinary MSI repair did not restore companion '$relativePath'."
        }
        Assert-ProtectedEntry `
            -Path $companionPath `
            -RequireExactPayloadAcl
    }
    Assert-ProtectedEntry -Path $installRoot -RequireExactPayloadAcl

    # Exercise force-all repair too. Remove one payload file and independently
    # corrupt the root, another root file, and (when present) one nested
    # directory/file pair selected from the package's validation metadata.
    # Protected child DACLs do not inherit later root changes, so each object
    # class is changed explicitly before MSI is required to normalize it.
    [string[]]$rootFileRelativePaths = @(
        $expectedFiles.Keys |
            Where-Object { -not ([string]$_).Contains('/') }
    )
    [Array]::Sort($rootFileRelativePaths, [StringComparer]::Ordinal)
    if ($rootFileRelativePaths.Count -lt 2) {
        throw 'Validation metadata must contain at least two root payload files for independent repair fixtures.'
    }
    $repairFilePath =
        Join-Path $installRoot $rootFileRelativePaths[0]
    Remove-Item -LiteralPath $repairFilePath -Force
    $rootAclRepairFile =
        Join-Path $installRoot $rootFileRelativePaths[1]
    Set-UntrustedWritableAcl -Path $installRoot -Directory
    Set-UntrustedWritableAcl -Path $rootAclRepairFile

    [string[]]$nestedFileRelativePaths = @(
        $expectedFiles.Keys |
            Where-Object { ([string]$_).Contains('/') }
    )
    [Array]::Sort($nestedFileRelativePaths, [StringComparer]::Ordinal)
    if ($nestedFileRelativePaths.Count -gt 0) {
        $nestedFileRelativePath = $nestedFileRelativePaths[0]
        $nestedDirectoryRelativePath = $nestedFileRelativePath.Substring(
            0,
            $nestedFileRelativePath.LastIndexOf('/'))
        $nestedAclRepairDirectory = Join-Path `
            $installRoot `
            $nestedDirectoryRelativePath.Replace(
                '/',
                [IO.Path]::DirectorySeparatorChar)
        $nestedAclRepairFile = Join-Path `
            $installRoot `
            $nestedFileRelativePath.Replace(
                '/',
                [IO.Path]::DirectorySeparatorChar)
        Set-UntrustedWritableAcl `
            -Path $nestedAclRepairDirectory `
            -Directory
        Set-UntrustedWritableAcl -Path $nestedAclRepairFile
    }

    $repairResult = Invoke-MsiExec -Operation 'force-all-repair' -Arguments @(
        '/fa',
        $resolvedMsiPath,
        '/qn',
        '/norestart',
        'REBOOT=ReallySuppress'
    )
    Assert-MsiOperationSucceeded `
        -Result $repairResult `
        -Operation 'MSI force-all repair'

    Assert-ProtectedEntry -Path $installRoot -RequireExactPayloadAcl
    $repairedEntries = @(Get-ChildItem -LiteralPath $installRoot -Recurse -Force)
    $repairedFiles = @($repairedEntries | Where-Object { -not $_.PSIsContainer })
    if ($repairedFiles.Count -ne $expectedFiles.Count) {
        throw "Repaired image contains $($repairedFiles.Count) files; expected $($expectedFiles.Count)."
    }
    foreach ($file in $repairedEntries) {
        Assert-ProtectedEntry `
            -Path $file.FullName `
            -RequireExactPayloadAcl
        if ($file.PSIsContainer) {
            continue
        }
        $relativePath = $file.FullName.Substring(
            $installRoot.TrimEnd('\', '/').Length).TrimStart('\', '/').Replace('\', '/')
        if (-not $expectedFiles.ContainsKey($relativePath)) {
            throw "Repaired image contains unexpected file '$relativePath'."
        }
        $expectedFile = $expectedFiles[$relativePath]
        if ($file.Length -ne [Int64]$expectedFile.Size -or
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne
                [string]$expectedFile.Sha256) {
            throw "Repaired file '$relativePath' does not match validation metadata."
        }
    }
    if (@($shortcutPaths | Where-Object {
                -not [IO.File]::Exists($_)
            }).Count -ne 0 -or
        (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash -cne $sentinelHash) {
        throw 'MSI repair removed an all-users shortcut or touched the hostile legacy-path sentinel.'
    }
    Invoke-InstalledNativeHostSmoke -Phase 'Repaired native-host smoke'
}
catch {
    $primaryError = $_
}
finally {
    if (-not $installerStateSafeForCleanup) {
        $cleanupErrors.Add(
            'Cleanup was skipped because Windows Installer state is not known to be quiescent.')
    }
    else {
        try {
            if ($installed -or (Get-ProductState -ProductCode $productCode) -ne -1) {
                $uninstallResult = Invoke-MsiExec -Operation 'uninstall' -Arguments @(
                    '/x',
                    $productCode,
                    '/qn',
                    '/norestart',
                    'REBOOT=ReallySuppress'
                )
                Assert-MsiOperationSucceeded `
                    -Result $uninstallResult `
                    -Operation 'MSI uninstall'
            }
        }
        catch {
            $cleanupErrors.Add($_.Exception.Message)
        }

        if ($installerStateSafeForCleanup) {
            try {
                if ($legacyJunctionCreated -and [IO.Directory]::Exists($legacyInstallRoot)) {
                    $legacyEntry = Get-Item -LiteralPath $legacyInstallRoot -Force
                    if (($legacyEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                        throw "Refusing to clean legacy test path '$legacyInstallRoot' because it is no longer a junction."
                    }
                    [IO.Directory]::Delete($legacyInstallRoot)
                }
            }
            catch {
                $cleanupErrors.Add($_.Exception.Message)
            }
            try {
                if (Test-FileSystemEntryExists -Path $testRoot) {
                    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
                    $normalizedTempRoot = [IO.Path]::GetFullPath(
                        [IO.Path]::GetTempPath()).TrimEnd('\', '/') + '\'
                    $testRootEntry =
                        Get-Item -LiteralPath $resolvedTestRoot -Force
                    if (-not $resolvedTestRoot.StartsWith(
                            $normalizedTempRoot,
                            [StringComparison]::OrdinalIgnoreCase) -or
                        -not (Split-Path -Leaf $resolvedTestRoot).StartsWith(
                            'WireSockUI.Msi.InstallTest.',
                            [StringComparison]::Ordinal) -or
                        -not $testRootEntry.PSIsContainer -or
                        ($testRootEntry.Attributes -band
                            [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "Refusing to recursively clean unsafe test path '$resolvedTestRoot'."
                    }
                    [IO.Directory]::Delete($resolvedTestRoot, $true)
                }
            }
            catch {
                $cleanupErrors.Add($_.Exception.Message)
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
        "$($primaryError.Exception.Message)$cleanupSuffix",
        $primaryError.Exception)
}
if ($cleanupErrors.Count -gt 0) {
    throw "MSI installation and repair passed, but cleanup failed: $($cleanupErrors -join ' | ')"
}

if ((Get-ProductState -ProductCode $productCode) -ne -1 -or
    (Test-FileSystemEntryExists -Path $installRoot) -or
    (Test-FileSystemEntryExists -Path $legacyInstallRoot) -or
    @($shortcutPaths | Where-Object {
            Test-FileSystemEntryExists -Path $_
        }).Count -ne 0) {
    throw 'MSI-owned product state, application files, legacy test entry, or all-users shortcuts remained after uninstall.'
}

Write-Output "Installed, security-validated, and uninstalled $resolvedMsiPath without touching the hostile legacy-path junction."
