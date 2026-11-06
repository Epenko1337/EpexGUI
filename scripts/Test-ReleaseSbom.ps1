[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $SbomPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ValidationMetadataPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $NuGetLockFilePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $NuGetTargetFramework,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ExpectedPackageName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z')]
    [string] $ExpectedVersion
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$maximumSbomBytes = 32MB
$maximumMetadataBytes = 4MB
$maximumLockFileBytes = 4MB
$maximumFiles = 4096
$maximumPackages = 4096
$maximumSnippets = 4096
$maximumRelationships = 16384
$maximumSpdxIdLength = 256

function Read-BoundedJson {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [Int64] $MaximumBytes
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $file = Get-Item -LiteralPath $resolvedPath -Force
    if ($file.PSIsContainer) {
        throw "JSON evidence '$resolvedPath' is not a file."
    }
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "JSON evidence '$resolvedPath' is a reparse point."
    }
    if ($file.Length -lt 1 -or $file.Length -gt $MaximumBytes) {
        throw "JSON evidence '$resolvedPath' is empty or exceeds the $MaximumBytes-byte limit."
    }

    try {
        return Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        throw "JSON evidence '$resolvedPath' is malformed: $($_.Exception.Message)"
    }
}

function Find-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $matches = @(
        $Object.PSObject.Properties |
            Where-Object { $_.Name -ceq $Name }
    )
    if ($matches.Count -gt 1) {
        throw "JSON object contains duplicate '$Name' properties."
    }
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[0]
}

function Get-RequiredJsonString {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Context,

        [int] $MaximumLength = 256
    )

    $property = Find-JsonProperty -Object $Object -Name $Name
    if ($null -eq $property) {
        throw "$Context is missing '$Name'."
    }

    $value = [string]$property.Value
    if ([string]::IsNullOrWhiteSpace($value) -or
        $value.Length -gt $MaximumLength -or
        $value -cne $value.Trim() -or
        $value -match '[\x00-\x1f\x7f]') {
        throw "$Context contains an invalid '$Name' value."
    }
    return $value
}

function Get-CanonicalEvidencePath {
    param([Parameter(Mandatory = $true)][string] $Path)

    $normalized = $Path.Replace('\', '/')
    if ($normalized.StartsWith('./', [StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }
    if ([string]::IsNullOrWhiteSpace($normalized) -or
        $normalized -cne $normalized.Trim() -or
        $normalized.StartsWith('/', [StringComparison]::Ordinal) -or
        $normalized.EndsWith('/', [StringComparison]::Ordinal) -or
        $normalized.Contains('//') -or
        $normalized.Contains(':') -or
        $normalized -match '[\x00-\x1f\x7f]' -or
        $normalized -match '(^|/)\.\.?(/|$)') {
        throw "Evidence contains unsafe file path '$Path'."
    }
    return $normalized
}

function Add-SpdxElementId {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Collections.Generic.HashSet[string]] $KnownIds,

        [Parameter(Mandatory = $true)]
        [string] $SpdxId,

        [Parameter(Mandatory = $true)]
        [string] $Context
    )

    if ($SpdxId.Length -gt $maximumSpdxIdLength -or
        $SpdxId -cnotmatch '^SPDXRef-[A-Za-z0-9.-]+$') {
        throw "$Context has invalid SPDX identifier '$SpdxId'."
    }
    if (-not $KnownIds.Add($SpdxId)) {
        throw "SPDX identifier '$SpdxId' is not unique."
    }
}

function Add-RelationshipKey {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Collections.Generic.HashSet[string]] $Relationships,

        [Parameter(Mandatory = $true)]
        [string] $Source,

        [Parameter(Mandatory = $true)]
        [string] $Type,

        [Parameter(Mandatory = $true)]
        [string] $Target,

        [string] $DuplicateMessage = 'The SPDX document contains a duplicate relationship.'
    )

    $key = "$Source|$Type|$Target"
    if (-not $Relationships.Add($key)) {
        throw "$DuplicateMessage ($Source $Type $Target)"
    }
    return $key
}

if ($ExpectedPackageName.Length -gt 256 -or
    $ExpectedPackageName -cne $ExpectedPackageName.Trim() -or
    $ExpectedPackageName -match '[\x00-\x1f\x7f]') {
    throw 'The expected package name is invalid.'
}
if ($NuGetTargetFramework.Length -gt 256 -or
    $NuGetTargetFramework -cne $NuGetTargetFramework.Trim() -or
    $NuGetTargetFramework -match '[\x00-\x1f\x7f]') {
    throw 'The NuGet target framework is invalid.'
}

