[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateCount(6, 6)]
    [string[]]$MsiPath,

    [string]$ComponentIdentityMapPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptUnderTest =
    Join-Path $PSScriptRoot 'Test-MsiArchitectureIsolation.ps1'
$packageValidator =
    Join-Path $PSScriptRoot 'Test-MsiPackage.ps1'
if ([string]::IsNullOrWhiteSpace($ComponentIdentityMapPath)) {
    $ComponentIdentityMapPath = Join-Path `
        (Split-Path -Parent $PSScriptRoot) `
        'WireSockUI.Installer\ComponentIdentityMap.json'
}
$resolvedIdentityMapPath = [IO.Path]::GetFullPath(
    $ComponentIdentityMapPath)
$resolvedMsiPaths = @(
    $MsiPath | ForEach-Object { [IO.Path]::GetFullPath($_) }
)

$temporaryDirectory = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path `
    $temporaryDirectory `
    ("WireSockUI-MsiIdentity-{0}" -f [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)

function Invoke-ComMethod {
    param([object]$Instance, [string]$Name, [object[]]$Arguments)

    return $Instance.GetType().InvokeMember(
        $Name,
        [Reflection.BindingFlags]::InvokeMethod,
        $null,
        $Instance,
        $Arguments)
}

function Set-ComProperty {
    param([object]$Instance, [string]$Name, [object[]]$Arguments)

    $Instance.GetType().InvokeMember(
        $Name,
        [Reflection.BindingFlags]::SetProperty,
        $null,
        $Instance,
        $Arguments) | Out-Null
}

function Assert-WindowsLaunchConditionSemantics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Package,

        [Parameter(Mandatory = $true)]
        [ValidateSet('no-uwp', 'uwp')]
        [string]$Flavor
    )

    $installer = $null
    $session = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        # INSTALLUILEVEL_NONE prevents a regressed LaunchCondition from
        # displaying a modal message box and hanging a headless CI runner.
        Set-ComProperty $installer UILevel @([int]2)
        # Flag 1 is MSIOPENPACKAGEFLAGS_IGNOREMACHINESTATE. This creates a
        # read-only test session; it never runs an installation sequence.
        $session = Invoke-ComMethod `
            $installer `
            OpenPackage `
            @([string]$Package, [int]1)
        Set-ComProperty $session Property @('Installed', '')
        Set-ComProperty `
            $session `
            Property `
            @('NETFRAMEWORK472RELEASE', '#533325')

        if ($Flavor -eq 'uwp') {
            $condition = 'Installed OR VersionNT >= 603'
            $testCases = @(
                [pscustomobject]@{ Version = ''; ServicePack = ''; Expected = 0 }
                [pscustomobject]@{ Version = 601; ServicePack = 1; Expected = 0 }
                [pscustomobject]@{ Version = 602; ServicePack = 0; Expected = 0 }
                [pscustomobject]@{ Version = 603; ServicePack = 0; Expected = 1 }
            )
        }
        else {
            $condition =
                'Installed OR VersionNT >= 603 OR ' +
                '(VersionNT = 601 AND ServicePackLevel >= 1)'
            $testCases = @(
                [pscustomobject]@{ Version = ''; ServicePack = ''; Expected = 0 }
                [pscustomobject]@{ Version = 601; ServicePack = 0; Expected = 0 }
                [pscustomobject]@{ Version = 601; ServicePack = 1; Expected = 1 }
                [pscustomobject]@{ Version = 602; ServicePack = 0; Expected = 0 }
                [pscustomobject]@{ Version = 603; ServicePack = 0; Expected = 1 }
            )
        }
        foreach ($testCase in $testCases) {
            Set-ComProperty `
                $session `
                Property `
                @('VersionNT', [string]$testCase.Version)
            Set-ComProperty `
                $session `
                Property `
                @('ServicePackLevel', [string]$testCase.ServicePack)
            $evaluation = [int](
                Invoke-ComMethod `
                    $session `
                    EvaluateCondition `
                    @([string]$condition))
            if ($evaluation -ne $testCase.Expected) {
                throw (
                    "$Flavor Windows launch condition evaluated VersionNT " +
                    "'$($testCase.Version)' and ServicePackLevel " +
                    "'$($testCase.ServicePack)' as $evaluation; expected " +
                    "$($testCase.Expected).")
            }
        }

        Set-ComProperty $session Property @('VersionNT', '602')
        Set-ComProperty $session Property @('ServicePackLevel', '0')
        $rejectedActionStatus = [int](
            Invoke-ComMethod $session DoAction @('LaunchConditions'))
        if ($rejectedActionStatus -ne 3) {
            throw (
                "An unsupported Windows build returned MSI action status " +
                "$rejectedActionStatus; expected 3.")
        }

        if ($Flavor -eq 'uwp') {
            Set-ComProperty $session Property @('VersionNT', '603')
            Set-ComProperty $session Property @('ServicePackLevel', '0')
        }
        else {
            Set-ComProperty $session Property @('VersionNT', '601')
            Set-ComProperty $session Property @('ServicePackLevel', '1')
        }
        $actionStatus = [int](
            Invoke-ComMethod $session DoAction @('LaunchConditions'))
        if ($actionStatus -ne 1) {
            throw "LaunchConditions returned MSI action status $actionStatus; expected 1."
        }
    }
    catch {
        throw (
            "The $Flavor MSI Windows launch condition has incorrect " +
            "VersionNT/ServicePackLevel semantics: $($_.Exception.Message)")
    }
    finally {
        if ($null -ne $session) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $session) | Out-Null
        }
        if ($null -ne $installer) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $installer) | Out-Null
        }
    }
}

function New-IdentityMapCopy {
    return Get-Content `
        -LiteralPath $resolvedIdentityMapPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
}

function Get-IdentityEntry {
    param(
        [object]$Map,
        [string]$Architecture,
        [string]$Resource
    )

    $matches = @(
        $Map.Entries |
            Where-Object {
                [string]$_.Architecture -ceq $Architecture -and
                [string]$_.Resource -ceq $Resource
            }
    )
    if ($matches.Count -ne 1) {
        throw "Test fixture does not contain exactly one '$Architecture/$Resource' entry."
    }
    return $matches[0]
}

function Save-IdentityMap {
    param(
        [object]$Map,
        [string]$Name
    )

    $entries = [Collections.Generic.List[object]]::new()
    foreach ($entry in $Map.Entries) {
        $entries.Add($entry)
    }
    $entries.Sort(
        [Comparison[object]]{
            param($left, $right)

            return [StringComparer]::Ordinal.Compare(
                "$($left.Architecture)`0$($left.Resource)",
                "$($right.Architecture)`0$($right.Resource)")
        })
    $document = [ordered]@{
        Schema = [string]$Map.Schema
        Entries = @($entries)
    }
    $path = Join-Path $testRoot "$Name.json"
    $json = $document | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText(
        $path,
        $json,
        [Text.UTF8Encoding]::new($false))
    return $path
}

function Assert-ValidatorAccepts {
    param(
        [string]$Description,
        [string[]]$Packages,
        [string]$IdentityMapPath
    )

    try {
        & $scriptUnderTest `
            -MsiPath $Packages `
            -ComponentIdentityMapPath $IdentityMapPath |
            Out-Null
    }
    catch {
        throw "$Description was rejected unexpectedly: $($_.Exception.Message)"
    }
}

function Assert-ValidatorRejects {
    param(
        [string]$Description,
        [string[]]$Packages,
        [string]$IdentityMapPath,
        [string]$ExpectedMessage
    )

    try {
        & $scriptUnderTest `
            -MsiPath $Packages `
            -ComponentIdentityMapPath $IdentityMapPath |
            Out-Null
    }
    catch {
        if ($_.Exception.Message.IndexOf(
                $ExpectedMessage,
                [StringComparison]::Ordinal) -lt 0) {
            throw "$Description failed for an unexpected reason: $($_.Exception.Message)"
        }
        return
    }
    throw "$Description was accepted unexpectedly."
}

function Invoke-MsiUpdate {
    param(
        [string]$SourcePath,
        [string]$Name,
        [string[]]$Sql
    )

    $destinationPath = Join-Path $testRoot "$Name.msi"
    [IO.File]::Copy($SourcePath, $destinationPath, $false)
    $installer = $null
    $database = $null
    $view = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        try {
            $database = Invoke-ComMethod `
                $installer `
                OpenDatabase `
                @([string]$destinationPath, [int]1)
        }
        catch {
            throw "Could not open mutated MSI '$destinationPath': $($_.Exception.Message)"
        }
        try {
            foreach ($statement in $Sql) {
                $view = Invoke-ComMethod `
                    $database `
                    OpenView `
                    @([string]$statement)
                try {
                    Invoke-ComMethod $view Execute @() | Out-Null
                }
                finally {
                    try {
                        Invoke-ComMethod $view Close @() | Out-Null
                    }
                    finally {
                        [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                            $view) | Out-Null
                        $view = $null
                    }
                }
            }
            Invoke-ComMethod $database Commit @() | Out-Null
        }
        catch {
            throw "Could not apply MSI mutation '$Name': $($_.Exception.Message)"
        }
    }
    finally {
        if ($null -ne $view) {
            try {
                Invoke-ComMethod $view Close @() | Out-Null
            }
            finally {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                    $view) | Out-Null
            }
        }
        if ($null -ne $database) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $database) | Out-Null
        }
        if ($null -ne $installer) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $installer) | Out-Null
        }
    }
    return $destinationPath
}

