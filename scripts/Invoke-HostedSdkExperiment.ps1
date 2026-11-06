#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('x64', 'ARM64')]
    [string] $Platform
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedRepository = 'wiresock/WireSockUI'
$expectedRef = 'refs/heads/main'
$packageId = 'NTKERNEL.WireSockVPNClientCLI'
$packageManifestVersion = '3.4.8'
$packageInstallerReleaseVersion = '3.4.8.1'
$normalizedPlatform = switch ($Platform.ToLowerInvariant()) {
    'x64' { 'x64' }
    'arm64' { 'ARM64' }
    default { throw "Unsupported hosted SDK platform '$Platform'." }
}
$packageArchitecture = $normalizedPlatform.ToLowerInvariant()
$packageInstallerUriByArchitecture = @{
    x64 = [Uri](
        'https://wiresock.net/_api/download-release.php?' +
        'product=wiresock-secure-connect-sdk&platform=x64&' +
        "version=$packageInstallerReleaseVersion&channel=winget")
    arm64 = [Uri](
        'https://wiresock.net/_api/download-release.php?' +
        'product=wiresock-secure-connect-sdk&platform=ARM64&' +
        "version=$packageInstallerReleaseVersion&channel=winget")
}
$packageInstallerSha256ByArchitecture = @{
    x64 = 'ABFEEBDC645DE36B95FABBED00C7FDB0BF4D0C68C5518608450619C61876D33E'
    arm64 = '62F641A19C2D4A89CE58BA4C0539166982FB89373AEF3C87B66FEA33E26DB311'
}
$packageInstallerUri =
    $packageInstallerUriByArchitecture[$packageArchitecture]
$packageInstallerSha256 =
    $packageInstallerSha256ByArchitecture[$packageArchitecture]
if ($null -eq $packageInstallerUri -or
    $packageInstallerSha256 -cnotmatch '\A[0-9A-F]{64}\z') {
    throw (
        "No complete audited SDK installer metadata exists for " +
        "architecture '$packageArchitecture'.")
}
$expectedRunnerArchitecture = if ($normalizedPlatform -ceq 'ARM64') {
    [Runtime.InteropServices.Architecture]::Arm64
}
else {
    [Runtime.InteropServices.Architecture]::X64
}
$repositoryRoot = [IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot))
$versionResolverPath = Join-Path `
    $PSScriptRoot `
    'Resolve-BuildVersion.ps1'
