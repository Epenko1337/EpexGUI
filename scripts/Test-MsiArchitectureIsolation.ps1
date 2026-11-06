[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateCount(2, 6)]
    [string[]]$MsiPath,

    [string]$ComponentIdentityMapPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$maximumMsiBytes = 2GB - 1
$maximumTableRows = 65536
$maximumTableFields = 32
$maximumFieldCharacters = 32767
$maximumQueryCharacters = 64MB
$maximumIdentityMapBytes = 1MB
$maximumIdentityEntries = 4096
$expectedUpgradeCode = '{5C1DDAE5-6681-41BF-B153-AB2952AA6DF1}'

function Invoke-ComMethod {
    param([object]$Instance, [string]$Name, [object[]]$Arguments)

    return $Instance.GetType().InvokeMember(
        $Name,
        [Reflection.BindingFlags]::InvokeMethod,
        $null,
        $Instance,
        $Arguments)
}

function Get-ComProperty {
    param([object]$Instance, [string]$Name, [object[]]$Arguments)

    return $Instance.GetType().InvokeMember(
        $Name,
        [Reflection.BindingFlags]::GetProperty,
        $null,
        $Instance,
        $Arguments)
}

function Get-Rows {
    param(
        [object]$Database,
        [string]$Sql,
        [int]$MaximumRows = $maximumTableRows
    )

    $view = $null
    try {
        $view = Invoke-ComMethod $Database OpenView @($Sql)
        Invoke-ComMethod $view Execute @() | Out-Null
        $rows = New-Object 'System.Collections.Generic.List[object]'
        [Int64]$queryCharacters = 0
        while ($true) {
            $record = Invoke-ComMethod $view Fetch @()
            if ($null -eq $record) {
                break
            }
            try {
                if ($rows.Count -ge $MaximumRows) {
                    throw "MSI query exceeded the $MaximumRows-row validation limit: $Sql"
                }
                $fieldCount = [int](Get-ComProperty $record FieldCount @())
                if ($fieldCount -lt 1 -or $fieldCount -gt $maximumTableFields) {
                    throw "MSI query returned invalid field count $fieldCount`: $Sql"
                }
                $row = New-Object 'System.Collections.Generic.List[string]'
                for ($index = 1; $index -le $fieldCount; $index++) {
                    $value =
                        [string](Get-ComProperty $record StringData @($index))
                    if ($value.Length -gt $maximumFieldCharacters -or
                        $queryCharacters -gt
                            $maximumQueryCharacters - $value.Length) {
                        throw "MSI query exceeded its bounded string-data limit: $Sql"
                    }
                    $queryCharacters += $value.Length
                    $row.Add($value)
                }
                $rows.Add($row.ToArray())
            }
            finally {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                    $record) | Out-Null
            }
        }
        return $rows.ToArray()
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
    }
}

function Get-LongMsiName {
    param([string]$Value)

    $targetName = ($Value -split ':', 2)[0]
    if ($targetName.Contains('|')) {
        return ($targetName -split '\|', 2)[1]
    }
    return $targetName
}