function Get-NonHostVersionedFileId {
    param([string]$Path)

    $installer = $null
    $database = $null
    $view = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = Invoke-ComMethod `
            $installer `
            OpenDatabase `
            @([string]$Path, [int]0)
        $view = Invoke-ComMethod `
            $database `
            OpenView `
            @('SELECT `File`, `Version` FROM `File`')
        Invoke-ComMethod $view Execute @() | Out-Null
        while ($true) {
            $record = Invoke-ComMethod $view Fetch @()
            if ($null -eq $record) {
                break
            }
            try {
                $fileId = [string]$record.StringData(1)
                $version = [string]$record.StringData(2)
                if ($fileId -cne 'WireSockRuntimeHostFile' -and
                    $version -cmatch
                        '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
                    return $fileId
                }
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
                Invoke-ComMethod $view Close @() | Out-Null
            }
            finally {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                    $view) | Out-Null
            }
        }
        if ($null -ne $database) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $database) | Out-Null
        }
        if ($null -ne $installer) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                $installer) | Out-Null
        }
    }
    throw 'The fixture MSI has no non-host directly versioned payload file.'
}

function Assert-PackageValidatorRejects {
    param(
        [string]$Description,
        [string]$Package,
        [string]$ValidationMetadataPath,
        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$ExpectedArchitecture,
        [ValidateSet('no-uwp', 'uwp')]
        [string]$ExpectedFlavor,
        [string]$ExpectedVersion,
        [string]$ExpectedMessage
    )

    try {
        & $packageValidator `
            -MsiPath $Package `
            -ValidationMetadataPath $ValidationMetadataPath `
            -ExpectedArchitecture $ExpectedArchitecture `
            -ExpectedVersion $ExpectedVersion `
            -ExpectedFlavor $ExpectedFlavor |
            Out-Null
    }
    catch {
        if ($_.Exception.Message.IndexOf(
                $ExpectedMessage,
                [StringComparison]::Ordinal) -lt 0) {
            throw "$Description failed for an unexpected reason: $($_.Exception.Message)"
        }
        return
    }
    throw "$Description was accepted unexpectedly."
}

function Get-PackagesWithReplacement {
    param(
        [string]$OriginalPath,
        [string]$ReplacementPath
    )

    return @(
        $resolvedMsiPaths |
            ForEach-Object {
                if ([string]::Equals(
                        $_,
                        $OriginalPath,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    $ReplacementPath
                }
                else {
                    $_
                }
            }
    )
}

try {
    Assert-ValidatorAccepts `
        -Description 'The committed component identity map' `
        -Packages $resolvedMsiPaths `
        -IdentityMapPath $resolvedIdentityMapPath

    $targetResource = 'file:System.Buffers.dll'

    $guidDriftMap = New-IdentityMapCopy
    $guidDriftEntry = Get-IdentityEntry `
        -Map $guidDriftMap `
        -Architecture 'x64' `
        -Resource $targetResource
    $guidDriftEntry.Guid =
        [Guid]::NewGuid().ToString('B').ToUpperInvariant()
    $guidDriftMapPath =
        Save-IdentityMap -Map $guidDriftMap -Name 'guid-drift'
    Assert-ValidatorRejects `
        -Description 'A changed reviewed component GUID' `
        -Packages $resolvedMsiPaths `
        -IdentityMapPath $guidDriftMapPath `
        -ExpectedMessage 'changes the reviewed component GUID'

    $missingIdentityMap = New-IdentityMapCopy
    $missingIdentityMap.Entries = @(
        $missingIdentityMap.Entries |
            Where-Object {
                -not (
                    [string]$_.Architecture -ceq 'x64' -and
                    [string]$_.Resource -ceq $targetResource)
            }
    )
    $missingIdentityMapPath =
        Save-IdentityMap -Map $missingIdentityMap -Name 'missing-identity'
    Assert-ValidatorRejects `
        -Description 'An unreviewed installed resource' `
        -Packages $resolvedMsiPaths `
        -IdentityMapPath $missingIdentityMapPath `
        -ExpectedMessage 'without a reviewed component identity'

    $prematureRetirementMap = New-IdentityMapCopy
    $prematureRetirementEntry = Get-IdentityEntry `
        -Map $prematureRetirementMap `
        -Architecture 'x64' `
        -Resource $targetResource
    $prematureRetirementEntry.State = 'retired'
    $prematureRetirementMapPath = Save-IdentityMap `
        -Map $prematureRetirementMap `
        -Name 'premature-retirement'
    Assert-ValidatorRejects `
        -Description 'A package that restores a retired resource' `
        -Packages $resolvedMsiPaths `
        -IdentityMapPath $prematureRetirementMapPath `
        -ExpectedMessage 'restores retired resource'

    $futureActiveMap = New-IdentityMapCopy
    $futureActiveMap.Entries = @(
        $futureActiveMap.Entries
        [pscustomobject][ordered]@{
            Architecture = 'x64'
            Resource = 'file:WireSockUI.FutureIdentitySentinel.dll'
            Guid = [Guid]::NewGuid().ToString('B').ToUpperInvariant()
            State = 'active'
        }
    )
    $futureActiveMapPath =
        Save-IdentityMap -Map $futureActiveMap -Name 'future-active'
    Assert-ValidatorRejects `
        -Description 'An active identity omitted by the release matrix' `
        -Packages $resolvedMsiPaths `
        -IdentityMapPath $futureActiveMapPath `
        -ExpectedMessage 'omits active reviewed component identity'

    $futureRetiredMap = New-IdentityMapCopy
    $futureRetiredMap.Entries = @(
        $futureRetiredMap.Entries
        [pscustomobject][ordered]@{
            Architecture = 'x64'
            Resource = 'file:WireSockUI.RetiredIdentitySentinel.dll'
            Guid = [Guid]::NewGuid().ToString('B').ToUpperInvariant()
            State = 'retired'
        }
    )
    $futureRetiredMapPath =
        Save-IdentityMap -Map $futureRetiredMap -Name 'future-retired'
    Assert-ValidatorAccepts `
        -Description 'An explicit retired identity tombstone' `
        -Packages $resolvedMsiPaths `
        -IdentityMapPath $futureRetiredMapPath

    $x64NoUwpMatches = @(
        $resolvedMsiPaths |
            Where-Object {
                [IO.Path]::GetFileName($_) -cmatch
                    '^WireSockUI-[0-9]+\.[0-9]+\.[0-9]+-win-x64-no-uwp\.msi$'
            }
    )
    if ($x64NoUwpMatches.Count -ne 1) {
        throw 'The test requires exactly one canonically named x64/no-uwp MSI.'
    }
    $x64NoUwpPath = $x64NoUwpMatches[0]
    $x64NoUwpName = [IO.Path]::GetFileName($x64NoUwpPath)
    if ($x64NoUwpName -cnotmatch
        '^WireSockUI-(?<version>[0-9]+\.[0-9]+\.[0-9]+)-win-x64-no-uwp\.msi$') {
        throw 'The x64/no-uwp fixture MSI does not have a canonical versioned name.'
    }
    $x64NoUwpVersion = [string]$Matches.version

    $x86NoUwpMatches = @(
        $resolvedMsiPaths |
            Where-Object {
                [IO.Path]::GetFileName($_) -cmatch
                    '^WireSockUI-[0-9]+\.[0-9]+\.[0-9]+-win-x86-no-uwp\.msi$'
            }
    )
    if ($x86NoUwpMatches.Count -ne 1) {
        throw 'The test requires exactly one canonically named x86/no-uwp MSI.'
    }
    $x86NoUwpPath = $x86NoUwpMatches[0]
    $x86NoUwpName = [IO.Path]::GetFileName($x86NoUwpPath)
    if ($x86NoUwpName -cnotmatch
        '^WireSockUI-(?<version>[0-9]+\.[0-9]+\.[0-9]+)-win-x86-no-uwp\.msi$') {
        throw 'The x86/no-uwp fixture MSI does not have a canonical versioned name.'
    }
    $x86NoUwpVersion = [string]$Matches.version

    $x86UwpMatches = @(
        $resolvedMsiPaths |
            Where-Object {
                [IO.Path]::GetFileName($_) -cmatch
                    '^WireSockUI-[0-9]+\.[0-9]+\.[0-9]+-win-x86-uwp\.msi$'
            }
    )
    if ($x86UwpMatches.Count -ne 1) {
        throw 'The test requires exactly one canonically named x86/uwp MSI.'
    }
    $x86UwpPath = $x86UwpMatches[0]

    Assert-WindowsLaunchConditionSemantics `
        -Package $x86NoUwpPath `
        -Flavor 'no-uwp'
    Assert-WindowsLaunchConditionSemantics `
        -Package $x86UwpPath `
        -Flavor 'uwp'

    $always64FrameworkSearchMsi = Invoke-MsiUpdate `
        -SourcePath $x86NoUwpPath `
        -Name 'always64-framework-search' `
        -Sql (
            'UPDATE `RegLocator` SET `Type` = 18 WHERE `Signature_` = ' +
            '''NetFramework472ReleaseSearch''')
    Assert-PackageValidatorRejects `
        -Description 'An x86 package with a 64-bit .NET Framework registry locator' `
        -Package $always64FrameworkSearchMsi `
        -ValidationMetadataPath ($x86NoUwpPath + '.validation.json') `
        -ExpectedArchitecture 'x86' `
        -ExpectedFlavor 'no-uwp' `
        -ExpectedVersion $x86NoUwpVersion `
        -ExpectedMessage 'documented 32-bit .NET Framework release key'

    $versionNtWindowsGateMsi = Invoke-MsiUpdate `
        -SourcePath $x86NoUwpPath `
        -Name 'version-nt-windows-gate' `
        -Sql @(
            (
                'DELETE FROM `LaunchCondition` WHERE `Condition` = ' +
                '''Installed OR VersionNT >= 603 OR ' +
                '(VersionNT = 601 AND ServicePackLevel >= 1)'''
            ),
            (
                'INSERT INTO `LaunchCondition` (`Condition`, `Description`) ' +
                'VALUES (''Installed OR VersionNT >= 1000'', ' +
                '''WireSock UI requires Windows 7 SP1, Windows 8.1, or later.'')'
            ))
    Assert-PackageValidatorRejects `
        -Description 'An unsupported VersionNT Windows launch condition' `
        -Package $versionNtWindowsGateMsi `
        -ValidationMetadataPath ($x86NoUwpPath + '.validation.json') `
        -ExpectedArchitecture 'x86' `
        -ExpectedFlavor 'no-uwp' `
        -ExpectedVersion $x86NoUwpVersion `
        -ExpectedMessage 'MSI launch conditions contain unexpected rows'

    $keyPathDriftMsi = Invoke-MsiUpdate `
        -SourcePath $x64NoUwpPath `
        -Name 'key-path-drift' `
        -Sql (
            'UPDATE `Component` SET `KeyPath` = ' +
            '''WireSockRuntimeConfigFile'' WHERE `Component` = ' +
            '''WireSockRuntimeHostFile''')
    Assert-ValidatorRejects `
        -Description 'A runtime key-path drift' `
        -Packages (
            Get-PackagesWithReplacement `
                -OriginalPath $x64NoUwpPath `
                -ReplacementPath $keyPathDriftMsi) `
        -IdentityMapPath $resolvedIdentityMapPath `
        -ExpectedMessage (
            'does not use the native host as the exact runtime component key path')

    $companionDriftMsi = Invoke-MsiUpdate `
        -SourcePath $x64NoUwpPath `
        -Name 'companion-drift' `
        -Sql (
            'UPDATE `File` SET `Version` = ''InvalidCompanion'' ' +
            'WHERE `File` = ''WireSockRuntimeConfigFile''')
    Assert-ValidatorRejects `
        -Description 'A runtime companion-key drift' `
        -Packages (
            Get-PackagesWithReplacement `
                -OriginalPath $x64NoUwpPath `
                -ReplacementPath $companionDriftMsi) `
        -IdentityMapPath $resolvedIdentityMapPath `
        -ExpectedMessage (
            'does not make the runtime configuration a companion of the native host')

    $unversionedFileId =
        Get-NonHostVersionedFileId -Path $x64NoUwpPath
    $standaloneUnversionedMsi = Invoke-MsiUpdate `
        -SourcePath $x64NoUwpPath `
        -Name 'standalone-unversioned-runtime' `
        -Sql (
            'UPDATE `File` SET `Version` = NULL WHERE `File` = ' +
            "'$unversionedFileId'")
    Assert-PackageValidatorRejects `
        -Description 'A standalone unversioned manifest-bound runtime file' `
        -Package $standaloneUnversionedMsi `
        -ValidationMetadataPath ($x64NoUwpPath + '.validation.json') `
        -ExpectedArchitecture 'x64' `
        -ExpectedFlavor 'no-uwp' `
        -ExpectedVersion $x64NoUwpVersion `
        -ExpectedMessage 'standalone and unversioned'

    $packageGuidDriftMsi = Invoke-MsiUpdate `
        -SourcePath $x64NoUwpPath `
        -Name 'package-guid-drift' `
        -Sql (
            'UPDATE `Component` SET `ComponentId` = ' +
            "'$([Guid]::NewGuid().ToString('B').ToUpperInvariant())' " +
            'WHERE `Component` = ''WireSockRuntimeHostFile''')
    Assert-ValidatorRejects `
        -Description 'A package component-GUID drift' `
        -Packages (
            Get-PackagesWithReplacement `
                -OriginalPath $x64NoUwpPath `
                -ReplacementPath $packageGuidDriftMsi) `
        -IdentityMapPath $resolvedIdentityMapPath `
        -ExpectedMessage 'changes the reviewed component GUID'

    Write-Output (
        'Validated fail-closed MSI component identity, key-path, companion ' +
        'repair, and retirement behavior.')
}
finally {
    if ([IO.Directory]::Exists($testRoot)) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $temporaryPrefix =
            $temporaryDirectory.TrimEnd(
                [IO.Path]::DirectorySeparatorChar,
                [IO.Path]::AltDirectorySeparatorChar) +
            [IO.Path]::DirectorySeparatorChar
        $testRootItem = Get-Item -LiteralPath $resolvedTestRoot -Force
        if (-not $resolvedTestRoot.StartsWith(
                $temporaryPrefix,
                [StringComparison]::OrdinalIgnoreCase) -or
            ($testRootItem.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to clean unsafe test directory '$resolvedTestRoot'."
        }
        [IO.Directory]::Delete($resolvedTestRoot, $true)
    }
}