$metadata = Read-BoundedJson `
    -Path $ValidationMetadataPath `
    -MaximumBytes $maximumMetadataBytes
if ([string]$metadata.Schema -cne 'WireSockUI-Msi-Validation-v1' -or
    [string]$metadata.ProductVersion -cne $ExpectedVersion) {
    throw 'The MSI validation metadata has an unexpected schema or product version.'
}

$expectedFiles = [Collections.Generic.Dictionary[string, string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($metadata.Files)) {
    $relativePath = Get-CanonicalEvidencePath -Path ([string]$entry.Path)
    $hash = [string]$entry.Sha256
    if ($hash -cnotmatch '^[0-9a-f]{64}$' -or
        $expectedFiles.ContainsKey($relativePath)) {
        throw "The MSI validation metadata contains a duplicate path or invalid hash at '$relativePath'."
    }
    $expectedFiles.Add($relativePath, $hash)
}
if ($expectedFiles.Count -lt 1 -or $expectedFiles.Count -gt $maximumFiles) {
    throw "The MSI validation metadata must contain between 1 and $maximumFiles files."
}

# Build the dependency identity and graph from the committed restore lock. The
# lock, rather than detector output, is the release authority for NuGet versions.
$lockFile = Read-BoundedJson `
    -Path $NuGetLockFilePath `
    -MaximumBytes $maximumLockFileBytes
if ([int]$lockFile.version -ne 1) {
    throw 'The NuGet lock file has an unsupported schema version.'
}
$lockDependenciesProperty = Find-JsonProperty -Object $lockFile -Name 'dependencies'
if ($null -eq $lockDependenciesProperty -or $null -eq $lockDependenciesProperty.Value) {
    throw 'The NuGet lock file does not contain a dependencies object.'
}
$targetProperties = @(
    $lockDependenciesProperty.Value.PSObject.Properties |
        Where-Object { $_.Name -ceq $NuGetTargetFramework }
)
if ($targetProperties.Count -ne 1 -or $null -eq $targetProperties[0].Value) {
    throw "The NuGet lock file does not contain exactly one '$NuGetTargetFramework' target."
}

$lockPackageProperties = @($targetProperties[0].Value.PSObject.Properties)
if ($lockPackageProperties.Count -gt ($maximumPackages - 1)) {
    throw "The NuGet lock target exceeds the $($maximumPackages - 1)-package limit."
}

$expectedNuGetPackages =
    [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase)
foreach ($packageProperty in $lockPackageProperties) {
    $packageName = [string]$packageProperty.Name
    if ([string]::IsNullOrWhiteSpace($packageName) -or
        $packageName.Length -gt 256 -or
        $packageName -cnotmatch '^[A-Za-z0-9_.-]+$' -or
        $packageName -ceq $ExpectedPackageName -or
        $expectedNuGetPackages.ContainsKey($packageName)) {
        throw "The NuGet lock target contains invalid or duplicate package '$packageName'."
    }

    $lockedPackage = $packageProperty.Value
    $resolvedVersion = Get-RequiredJsonString `
        -Object $lockedPackage `
        -Name 'resolved' `
        -Context "NuGet package '$packageName'" `
        -MaximumLength 128
    if ($resolvedVersion -cnotmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*$') {
        throw "NuGet package '$packageName' has invalid resolved version '$resolvedVersion'."
    }

    $packageType = Get-RequiredJsonString `
        -Object $lockedPackage `
        -Name 'type' `
        -Context "NuGet package '$packageName'" `
        -MaximumLength 16
    if ($packageType -cne 'Direct' -and $packageType -cne 'Transitive') {
        throw "NuGet package '$packageName' has unsupported type '$packageType'."
    }

    $contentHash = Get-RequiredJsonString `
        -Object $lockedPackage `
        -Name 'contentHash' `
        -Context "NuGet package '$packageName'" `
        -MaximumLength 128
    if ($contentHash -cnotmatch '^[A-Za-z0-9+/]{86}==$') {
        throw "NuGet package '$packageName' has an invalid SHA-512 content hash."
    }

    $packageDependencies =
        [Collections.Generic.Dictionary[string, string]]::new(
            [StringComparer]::OrdinalIgnoreCase)
    $packageDependenciesProperty =
        Find-JsonProperty -Object $lockedPackage -Name 'dependencies'
    if ($null -ne $packageDependenciesProperty) {
        if ($null -eq $packageDependenciesProperty.Value) {
            throw "NuGet package '$packageName' has a null dependencies object."
        }
        foreach ($dependencyProperty in @(
                $packageDependenciesProperty.Value.PSObject.Properties)) {
            $dependencyName = [string]$dependencyProperty.Name
            $dependencyVersion = [string]$dependencyProperty.Value
            if ([string]::IsNullOrWhiteSpace($dependencyName) -or
                $dependencyName.Length -gt 256 -or
                $dependencyName -cnotmatch '^[A-Za-z0-9_.-]+$' -or
                [string]::IsNullOrWhiteSpace($dependencyVersion) -or
                $dependencyVersion.Length -gt 128 -or
                $dependencyVersion -cnotmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*$' -or
                $packageDependencies.ContainsKey($dependencyName)) {
                throw "NuGet package '$packageName' contains an invalid or duplicate dependency."
            }
            $packageDependencies.Add($dependencyName, $dependencyVersion)
        }
    }

    $expectedNuGetPackages.Add(
        $packageName,
        [pscustomobject]@{
            Name = $packageName
            Version = $resolvedVersion
            Type = $packageType
            Dependencies = $packageDependencies
        })
}

foreach ($package in $expectedNuGetPackages.Values) {
    foreach ($dependency in $package.Dependencies.GetEnumerator()) {
        $lockedDependency = $null
        if (-not $expectedNuGetPackages.TryGetValue(
                $dependency.Key,
                [ref]$lockedDependency) -or
            $lockedDependency.Name -cne $dependency.Key -or
            $lockedDependency.Version -cne $dependency.Value) {
            throw "NuGet package '$($package.Name)' references unlocked dependency '$($dependency.Key)' version '$($dependency.Value)'."
        }
    }
}

# Lock entries must be reachable from a direct reference; stale/orphaned entries
# must not silently become release components.
$reachablePackages =
    [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
$packageQueue = [Collections.Generic.Queue[string]]::new()
foreach ($package in $expectedNuGetPackages.Values) {
    if ($package.Type -ceq 'Direct' -and $reachablePackages.Add($package.Name)) {
        $packageQueue.Enqueue($package.Name)
    }
}
while ($packageQueue.Count -gt 0) {
    $packageName = $packageQueue.Dequeue()
    $package = $expectedNuGetPackages[$packageName]
    foreach ($dependencyName in $package.Dependencies.Keys) {
        if ($reachablePackages.Add($dependencyName)) {
            $packageQueue.Enqueue($dependencyName)
        }
    }
}
if ($reachablePackages.Count -ne $expectedNuGetPackages.Count) {
    $orphanedPackages = @(
        $expectedNuGetPackages.Keys |
            Where-Object { -not $reachablePackages.Contains($_) } |
            Sort-Object
    )
    throw "The NuGet lock target contains packages unreachable from direct references: $($orphanedPackages -join ', ')."
}

$sbom = Read-BoundedJson -Path $SbomPath -MaximumBytes $maximumSbomBytes
$expectedDocumentName = "$ExpectedPackageName $ExpectedVersion"
if ([string]$sbom.spdxVersion -cne 'SPDX-2.2' -or
    [string]$sbom.dataLicense -cne 'CC0-1.0' -or
    [string]$sbom.name -cne $expectedDocumentName) {
    throw 'The generated document is not the expected SPDX 2.2 package SBOM.'
}

$documentNamespace = [string]$sbom.documentNamespace
$namespaceUri = $null
if (-not [Uri]::TryCreate(
        $documentNamespace,
        [UriKind]::Absolute,
        [ref]$namespaceUri) -or
    $namespaceUri.Scheme -cne 'https' -or
    -not [string]::IsNullOrEmpty($namespaceUri.UserInfo)) {
    throw 'The SPDX document namespace must be an absolute HTTPS URI without user information.'
}

$knownSpdxIds =
    [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$documentId = Get-RequiredJsonString `
    -Object $sbom `
    -Name 'SPDXID' `
    -Context 'The SPDX document' `
    -MaximumLength $maximumSpdxIdLength
if ($documentId -cne 'SPDXRef-DOCUMENT') {
    throw "The SPDX document identifier must be 'SPDXRef-DOCUMENT'."
}
Add-SpdxElementId `
    -KnownIds $knownSpdxIds `
    -SpdxId $documentId `
    -Context 'The SPDX document'

$sbomPackages = @($sbom.packages)
if ($sbomPackages.Count -ne ($expectedNuGetPackages.Count + 1) -or
    $sbomPackages.Count -gt $maximumPackages) {
    throw "The SPDX package inventory must contain one root and exactly $($expectedNuGetPackages.Count) locked NuGet packages."
}

$dependencyPackagesByName =
    [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase)
$matchingRootPackages = [Collections.Generic.List[object]]::new()
foreach ($package in $sbomPackages) {
    $packageId = Get-RequiredJsonString `
        -Object $package `
        -Name 'SPDXID' `
        -Context 'An SPDX package' `
        -MaximumLength $maximumSpdxIdLength
    Add-SpdxElementId `
        -KnownIds $knownSpdxIds `
        -SpdxId $packageId `
        -Context 'An SPDX package'

    $packageName = Get-RequiredJsonString `
        -Object $package `
        -Name 'name' `
        -Context "SPDX package '$packageId'"
    $packageVersion = Get-RequiredJsonString `
        -Object $package `
        -Name 'versionInfo' `
        -Context "SPDX package '$packageId'" `
        -MaximumLength 128

    if ($packageName -ceq $ExpectedPackageName -and
        $packageVersion -ceq $ExpectedVersion) {
        $matchingRootPackages.Add($package)
        continue
    }

    $expectedNuGetPackage = $null
    if (-not $expectedNuGetPackages.TryGetValue(
            $packageName,
            [ref]$expectedNuGetPackage)) {
        throw "The SPDX document contains unexpected package '$packageName' version '$packageVersion'."
    }
    if ($packageName -cne $expectedNuGetPackage.Name -or
        $packageVersion -cne $expectedNuGetPackage.Version -or
        $dependencyPackagesByName.ContainsKey($packageName)) {
        throw "The SPDX identity for locked NuGet package '$packageName' is missing, duplicated, or has the wrong version."
    }
    $dependencyPackagesByName.Add(
        $packageName,
        [pscustomobject]@{
            SpdxId = $packageId
            Package = $package
        })
}
if ($matchingRootPackages.Count -ne 1 -or
    $dependencyPackagesByName.Count -ne $expectedNuGetPackages.Count) {
    throw 'The SPDX document does not contain exactly one root and every locked NuGet package identity.'
}

$rootPackage = $matchingRootPackages[0]
$rootPackageId = [string]$rootPackage.SPDXID

$actualFiles =
    [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase)
$fileIds =
    [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$sbomFiles = @($sbom.files)
if ($sbomFiles.Count -lt 1 -or $sbomFiles.Count -gt $maximumFiles) {
    throw "The SPDX document must contain between 1 and $maximumFiles files."
}
foreach ($file in $sbomFiles) {
    $fileId = Get-RequiredJsonString `
        -Object $file `
        -Name 'SPDXID' `
        -Context 'An SPDX file' `
        -MaximumLength $maximumSpdxIdLength
    Add-SpdxElementId `
        -KnownIds $knownSpdxIds `
        -SpdxId $fileId `
        -Context 'An SPDX file'
    [void]$fileIds.Add($fileId)

    $relativePath = Get-CanonicalEvidencePath -Path (
        Get-RequiredJsonString `
            -Object $file `
            -Name 'fileName' `
            -Context "SPDX file '$fileId'" `
            -MaximumLength 1024)
    $sha256Checksums = @(
        @($file.checksums) |
            Where-Object { [string]$_.algorithm -ceq 'SHA256' }
    )
    if ($sha256Checksums.Count -ne 1 -or
        [string]$sha256Checksums[0].checksumValue -cnotmatch '^[0-9a-fA-F]{64}$' -or
        $actualFiles.ContainsKey($relativePath)) {
        throw "The SPDX file '$relativePath' has a missing, duplicate, or invalid SHA-256 checksum."
    }
    $actualFiles.Add(
        $relativePath,
        [pscustomobject]@{
            Sha256 =
                ([string]$sha256Checksums[0].checksumValue).ToLowerInvariant()
            SpdxId = $fileId
        })
}

$snippetsProperty = Find-JsonProperty -Object $sbom -Name 'snippets'
if ($null -ne $snippetsProperty) {
    $snippets = @($snippetsProperty.Value)
    if ($snippets.Count -gt $maximumSnippets) {
        throw "The SPDX document exceeds the $maximumSnippets-snippet limit."
    }
    foreach ($snippet in $snippets) {
        $snippetId = Get-RequiredJsonString `
            -Object $snippet `
            -Name 'SPDXID' `
            -Context 'An SPDX snippet' `
            -MaximumLength $maximumSpdxIdLength
        Add-SpdxElementId `
            -KnownIds $knownSpdxIds `
            -SpdxId $snippetId `
            -Context 'An SPDX snippet'
    }
}

if ($actualFiles.Count -ne $expectedFiles.Count) {
    throw "The SPDX file count $($actualFiles.Count) does not match the MSI inventory count $($expectedFiles.Count)."
}
foreach ($expected in $expectedFiles.GetEnumerator()) {
    $actualFile = $null
    if (-not $actualFiles.TryGetValue($expected.Key, [ref]$actualFile) -or
        $actualFile.Sha256 -cne $expected.Value) {
        throw "The SPDX digest for '$($expected.Key)' does not match the MSI inventory."
    }
}

$documentDescribesProperty =
    Find-JsonProperty -Object $sbom -Name 'documentDescribes'
if ($null -eq $documentDescribesProperty) {
    throw 'The SPDX document is missing documentDescribes.'
}
$documentDescribes = @($documentDescribesProperty.Value)
if ($documentDescribes.Count -ne 1 -or
    [string]$documentDescribes[0] -cne $rootPackageId) {
    throw 'The SPDX document must describe exactly the validated root package.'
}

$relationships = @($sbom.relationships)
if ($relationships.Count -lt 1 -or
    $relationships.Count -gt $maximumRelationships) {
    throw "The SPDX document must contain between 1 and $maximumRelationships relationships."
}
$relationshipKeys =
    [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$describesRelationships = [Collections.Generic.List[string]]::new()
$actualDependencyRelationships =
    [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$containedFileIds =
    [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$containmentRelationshipCount = 0
foreach ($relationship in $relationships) {
    $source = Get-RequiredJsonString `
        -Object $relationship `
        -Name 'spdxElementId' `
        -Context 'An SPDX relationship' `
        -MaximumLength $maximumSpdxIdLength
    $type = Get-RequiredJsonString `
        -Object $relationship `
        -Name 'relationshipType' `
        -Context "SPDX relationship from '$source'" `
        -MaximumLength 64
    $target = Get-RequiredJsonString `
        -Object $relationship `
        -Name 'relatedSpdxElement' `
        -Context "SPDX relationship from '$source'" `
        -MaximumLength $maximumSpdxIdLength
    if ($type -cnotmatch '^[A-Z][A-Z0-9_]{0,63}$') {
        throw "SPDX relationship from '$source' has invalid type '$type'."
    }
    if (-not $knownSpdxIds.Contains($source) -or
        -not $knownSpdxIds.Contains($target)) {
        throw "SPDX relationship '$source $type $target' references an unknown local element."
    }

    $relationshipKey = Add-RelationshipKey `
        -Relationships $relationshipKeys `
        -Source $source `
        -Type $type `
        -Target $target
    if ($type -ceq 'DESCRIBES') {
        $describesRelationships.Add($relationshipKey)
    }
    elseif ($type -ceq 'DEPENDS_ON') {
        [void]$actualDependencyRelationships.Add($relationshipKey)
    }
    elseif ($type -ceq 'CONTAINS' -or $type -ceq 'CONTAINED_BY') {
        $containmentRelationshipCount++
        $fileId = $null
        if ($type -ceq 'CONTAINS' -and
            $source -ceq $rootPackageId -and
            $fileIds.Contains($target)) {
            $fileId = $target
        }
        elseif ($type -ceq 'CONTAINED_BY' -and
            $target -ceq $rootPackageId -and
            $fileIds.Contains($source)) {
            $fileId = $source
        }
        else {
            throw "SPDX containment relationship '$source $type $target' is not between the root package and an inventoried file."
        }
        if (-not $containedFileIds.Add($fileId)) {
            throw "SPDX file '$fileId' has duplicate semantic containment relationships."
        }
    }
}

if ($describesRelationships.Count -ne 1 -or
    $describesRelationships[0] -cne
        "$documentId|DESCRIBES|$rootPackageId") {
    throw 'The SPDX document must have exactly one DOCUMENT DESCRIBES root-package relationship.'
}

# SPDX 2.2 Package.hasFiles is the schema's shorthand for package CONTAINS
# file relationships. Require exact coverage in each representation supplied,
# and require at least one representation.
$rootHasFilesProperty = Find-JsonProperty -Object $rootPackage -Name 'hasFiles'
if ($null -ne $rootHasFilesProperty) {
    $rootHasFiles =
        [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($fileIdValue in @($rootHasFilesProperty.Value)) {
        $fileId = [string]$fileIdValue
        if (-not $fileIds.Contains($fileId) -or
            -not $rootHasFiles.Add($fileId)) {
            throw "The root package hasFiles list contains unknown or duplicate file '$fileId'."
        }
    }
    if ($rootHasFiles.Count -ne $fileIds.Count) {
        throw 'The root package hasFiles list does not contain every inventoried file.'
    }
}
if ($containmentRelationshipCount -gt 0 -and
    $containedFileIds.Count -ne $fileIds.Count) {
    throw 'The root package containment relationships do not cover every inventoried file.'
}
if ($null -eq $rootHasFilesProperty -and
    $containmentRelationshipCount -eq 0) {
    throw 'The root package does not contain the inventoried files.'
}

$expectedDependencyRelationships =
    [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($lockedPackage in $expectedNuGetPackages.Values) {
    $sourceId =
        [string]$dependencyPackagesByName[$lockedPackage.Name].SpdxId
    if ($lockedPackage.Type -ceq 'Direct') {
        [void](Add-RelationshipKey `
            -Relationships $expectedDependencyRelationships `
            -Source $rootPackageId `
            -Type 'DEPENDS_ON' `
            -Target $sourceId `
            -DuplicateMessage 'The NuGet lock implies a duplicate dependency relationship.')
        if ($expectedDependencyRelationships.Count -gt $maximumRelationships) {
            throw 'The NuGet dependency closure exceeds the SPDX relationship limit.'
        }
    }

    # Microsoft.Sbom.DotNetTool emits the transitive closure for each NuGet
    # package, while retaining only direct references from the root package.
    # Reconstruct that exact closure so legitimate flattened relationships are
    # accepted without permitting arbitrary or unlocked dependency edges.
    $reachableDependencies =
        [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase)
    $dependencyQueue = [Collections.Generic.Queue[string]]::new()
    foreach ($dependencyName in $lockedPackage.Dependencies.Keys) {
        $dependencyQueue.Enqueue($dependencyName)
    }
    while ($dependencyQueue.Count -gt 0) {
        $dependencyName = $dependencyQueue.Dequeue()
        if ($dependencyName -ceq $lockedPackage.Name) {
            throw "The NuGet lock target contains a dependency cycle involving '$($lockedPackage.Name)'."
        }
        if (-not $reachableDependencies.Add($dependencyName)) {
            continue
        }
        foreach ($transitiveDependencyName in
            $expectedNuGetPackages[$dependencyName].Dependencies.Keys) {
            $dependencyQueue.Enqueue($transitiveDependencyName)
        }
    }

    foreach ($dependencyName in $reachableDependencies) {
        $dependencyTargetId =
            [string]$dependencyPackagesByName[$dependencyName].SpdxId
        [void](Add-RelationshipKey `
            -Relationships $expectedDependencyRelationships `
            -Source $sourceId `
            -Type 'DEPENDS_ON' `
            -Target $dependencyTargetId `
            -DuplicateMessage 'The NuGet lock implies a duplicate dependency relationship.')
        if ($expectedDependencyRelationships.Count -gt $maximumRelationships) {
            throw 'The NuGet dependency closure exceeds the SPDX relationship limit.'
        }
    }
}

if ($actualDependencyRelationships.Count -ne
    $expectedDependencyRelationships.Count) {
    throw 'The SPDX DEPENDS_ON relationship count does not match the NuGet lock graph.'
}
foreach ($expectedRelationship in $expectedDependencyRelationships) {
    if (-not $actualDependencyRelationships.Contains($expectedRelationship)) {
        throw "The SPDX document is missing locked dependency relationship '$expectedRelationship'."
    }
}

Write-Output (
    "Validated SPDX namespace '$documentNamespace' against " +
    "$($expectedFiles.Count) MSI payload files and " +
    "$($expectedNuGetPackages.Count) locked NuGet packages.")