function Get-RelativeDirectory {
    param(
        [string]$DirectoryId,
        [Collections.IDictionary]$Directories,
        [string]$PackagePath
    )

    $segments = New-Object 'System.Collections.Generic.List[string]'
    $current = $DirectoryId
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    while (-not [string]::Equals(
            $current,
            'WireSockInstallFolder',
            [StringComparison]::Ordinal)) {
        if (-not $visited.Add($current)) {
            throw "MSI '$PackagePath' has a Directory-table cycle at '$current'."
        }
        if (-not $Directories.Contains($current)) {
            throw "MSI '$PackagePath' references unknown directory '$current'."
        }
        $directory = $Directories[$current]
        $name = [string]$directory.Name
        if (-not [string]::IsNullOrEmpty($name) -and $name -cne '.') {
            if ($name -in @('.', '..') -or
                $name.IndexOfAny([char[]]@('/', '\')) -ge 0) {
                throw "MSI '$PackagePath' has invalid installed directory name '$name'."
            }
            $segments.Insert(0, $name)
        }
        $current = [string]$directory.Parent
    }
    return [string]::Join('/', $segments)
}

function Assert-ExactJsonProperties {
    param(
        [object]$Object,
        [string[]]$Expected,
        [string]$Description
    )

    if ($null -eq $Object) {
        throw "$Description is null."
    }
    $actual = @($Object.PSObject.Properties.Name | Sort-Object)
    $expectedSorted = @($Expected | Sort-Object)
    if (@(
            Compare-Object `
                -ReferenceObject $expectedSorted `
                -DifferenceObject $actual `
                -CaseSensitive
        ).Count -ne 0) {
        throw "$Description does not have the exact expected JSON properties."
    }
}

function Test-IsReservedDeviceSegment {
    param([string]$Segment)

    $dotIndex = $Segment.IndexOf('.')
    $name = if ($dotIndex -ge 0) {
        $Segment.Substring(0, $dotIndex)
    }
    else {
        $Segment
    }
    if ($name -in @('CON', 'PRN', 'AUX', 'NUL')) {
        return $true
    }
    return $name.Length -eq 4 -and
        ($name.StartsWith('COM', [StringComparison]::OrdinalIgnoreCase) -or
         $name.StartsWith('LPT', [StringComparison]::OrdinalIgnoreCase)) -and
        $name[3] -ge '1' -and
        $name[3] -le '9'
}

function Test-IsCanonicalIdentityResource {
    param([string]$Resource)

    if ($Resource -in @(
            'component:ApplicationDirectorySecurity',
            'component:DesktopShortcutComponent',
            'component:StartMenuShortcutComponent')) {
        return $true
    }
    $prefix = if ($Resource.StartsWith(
            'file:',
            [StringComparison]::Ordinal)) {
        'file:'
    }
    elseif ($Resource.StartsWith(
            'directory:',
            [StringComparison]::Ordinal)) {
        'directory:'
    }
    else {
        return $false
    }
    if ($Resource.Length -gt 32768) {
        return $false
    }

    $path = $Resource.Substring($prefix.Length)
    if ([string]::IsNullOrWhiteSpace($path) -or
        $path.Contains('\') -or
        $path.StartsWith('/', [StringComparison]::Ordinal) -or
        $path.EndsWith('/', [StringComparison]::Ordinal) -or
        $path.Contains(':') -or
        $path -match '[\x00-\x1f\x7f]') {
        return $false
    }
    foreach ($segment in $path.Split('/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or
            $segment -in @('.', '..') -or
            $segment.EndsWith('.', [StringComparison]::Ordinal) -or
            $segment.EndsWith(' ', [StringComparison]::Ordinal) -or
            (Test-IsReservedDeviceSegment -Segment $segment)) {
            return $false
        }
    }
    return $true
}

if ([string]::IsNullOrWhiteSpace($ComponentIdentityMapPath)) {
    $ComponentIdentityMapPath = Join-Path `
        (Split-Path -Parent $PSScriptRoot) `
        'WireSockUI.Installer\ComponentIdentityMap.json'
}
# This map is an append-only installer compatibility boundary. Keep an entry's
# GUID unchanged while its resource exists. When removing a resource, retain the
# entry and change State to "retired"; if it returns, reactivate that same GUID.
# New resources require a new, explicitly reviewed active entry.
$resolvedIdentityMapPath = [IO.Path]::GetFullPath(
    $ComponentIdentityMapPath)
if (-not [IO.File]::Exists($resolvedIdentityMapPath)) {
    throw "MSI component identity map '$resolvedIdentityMapPath' does not exist."
}
$identityMapFile = Get-Item -LiteralPath $resolvedIdentityMapPath -Force
if (($identityMapFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    $identityMapFile.Length -lt 1 -or
    $identityMapFile.Length -gt $maximumIdentityMapBytes) {
    throw 'The MSI component identity map is a reparse point, empty, or larger than 1 MiB.'
}
$identityMap = Get-Content `
    -LiteralPath $resolvedIdentityMapPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json
Assert-ExactJsonProperties `
    -Object $identityMap `
    -Expected @('Schema', 'Entries') `
    -Description 'MSI component identity map'
if ([string]$identityMap.Schema -cne
    'WireSockUI-Msi-Component-Identity-v1') {
    throw 'The MSI component identity map has an unsupported schema.'
}

$identityEntries = @($identityMap.Entries)
if ($identityEntries.Count -lt 1 -or
    $identityEntries.Count -gt $maximumIdentityEntries) {
    throw "The MSI component identity map must contain between 1 and $maximumIdentityEntries entries."
}
$goldenIdentityByKey =
    [Collections.Generic.Dictionary[string,object]]::new(
        [StringComparer]::Ordinal)
$identityKeysByGuid = @{}
$previousIdentitySortKey = $null
foreach ($entry in $identityEntries) {
    Assert-ExactJsonProperties `
        -Object $entry `
        -Expected @('Architecture', 'Resource', 'Guid', 'State') `
        -Description 'MSI component identity entry'
    $entryArchitecture = [string]$entry.Architecture
    $entryResource = [string]$entry.Resource
    $entryGuid = [string]$entry.Guid
    $entryState = [string]$entry.State
    if ($entryArchitecture -cnotmatch '^(arm64|x64|x86)$' -or
        -not (Test-IsCanonicalIdentityResource -Resource $entryResource) -or
        $entryGuid -cnotmatch
            '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$' -or
        $entryState -cnotmatch '^(active|retired)$') {
        throw 'The MSI component identity map contains a noncanonical entry.'
    }

    $identityKey = "$entryArchitecture`0$entryResource"
    if ($null -ne $previousIdentitySortKey -and
        [StringComparer]::Ordinal.Compare(
            $previousIdentitySortKey,
            $identityKey) -ge 0) {
        throw 'The MSI component identity map is not uniquely and canonically sorted.'
    }
    $previousIdentitySortKey = $identityKey
    if ($goldenIdentityByKey.ContainsKey($identityKey)) {
        throw "The MSI component identity map duplicates '$entryArchitecture/$entryResource'."
    }
    $goldenIdentityByKey.Add($identityKey, $entry)
    if (-not $identityKeysByGuid.ContainsKey($entryGuid)) {
        $identityKeysByGuid[$entryGuid] =
            New-Object 'System.Collections.Generic.List[string]'
    }
    $identityKeysByGuid[$entryGuid].Add($identityKey)
}

foreach ($guid in $identityKeysByGuid.Keys) {
    $keys = @($identityKeysByGuid[$guid] | Sort-Object)
    if ($keys.Count -eq 1) {
        continue
    }
    if ($keys.Count -ne 2) {
        throw "The MSI component identity map reuses component GUID '$guid'."
    }
    $architecture = $keys[0].Split([char]0)[0]
    $expectedSharedKeys = @(
        "$architecture`0file:WireSockUI.exe",
        "$architecture`0file:WireSockUI.exe.config"
    )
    if (@(
            Compare-Object `
                -ReferenceObject $expectedSharedKeys `
                -DifferenceObject $keys `
                -CaseSensitive
        ).Count -ne 0 -or
        [string]$goldenIdentityByKey[$keys[0]].State -cne
            [string]$goldenIdentityByKey[$keys[1]].State) {
        throw "The MSI component identity map reuses component GUID '$guid' for unrelated or differently retired resources."
    }
}

foreach ($architecture in @('arm64', 'x64', 'x86')) {
    foreach ($requiredResource in @(
            'component:ApplicationDirectorySecurity',
            'component:DesktopShortcutComponent',
            'component:StartMenuShortcutComponent',
            'file:WireSockUI.exe',
            'file:WireSockUI.exe.config')) {
        $requiredKey = "$architecture`0$requiredResource"
        if (-not $goldenIdentityByKey.ContainsKey($requiredKey) -or
            [string]$goldenIdentityByKey[$requiredKey].State -cne 'active') {
            throw "The MSI component identity map lacks active core resource '$architecture/$requiredResource'."
        }
    }
}

$installer = New-Object -ComObject WindowsInstaller.Installer
try {
    $packages = New-Object 'System.Collections.Generic.List[object]'
    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase)
    $seenIdentities = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)

    foreach ($path in $MsiPath) {
        $resolvedPath = [IO.Path]::GetFullPath($path)
        if (-not [IO.File]::Exists($resolvedPath)) {
            throw "MSI '$resolvedPath' does not exist."
        }
        $msiFile = Get-Item -LiteralPath $resolvedPath -Force
        if (($msiFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $msiFile.Length -lt 1 -or
            $msiFile.Length -gt $maximumMsiBytes) {
            throw "MSI '$resolvedPath' is a reparse point, empty, or larger than the supported MSI limit."
        }
        if (-not $seenPaths.Add($resolvedPath)) {
            throw "MSI '$resolvedPath' was supplied more than once."
        }

        $database = $null
        try {
            $database = Invoke-ComMethod $installer OpenDatabase @($resolvedPath, 0)

            $properties = @{}
            foreach ($row in @(Get-Rows $database 'SELECT * FROM `Property`')) {
                $propertyName = [string]$row[0]
                if ($properties.ContainsKey($propertyName)) {
                    throw "MSI '$resolvedPath' has duplicate property '$propertyName'."
                }
                $properties[$propertyName] = [string]$row[1]
            }
            $architecture = [string]$properties.WIRESOCKUIARCHITECTURE
            $flavor = [string]$properties.WIRESOCKUIFLAVOR
            $productVersion = [string]$properties.ProductVersion
            $productCode = [string]$properties.ProductCode
            $upgradeCode = [string]$properties.UpgradeCode
            if ($architecture -cnotmatch '^(x86|x64|arm64)$' -or
                $flavor -cnotmatch '^(no-uwp|uwp)$' -or
                $productVersion -cnotmatch
                    '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or
                $productCode -cnotmatch
                    '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$' -or
                $upgradeCode -cne $expectedUpgradeCode) {
                throw "MSI '$resolvedPath' has invalid architecture, flavor, version, or product identity properties."
            }
            $identity = "$architecture|$flavor|$productVersion"
            if (-not $seenIdentities.Add($identity)) {
                throw "More than one MSI has package identity '$identity'."
            }

            $directories = @{}
            foreach ($row in @(
                    Get-Rows $database (
                        'SELECT `Directory`, `Directory_Parent`, `DefaultDir` ' +
                        'FROM `Directory`'))) {
                $directoryId = [string]$row[0]
                if ($directories.ContainsKey($directoryId)) {
                    throw "MSI '$resolvedPath' duplicates directory '$directoryId'."
                }
                $directories[$directoryId] = [pscustomobject]@{
                    Parent = [string]$row[1]
                    Name = Get-LongMsiName -Value ([string]$row[2])
                }
            }
            if (-not $directories.ContainsKey('WireSockInstallFolder')) {
                throw "MSI '$resolvedPath' does not define WireSockInstallFolder."
            }

            $componentGuids =
                [Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase)
            $components = @{}
            $resourceByComponentGuid = @{}
            $filePathsByComponent = @{}
            foreach ($row in @(
                    Get-Rows $database 'SELECT * FROM `Component`')) {
                $componentId = [string]$row[0]
                $componentGuid = [string]$row[1]
                if ($componentId -cnotmatch
                        '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
                    $componentGuid -cnotmatch
                        '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$' -or
                    $components.ContainsKey($componentId) -or
                    -not $componentGuids.Add($componentGuid)) {
                    throw "MSI '$resolvedPath' has a missing, noncanonical, or duplicate component identity."
                }
                $components[$componentId] = [pscustomobject]@{
                    Guid = $componentGuid
                    Directory = [string]$row[2]
                    KeyPath = [string]$row[5]
                }
            }
            foreach ($requiredComponent in @(
                    'ApplicationDirectorySecurity',
                    'DesktopShortcutComponent',
                    'StartMenuShortcutComponent')) {
                if (-not $components.ContainsKey($requiredComponent)) {
                    throw "MSI '$resolvedPath' lacks required component '$requiredComponent'."
                }
            }

            $createFolderComponentByDirectory = @{}
            $createFolderDirectoryByComponent = @{}
            foreach ($row in @(
                    Get-Rows $database 'SELECT * FROM `CreateFolder`')) {
                $directoryId = [string]$row[0]
                $componentId = [string]$row[1]
                if (-not $directories.ContainsKey($directoryId) -or
                    -not $components.ContainsKey($componentId) -or
                    $createFolderComponentByDirectory.ContainsKey(
                        $directoryId) -or
                    $createFolderDirectoryByComponent.ContainsKey(
                        $componentId)) {
                    throw "MSI '$resolvedPath' has duplicate, unknown, or shared CreateFolder ownership."
                }
                $createFolderComponentByDirectory[$directoryId] =
                    $componentId
                $createFolderDirectoryByComponent[$componentId] =
                    $directoryId
            }
            if (-not $createFolderComponentByDirectory.ContainsKey(
                    'WireSockInstallFolder') -or
                [string]$createFolderComponentByDirectory[
                    'WireSockInstallFolder'] -cne
                    'ApplicationDirectorySecurity') {
                throw "MSI '$resolvedPath' lacks exact application-directory CreateFolder ownership."
            }

            $fileComponentGuidsByPath =
                [Collections.Generic.Dictionary[string,string]]::new(
                    [StringComparer]::OrdinalIgnoreCase)
            $resourceGuidsByName =
                [Collections.Generic.Dictionary[string,string]]::new(
                    [StringComparer]::Ordinal)
            foreach ($requiredComponent in @(
                    'ApplicationDirectorySecurity',
                    'DesktopShortcutComponent',
                    'StartMenuShortcutComponent')) {
                $resourceGuidsByName.Add(
                    "component:$requiredComponent",
                    [string]$components[$requiredComponent].Guid)
            }
            foreach ($row in @(Get-Rows $database 'SELECT * FROM `File`')) {
                $fileId = [string]$row[0]
                $componentId = [string]$row[1]
                if (-not $components.ContainsKey($componentId)) {
                    throw "MSI '$resolvedPath' file references unknown component '$componentId'."
                }
                $fileName = Get-LongMsiName -Value ([string]$row[2])
                if ([string]::IsNullOrEmpty($fileName) -or
                    $fileName -in @('.', '..') -or
                    $fileName.IndexOfAny([char[]]@('/', '\')) -ge 0) {
                    throw "MSI '$resolvedPath' has invalid installed file name '$fileName'."
                }
                $relativeDirectory = Get-RelativeDirectory `
                    -DirectoryId ([string]$components[$componentId].Directory) `
                    -Directories $directories `
                    -PackagePath $resolvedPath
                $relativePath = if ([string]::IsNullOrEmpty(
                        $relativeDirectory)) {
                    $fileName
                }
                else {
                    "$relativeDirectory/$fileName"
                }
                if ($fileComponentGuidsByPath.ContainsKey($relativePath)) {
                    throw "MSI '$resolvedPath' installs more than one file at '$relativePath'."
                }
                if ($relativePath -ceq 'WireSockUI.exe') {
                    if ($fileId -cne 'WireSockRuntimeHostFile' -or
                        $componentId -cne 'WireSockRuntimeHostFile' -or
                        [string]$components[$componentId].KeyPath -cne
                            'WireSockRuntimeHostFile') {
                        throw "MSI '$resolvedPath' does not use the native host as the exact runtime component key path."
                    }
                }
                elseif ($relativePath -ceq 'WireSockUI.exe.config') {
                    if ($fileId -cne 'WireSockRuntimeConfigFile' -or
                        $componentId -cne 'WireSockRuntimeHostFile' -or
                        [string]$row[4] -cne 'WireSockRuntimeHostFile') {
                        throw "MSI '$resolvedPath' does not make the runtime configuration a companion of the native host."
                    }
                }
                elseif ($fileId -cne $componentId -or
                    [string]$components[$componentId].KeyPath -cne $fileId) {
                    throw "MSI '$resolvedPath' does not give '$relativePath' its own stable key-path component."
                }
                if (-not $filePathsByComponent.ContainsKey($componentId)) {
                    $filePathsByComponent[$componentId] =
                        New-Object 'System.Collections.Generic.List[string]'
                }
                elseif ($componentId -cne 'WireSockRuntimeHostFile') {
                    throw "MSI '$resolvedPath' assigns multiple payload files to component '$componentId'."
                }
                $filePathsByComponent[$componentId].Add($relativePath)
                $componentGuid = [string]$components[$componentId].Guid
                $fileComponentGuidsByPath.Add($relativePath, $componentGuid)
                $resourceGuidsByName.Add(
                    "file:$relativePath",
                    $componentGuid)
            }

            foreach ($componentId in $components.Keys) {
                $componentGuid = [string]$components[$componentId].Guid
                if ($componentId -in @(
                        'ApplicationDirectorySecurity',
                        'DesktopShortcutComponent',
                        'StartMenuShortcutComponent')) {
                    if ($filePathsByComponent.ContainsKey($componentId)) {
                        throw "MSI '$resolvedPath' attaches a payload file to installer-owned component '$componentId'."
                    }
                    $resourceByComponentGuid[$componentGuid] =
                        "component:$componentId"
                    continue
                }
                if (-not $filePathsByComponent.ContainsKey($componentId)) {
                    if (-not $createFolderDirectoryByComponent.ContainsKey(
                            $componentId)) {
                        throw "MSI '$resolvedPath' has payload component '$componentId' without a file or directory resource."
                    }
                    $directoryId =
                        [string]$createFolderDirectoryByComponent[$componentId]
                    $relativeDirectory = Get-RelativeDirectory `
                        -DirectoryId $directoryId `
                        -Directories $directories `
                        -PackagePath $resolvedPath
                    if ([string]::IsNullOrEmpty($relativeDirectory) -or
                        [string]$components[$componentId].Directory -cne
                            $directoryId -or
                        -not [string]::IsNullOrEmpty(
                            [string]$components[$componentId].KeyPath)) {
                        throw "MSI '$resolvedPath' has noncanonical payload-directory component '$componentId'."
                    }
                    $directoryResource = "directory:$relativeDirectory"
                    $resourceGuidsByName.Add(
                        $directoryResource,
                        $componentGuid)
                    $resourceByComponentGuid[$componentGuid] =
                        $directoryResource
                    continue
                }
                $componentPaths = @(
                    $filePathsByComponent[$componentId] |
                        Sort-Object
                )
                if ($componentId -ceq 'WireSockRuntimeHostFile') {
                    $expectedRuntimePaths = @(
                        'WireSockUI.exe',
                        'WireSockUI.exe.config'
                    )
                    if (@(Compare-Object `
                            -ReferenceObject $expectedRuntimePaths `
                            -DifferenceObject $componentPaths).Count -ne 0) {
                        throw "MSI '$resolvedPath' runtime-host component has an unexpected file inventory."
                    }
                }
                elseif ($componentPaths.Count -ne 1) {
                    throw "MSI '$resolvedPath' payload component '$componentId' does not own exactly one file."
                }
                $resourceByComponentGuid[$componentGuid] =
                    'files:' + ($componentPaths -join '|')
            }

            $packages.Add([pscustomobject]@{
                Path = $resolvedPath
                Architecture = $architecture
                Flavor = $flavor
                ProductVersion = $productVersion
                ProductCode = $productCode
                UpgradeCode = $upgradeCode
                ComponentGuids = $componentGuids
                Components = $components
                FileComponentGuidsByPath = $fileComponentGuidsByPath
                ResourceByComponentGuid = $resourceByComponentGuid
                ResourceGuidsByName = $resourceGuidsByName
            })
        }
        finally {
            if ($null -ne $database) {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                    $database) | Out-Null
            }
        }
    }

    if (@($packages.UpgradeCode | Sort-Object -Unique).Count -ne 1) {
        throw 'MSI packages do not share the one major-upgrade identity.'
    }
    if (@($packages.ProductCode | Sort-Object -Unique).Count -ne
        $packages.Count) {
        throw 'MSI packages reuse a ProductCode.'
    }
    if ($packages.Count -eq 6) {
        if (@($packages.ProductVersion | Sort-Object -Unique).Count -ne 1) {
            throw 'The six-package release matrix does not use one exact product version.'
        }
        foreach ($architecture in @('x86', 'x64', 'arm64')) {
            foreach ($flavor in @('no-uwp', 'uwp')) {
                $matchingPackages = @(
                    $packages |
                        Where-Object {
                            $_.Architecture -ceq $architecture -and
                            $_.Flavor -ceq $flavor
                        }
                )
                if ($matchingPackages.Count -ne 1) {
                    throw "The six-package release matrix does not contain exactly one $architecture/$flavor package."
                }
            }
        }
    }

    $observedGoldenIdentityKeys =
        [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal)
    foreach ($package in $packages) {
        foreach ($resourceEntry in
            $package.ResourceGuidsByName.GetEnumerator()) {
            $identityKey =
                "$($package.Architecture)`0$($resourceEntry.Key)"
            $goldenEntry = $null
            if (-not $goldenIdentityByKey.TryGetValue(
                    $identityKey,
                    [ref]$goldenEntry)) {
                throw "MSI '$($package.Path)' contains resource '$($resourceEntry.Key)' without a reviewed component identity."
            }
            if ([string]$goldenEntry.State -cne 'active') {
                throw "MSI '$($package.Path)' restores retired resource '$($resourceEntry.Key)'. Review and reactivate its existing identity explicitly."
            }
            if ([string]$goldenEntry.Guid -cne
                [string]$resourceEntry.Value) {
                throw "MSI '$($package.Path)' changes the reviewed component GUID for '$($resourceEntry.Key)'."
            }
            [void]$observedGoldenIdentityKeys.Add($identityKey)
        }
    }
    if ($packages.Count -eq 6) {
        foreach ($goldenEntryPair in
            $goldenIdentityByKey.GetEnumerator()) {
            if ([string]$goldenEntryPair.Value.State -ceq 'active' -and
                -not $observedGoldenIdentityKeys.Contains(
                    $goldenEntryPair.Key)) {
                $displayKey = $goldenEntryPair.Key.Replace(
                    [char]0,
                    '/')
                throw "The six-package release matrix omits active reviewed component identity '$displayKey'. Mark an intentionally removed resource as retired."
            }
        }
    }

    for ($leftIndex = 0; $leftIndex -lt $packages.Count; $leftIndex++) {
        for ($rightIndex = $leftIndex + 1;
            $rightIndex -lt $packages.Count;
            $rightIndex++) {
            $left = $packages[$leftIndex]
            $right = $packages[$rightIndex]
            if ($left.Architecture -cne $right.Architecture) {
                $sharedGuids = @(
                    $left.ComponentGuids |
                        Where-Object { $right.ComponentGuids.Contains($_) }
                )
                if ($sharedGuids.Count -ne 0) {
                    throw "Different-architecture MSIs '$($left.Path)' and '$($right.Path)' share component GUID '$($sharedGuids[0])'."
                }
                continue
            }

            foreach ($requiredComponent in @(
                    'ApplicationDirectorySecurity',
                    'DesktopShortcutComponent',
                    'StartMenuShortcutComponent')) {
                $leftGuid =
                    [string]$left.Components[$requiredComponent].Guid
                $rightGuid =
                    [string]$right.Components[$requiredComponent].Guid
                if ($leftGuid -cne $rightGuid) {
                    throw "Same-architecture MSIs '$($left.Path)' and '$($right.Path)' change the GUID of '$requiredComponent'."
                }
            }

            foreach ($relativePath in
                $left.FileComponentGuidsByPath.Keys) {
                if (-not $right.FileComponentGuidsByPath.ContainsKey(
                        $relativePath)) {
                    continue
                }
                $leftGuid =
                    [string]$left.FileComponentGuidsByPath[$relativePath]
                $rightGuid =
                    [string]$right.FileComponentGuidsByPath[$relativePath]
                if ($leftGuid -cne $rightGuid) {
                    throw "Same-architecture MSIs '$($left.Path)' and '$($right.Path)' change the component GUID for installed path '$relativePath'."
                }
            }

            foreach ($sharedGuid in @(
                    $left.ComponentGuids |
                        Where-Object { $right.ComponentGuids.Contains($_) })) {
                $leftResource =
                    [string]$left.ResourceByComponentGuid[$sharedGuid]
                $rightResource =
                    [string]$right.ResourceByComponentGuid[$sharedGuid]
                if ($leftResource -cne $rightResource) {
                    throw "Same-architecture MSIs '$($left.Path)' and '$($right.Path)' reuse component GUID '$sharedGuid' for different resources ('$leftResource' and '$rightResource')."
                }
            }
        }
    }

    $packageDescriptions = @(
        $packages |
            ForEach-Object {
                "$($_.Architecture)/$($_.Flavor)/$($_.ProductVersion)"
            }
    )
    Write-Output (
        'Validated cross-architecture isolation and same-architecture ' +
        "component path stability for $($packageDescriptions -join ', ').")
}
finally {
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) |
        Out-Null
}