$experimentVersion = & $versionResolverPath `
    -RepositoryRoot $repositoryRoot
$solutionPath = Join-Path $repositoryRoot 'WireSockUI.sln'
$installerProjectPath = Join-Path `
    $repositoryRoot `
    'WireSockUI.Installer\WireSockUI.Installer.wixproj'
$applicationProjectPath = Join-Path `
    $repositoryRoot `
    'WireSockUI\WireSockUI.csproj'
$testProjectPath = Join-Path `
    $repositoryRoot `
    'WireSockUI.Tests\WireSockUI.Tests.csproj'
$publishedPayloadPath = Join-Path `
    $repositoryRoot `
    "bin\$normalizedPlatform\Release\net472-windows\publish"
$workflowSecurityScriptPath = Join-Path `
    $PSScriptRoot `
    'Test-WorkflowSecurity.ps1'
$buildMsiScriptPath = Join-Path $PSScriptRoot 'Build-Msi.ps1'
$testMsiInstallationScriptPath = Join-Path `
    $PSScriptRoot `
    'Test-MsiInstallation.ps1'
$wireSockSdkRegistryPaths = @(
    'SOFTWARE\WireSock Foundation\WireSock Secure Connect',
    'SOFTWARE\WireSock Foundation\WireSock Secure Connect Pro',
    'SOFTWARE\NTKernelResources\WinpkFilterForVPNClient'
)

function Assert-LastExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Operation
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

function Assert-SdkInstallerExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [int] $ExitCode,

        [Parameter(Mandatory = $true)]
        [string] $Operation
    )

    if ($ExitCode -eq 0) {
        return
    }
    if ($ExitCode -eq 3010) {
        Write-Warning (
            "$Operation succeeded but requested a restart; continuing on " +
            'the disposable hosted runner.')
        return
    }
    throw "$Operation failed with exit code $ExitCode."
}

function Get-PortableExecutablePlatform {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 64) {
            throw "Portable executable '$Path' is truncated."
        }
        $reader = [IO.BinaryReader]::new($stream)
        try {
            if ($reader.ReadUInt16() -ne 0x5a4d) {
                throw "Portable executable '$Path' has no DOS header."
            }
            $stream.Position = 0x3c
            [UInt32] $peOffset = $reader.ReadUInt32()
            if ($peOffset -gt $stream.Length - 6) {
                throw "Portable executable '$Path' has an invalid PE offset."
            }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                throw "Portable executable '$Path' has no PE signature."
            }
            switch ($reader.ReadUInt16()) {
                0x014c { return 'x86' }
                0x8664 { return 'x64' }
                0xaa64 { return 'ARM64' }
                default {
                    throw "Portable executable '$Path' has an unsupported machine type."
                }
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Remove-HostedExperimentDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    try {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item `
                -LiteralPath $Path `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }
    }
    catch {
        Write-Warning (
            "Temporary directory cleanup failed for '$Path': " +
            "$($_.Exception.Message) GitHub will discard the hosted VM.")
    }
}

function Get-WireSockSdkLibraries {
    $registryViews = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )
    $locations = [Collections.Generic.List[string]]::new()
    foreach ($view in $registryViews) {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            $view)
        try {
            foreach ($registryPath in $wireSockSdkRegistryPaths) {
                $key = $baseKey.OpenSubKey($registryPath)
                try {
                    $location = if ($null -eq $key) {
                        ''
                    }
                    else {
                        [string]$key.GetValue('InstallLocation')
                    }
                    if (-not [string]::IsNullOrWhiteSpace($location) -and
                        -not $locations.Contains($location)) {
                        $locations.Add($location)
                    }
                }
                finally {
                    if ($null -ne $key) {
                        $key.Dispose()
                    }
                }
            }
        }
        finally {
            $baseKey.Dispose()
        }
    }

    $libraries = [Collections.Generic.List[string]]::new()
    foreach ($location in $locations) {
        foreach ($directory in @(
                (Join-Path $location 'sdk'),
                (Join-Path $location 'bin'),
                $location)) {
            $libraryPath = Join-Path $directory 'wgbooster.dll'
            if ((Test-Path -LiteralPath $libraryPath -PathType Leaf) -and
                -not $libraries.Contains($libraryPath)) {
                $libraries.Add((Resolve-Path -LiteralPath $libraryPath).Path)
            }
        }
    }
    return @($libraries)
}

function Wait-WireSockSdkLibraries {
    param(
        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 120,

        [ValidateRange(100, 10000)]
        [int] $PollIntervalMilliseconds = 2000
    )

    $timeoutMilliseconds = $TimeoutSeconds * 1000
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($stopwatch.ElapsedMilliseconds -lt $timeoutMilliseconds) {
            $libraries = @(Get-WireSockSdkLibraries)
            if ($libraries.Count -gt 0) {
                return $libraries
            }
            $remainingMilliseconds =
                $timeoutMilliseconds - $stopwatch.ElapsedMilliseconds
            if ($remainingMilliseconds -gt 0) {
                Start-Sleep -Milliseconds ([Math]::Min(
                        $PollIntervalMilliseconds,
                        [int]$remainingMilliseconds))
            }
        }
    }
    finally {
        $stopwatch.Stop()
    }

    throw (
        "The SDK installer registered no wgbooster.dll candidate within " +
        "$TimeoutSeconds seconds while polling every " +
        "$PollIntervalMilliseconds milliseconds. Expected InstallLocation " +
        'under the 32-bit or 64-bit HKLM registry paths ' +
        "'$($wireSockSdkRegistryPaths -join "', '")', with wgbooster.dll " +
        'in that location, sdk, or bin.')
}

function Set-ProtectedProfileAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory,

        [Parameter(Mandatory = $true)]
        [string[]] $Files
    )

    $administrators = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,
        $null)
    $system = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::LocalSystemSid,
        $null)
    $inheritance =
        [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $directoryAcl = [Security.AccessControl.DirectorySecurity]::new()
    $directoryAcl.SetOwner($administrators)
    $directoryAcl.SetAccessRuleProtection($true, $false)
    foreach ($identity in @($administrators, $system)) {
        $directoryAcl.AddAccessRule(
            [Security.AccessControl.FileSystemAccessRule]::new(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance,
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow))
    }
    Set-Acl -LiteralPath $Directory -AclObject $directoryAcl

    foreach ($file in $Files) {
        $fileAcl = [Security.AccessControl.FileSecurity]::new()
        $fileAcl.SetOwner($administrators)
        $fileAcl.SetAccessRuleProtection($true, $false)
        foreach ($identity in @($administrators, $system)) {
            $fileAcl.AddAccessRule(
                [Security.AccessControl.FileSystemAccessRule]::new(
                    $identity,
                    [Security.AccessControl.FileSystemRights]::FullControl,
                    [Security.AccessControl.AccessControlType]::Allow))
        }
        Set-Acl -LiteralPath $file -AclObject $fileAcl
    }
}

function New-HostedSdkProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    [void](New-Item -ItemType Directory -Path $Directory)
    $privateKey = [Convert]::ToBase64String([byte[]](1..32))
    $publicKey = [Convert]::ToBase64String([byte[]](33..64))
    $baseProfile = @(
        '[Interface]',
        "PrivateKey = $privateKey",
        'Address = 10.254.0.2/32',
        '',
        '[Peer]',
        "PublicKey = $publicKey",
        'Endpoint = 192.0.2.1:51820',
        'AllowedIPs = 198.51.100.0/24',
        ''
    ) -join "`r`n"
    $amneziaProfile = @(
        '[Interface]',
        "PrivateKey = $privateKey",
        'Address = 10.254.0.3/32',
        '#@ws:S1 = 64',
        '#@ws:S2 = 96',
        '#@ws:S3 = 128',
        '#@ws:S4 = 160',
        '#@ws:H1 = 10',
        '#@ws:H2 = 20',
        '#@ws:H3 = 30',
        '#@ws:H4 = 40',
        '#@ws:Id = example.com',
        '#@ws:Ip = quic',
        '#@ws:Ib = chrome',
        '',
        '[Peer]',
        "PublicKey = $publicKey",
        'Endpoint = 192.0.2.1:51820',
        'AllowedIPs = 198.51.100.0/24',
        ''
    ) -join "`r`n"

    $transparentPath = Join-Path $Directory 'transparent.conf'
    $virtualAdapterPath = Join-Path $Directory 'virtual-adapter.conf'
    $amneziaPath = Join-Path $Directory 'amnezia.conf'
    Set-Content -LiteralPath $transparentPath -Value $baseProfile -Encoding utf8NoBOM
    Set-Content -LiteralPath $virtualAdapterPath -Value $baseProfile -Encoding utf8NoBOM
    Set-Content -LiteralPath $amneziaPath -Value $amneziaProfile -Encoding utf8NoBOM
    $files = @($transparentPath, $virtualAdapterPath, $amneziaPath)
    Set-ProtectedProfileAcl -Directory $Directory -Files $files

    return [pscustomobject]@{
        Transparent = $transparentPath
        VirtualAdapter = $virtualAdapterPath
        Amnezia = $amneziaPath
    }
}

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne $expectedRepository -or
    $env:GITHUB_REF -cne $expectedRef -or
    $env:GITHUB_SHA -cnotmatch '\A[0-9a-f]{40}\z') {
    throw 'The hosted SDK experiment must run for the protected wiresock/WireSockUI main revision in GitHub Actions.'
}
if (-not [Environment]::Is64BitOperatingSystem -or
    [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne
        $expectedRunnerArchitecture) {
    throw (
        "The $normalizedPlatform hosted SDK experiment requires a native " +
        "$expectedRunnerArchitecture Windows runner.")
}
if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
    [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
    throw 'GitHub runner paths are unavailable.'
}
$runnerWorkspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE)
if (-not [string]::Equals(
        $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar),
        $runnerWorkspace.TrimEnd([IO.Path]::DirectorySeparatorChar),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Script repository root '$repositoryRoot' does not match GITHUB_WORKSPACE '$runnerWorkspace'."
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
        throw 'The hosted SDK experiment must run from an elevated administrator shell.'
    }
}
finally {
    $currentIdentity.Dispose()
}

$headSha = (git -C $repositoryRoot rev-parse 'HEAD^{commit}').Trim()
Assert-LastExitCode -Operation 'Resolving the experiment revision'
if ($headSha -cne $env:GITHUB_SHA) {
    throw "Checked-out revision '$headSha' does not match '$env:GITHUB_SHA'."
}

& $workflowSecurityScriptPath -RequireProductionContracts

$preexistingLibraries = @(Get-WireSockSdkLibraries)
if ($preexistingLibraries.Count -ne 0) {
    throw 'The disposable hosted runner unexpectedly contains a preinstalled WireSock SDK.'
}

$installedSdk = $false
$profileRoot = Join-Path $env:ProgramData (
    "WireSockUI-HostedSdkExperiment-$normalizedPlatform-" +
    [Guid]::NewGuid().ToString('N'))
$downloadRoot = Join-Path $env:RUNNER_TEMP (
    "WireSockUI-HostedSdkExperiment-Sdk-$normalizedPlatform-" +
    [Guid]::NewGuid().ToString('N'))
$msiRoot = Join-Path $env:RUNNER_TEMP (
    "WireSockUI-HostedSdkExperiment-Msi-$normalizedPlatform-" +
    [Guid]::NewGuid().ToString('N'))
$sdkInstallerPath = Join-Path $downloadRoot 'wiresock-sdk-installer.exe'
try {
    [void](New-Item -ItemType Directory -Path $downloadRoot)
    if ($packageInstallerUri.Scheme -cne 'https' -or
        $packageInstallerUri.Host -cne 'wiresock.net') {
        throw "Refusing unaudited SDK installer URI '$packageInstallerUri'."
    }
    Invoke-WebRequest `
        -Uri $packageInstallerUri `
        -OutFile $sdkInstallerPath `
        -MaximumRedirection 0
    $installerHash = (
        Get-FileHash -LiteralPath $sdkInstallerPath -Algorithm SHA256
    ).Hash
    if ($installerHash -cne $packageInstallerSha256) {
        throw "SDK installer digest '$installerHash' does not match the audited WinGet manifest."
    }
    $installerSignature = Get-AuthenticodeSignature -FilePath $sdkInstallerPath
    if ($installerSignature.Status -ne
        [Management.Automation.SignatureStatus]::Valid) {
        throw "SDK installer has Authenticode status '$($installerSignature.Status)'."
    }

    $installerProcess = Start-Process `
        -FilePath $sdkInstallerPath `
        -ArgumentList @('/S', '/NCRC') `
        -Wait `
        -PassThru
    Assert-SdkInstallerExitCode `
        -ExitCode $installerProcess.ExitCode `
        -Operation (
            "Installing $packageId manifest $packageManifestVersion " +
            "release $packageInstallerReleaseVersion")
    $installedSdk = $true

    $libraries = @(Wait-WireSockSdkLibraries)
    $libraryPath = $null
    foreach ($candidate in $libraries) {
        $signature = Get-AuthenticodeSignature -FilePath $candidate
        if ($signature.Status -eq
            [Management.Automation.SignatureStatus]::Valid) {
            $candidatePlatform = Get-PortableExecutablePlatform -Path $candidate
            if ($candidatePlatform -ceq $normalizedPlatform) {
                $libraryPath = $candidate
                break
            }
            Write-Warning (
                "Ignoring signed SDK library '$candidate' for " +
                "$candidatePlatform while testing $normalizedPlatform.")
            continue
        }
        Write-Warning (
            "Ignoring SDK library '$candidate' with Authenticode status " +
            "'$($signature.Status)'.")
    }
    if ([string]::IsNullOrWhiteSpace($libraryPath)) {
        throw (
            "The SDK installer registered no Authenticode-valid " +
            "$normalizedPlatform wgbooster.dll candidate.")
    }
    Write-Host "Validated signed SDK library '$libraryPath'."

    $profiles = New-HostedSdkProfiles -Directory $profileRoot

    dotnet restore $solutionPath `
        /p:Platform=$normalizedPlatform `
        --locked-mode `
        -m:1
    Assert-LastExitCode -Operation "Restoring the $normalizedPlatform solution"
    dotnet restore $installerProjectPath `
        --locked-mode
    Assert-LastExitCode -Operation 'Restoring the installer toolchain'

    dotnet publish $applicationProjectPath `
        --configuration Release `
        --framework net472-windows `
        --no-restore `
        --no-self-contained `
        /p:Platform=$normalizedPlatform `
        /p:UseSharedCompilation=false `
        /p:Version=$experimentVersion `
        /p:Repository=$expectedRepository `
        /p:RestoreLockedMode=true `
        -m:1
    Assert-LastExitCode `
        -Operation "Publishing the $normalizedPlatform WireSockUI candidate"

    & $buildMsiScriptPath `
        -Platform $normalizedPlatform `
        -Version $experimentVersion `
        -Flavor no-uwp `
        -PayloadDirectory $publishedPayloadPath `
        -OutputDirectory $msiRoot `
        -NoRestore

    $msis = @(Get-ChildItem -LiteralPath $msiRoot -File -Filter '*.msi')
    if ($msis.Count -ne 1) {
        throw "Expected one hosted experiment MSI; found $($msis.Count)."
    }
    & $testMsiInstallationScriptPath `
        -MsiPath $msis[0].FullName `
        -ValidationMetadataPath "$($msis[0].FullName).validation.json" `
        -EphemeralMachine

    $env:WIRESOCKUI_WGBOOSTER_PATH = $libraryPath
    $env:WIRESOCKUI_TEST_PROFILE_TRANSPARENT = $profiles.Transparent
    $env:WIRESOCKUI_TEST_PROFILE_VIRTUAL_ADAPTER = $profiles.VirtualAdapter
    $env:WIRESOCKUI_TEST_PROFILE_AMNEZIA = $profiles.Amnezia
    dotnet run `
        --project $testProjectPath `
        --configuration Release `
        --framework net472-windows `
        --no-restore `
        /p:Platform=$normalizedPlatform `
        /p:UseSharedCompilation=false `
        -- `
        --sdk-synthetic-integration
    Assert-LastExitCode `
        -Operation "Running the real $normalizedPlatform SDK lifecycle smoke test"

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value @(
            "### Hosted WireSock SDK $normalizedPlatform experiment passed",
            '',
            (
                "- Installed the audited $normalizedPlatform ``$packageId`` " +
                "manifest version ``$packageManifestVersion`` " +
                "(installer release ``$packageInstallerReleaseVersion``)."),
            "- Built and installation-tested the $normalizedPlatform no-UWP WireSockUI MSI.",
            '- Passed synthetic transparent, virtual-adapter, network-lock, and Amnezia SDK lifecycle checks without asserting external connectivity.'
        )
    }
}
finally {
    foreach ($name in @(
            'WIRESOCKUI_WGBOOSTER_PATH',
            'WIRESOCKUI_TEST_PROFILE_TRANSPARENT',
            'WIRESOCKUI_TEST_PROFILE_VIRTUAL_ADAPTER',
            'WIRESOCKUI_TEST_PROFILE_AMNEZIA')) {
        try {
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        catch {
            Write-Warning (
                "Environment cleanup failed for '$name': " +
                "$($_.Exception.Message) GitHub will discard the hosted VM.")
        }
    }
    Remove-HostedExperimentDirectory -Path $profileRoot
    Remove-HostedExperimentDirectory -Path $msiRoot
    if ($installedSdk -and
        (Test-Path -LiteralPath $sdkInstallerPath -PathType Leaf)) {
        try {
            $cleanupProcess = Start-Process `
                -FilePath $sdkInstallerPath `
                -ArgumentList @(
                    '/uninstall',
                    '/quiet',
                    '/norestart'
                ) `
                -Wait `
                -PassThru `
                -NoNewWindow
            Assert-SdkInstallerExitCode `
                -ExitCode $cleanupProcess.ExitCode `
                -Operation (
                    "Uninstalling $packageId manifest $packageManifestVersion " +
                    "release $packageInstallerReleaseVersion")
        }
        catch {
            Write-Warning (
                "SDK cleanup failed: $($_.Exception.Message) " +
                'GitHub will discard the hosted VM.')
        }
    }
    Remove-HostedExperimentDirectory -Path $downloadRoot
}
