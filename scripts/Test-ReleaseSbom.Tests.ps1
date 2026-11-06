[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$validatorPath = Join-Path $PSScriptRoot 'Test-ReleaseSbom.ps1'
$temporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()) (
    'WireSockUI-SbomTests-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporaryRoot)

$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
$testCount = 0

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object] $Value)

    return $Value |
        ConvertTo-Json -Depth 32 |
        ConvertFrom-Json
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [object] $Value
    )

    $path = Join-Path $temporaryRoot $Name
    $json = $Value | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($path, $json, $utf8WithoutBom)
    return $path
}

function Invoke-Fixture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [object] $Sbom,

        [Parameter(Mandatory = $true)]
        [object] $LockFile
    )

    $metadataPath = Write-JsonFixture `
        -Name "$Name.metadata.json" `
        -Value $script:baseMetadata
    $lockPath = Write-JsonFixture `
        -Name "$Name.packages.lock.json" `
        -Value $LockFile
    $sbomPath = Write-JsonFixture `
        -Name "$Name.spdx.json" `
        -Value $Sbom

    try {
        & $validatorPath `
            -SbomPath $sbomPath `
            -ValidationMetadataPath $metadataPath `
            -NuGetLockFilePath $lockPath `
            -NuGetTargetFramework 'net472' `
            -ExpectedPackageName 'WireSockUI-test' `
            -ExpectedVersion '1.2.3' |
            Out-Null
        return [pscustomobject]@{
            Succeeded = $true
            Message = ''
        }
    }
    catch {
        return [pscustomobject]@{
            Succeeded = $false
            Message = [string]$_.Exception.Message
        }
    }
}

function Assert-Accepted {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [object] $Sbom,

        [Parameter(Mandatory = $true)]
        [object] $LockFile
    )

    $result = Invoke-Fixture -Name $Name -Sbom $Sbom -LockFile $LockFile
    if (-not $result.Succeeded) {
        throw "Test '$Name' unexpectedly failed: $($result.Message)"
    }
    $script:testCount++
    Write-Output "PASS $Name"
}

function Assert-Rejected {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [object] $Sbom,

        [Parameter(Mandatory = $true)]
        [object] $LockFile,

        [Parameter(Mandatory = $true)]
        [string] $MessageFragment
    )

    $result = Invoke-Fixture -Name $Name -Sbom $Sbom -LockFile $LockFile
    if ($result.Succeeded) {
        throw "Test '$Name' unexpectedly passed."
    }
    if (-not $result.Message.Contains(
            $MessageFragment,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw (
            "Test '$Name' failed for the wrong reason. Expected " +
            "'$MessageFragment', received '$($result.Message)'.")
    }
    $script:testCount++
    Write-Output "PASS $Name"
}

$script:baseMetadata = [ordered]@{
    Schema = 'WireSockUI-Msi-Validation-v1'
    ProductVersion = '1.2.3'
    Files = @(
        [ordered]@{
            Path = 'WireSockUI.exe'
            Size = 10
            Sha256 = ('a' * 64)
        },
        [ordered]@{
            Path = 'Assets/config.json'
            Size = 20
            Sha256 = ('b' * 64)
        }
    )
}

$baseLock = [ordered]@{
    version = 1
    dependencies = [ordered]@{
        net472 = [ordered]@{
            'Direct.Package' = [ordered]@{
                type = 'Direct'
                requested = '[1.0.0, )'
                resolved = '1.0.0'
                contentHash = ('A' * 86) + '=='
                dependencies = [ordered]@{
                    'Transitive.Package' = '2.0.0'
                }
            }
            'Transitive.Package' = [ordered]@{
                type = 'Transitive'
                resolved = '2.0.0'
                contentHash = ('B' * 86) + '=='
            }
        }
    }
}

$baseSbom = [ordered]@{
    spdxVersion = 'SPDX-2.2'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = 'WireSockUI-test 1.2.3'
    documentNamespace = 'https://example.test/sbom/1'
    documentDescribes = @('SPDXRef-RootPackage')
    packages = @(
        [ordered]@{
            SPDXID = 'SPDXRef-RootPackage'
            name = 'WireSockUI-test'
            versionInfo = '1.2.3'
            hasFiles = @(
                'SPDXRef-File-Application',
                'SPDXRef-File-Configuration'
            )
        },
        [ordered]@{
            SPDXID = 'SPDXRef-Package-Direct'
            name = 'Direct.Package'
            versionInfo = '1.0.0'
        },
        [ordered]@{
            SPDXID = 'SPDXRef-Package-Transitive'
            name = 'Transitive.Package'
            versionInfo = '2.0.0'
        }
    )
    files = @(
        [ordered]@{
            SPDXID = 'SPDXRef-File-Application'
            fileName = 'WireSockUI.exe'
            checksums = @(
                [ordered]@{
                    algorithm = 'SHA256'
                    checksumValue = ('a' * 64)
                }
            )
        },
        [ordered]@{
            SPDXID = 'SPDXRef-File-Configuration'
            fileName = 'Assets/config.json'
            checksums = @(
                [ordered]@{
                    algorithm = 'SHA256'
                    checksumValue = ('b' * 64)
                }
            )
        }
    )
    relationships = @(
        [ordered]@{
            spdxElementId = 'SPDXRef-DOCUMENT'
            relationshipType = 'DESCRIBES'
            relatedSpdxElement = 'SPDXRef-RootPackage'
        },
        [ordered]@{
            spdxElementId = 'SPDXRef-RootPackage'
            relationshipType = 'CONTAINS'
            relatedSpdxElement = 'SPDXRef-File-Application'
        },
        [ordered]@{
            spdxElementId = 'SPDXRef-RootPackage'
            relationshipType = 'CONTAINS'
            relatedSpdxElement = 'SPDXRef-File-Configuration'
        },
        [ordered]@{
            spdxElementId = 'SPDXRef-RootPackage'
            relationshipType = 'DEPENDS_ON'
            relatedSpdxElement = 'SPDXRef-Package-Direct'
        },
        [ordered]@{
            spdxElementId = 'SPDXRef-Package-Direct'
            relationshipType = 'DEPENDS_ON'
            relatedSpdxElement = 'SPDXRef-Package-Transitive'
        }
    )
}

try {
    Assert-Accepted `
        -Name 'valid-both-containment-representations' `
        -Sbom (Copy-JsonObject -Value $baseSbom) `
        -LockFile (Copy-JsonObject -Value $baseLock)

    $transitiveClosureLock = Copy-JsonObject -Value $baseLock
    $transitiveClosureLock.dependencies.net472.'Transitive.Package' |
        Add-Member `
            -NotePropertyName dependencies `
            -NotePropertyValue ([pscustomobject][ordered]@{
                'Leaf.Package' = '3.0.0'
            })
    $transitiveClosureLock.dependencies.net472 |
        Add-Member `
            -NotePropertyName 'Leaf.Package' `
            -NotePropertyValue ([pscustomobject][ordered]@{
                type = 'Transitive'
                resolved = '3.0.0'
                contentHash = ('C' * 86) + '=='
            })
    $transitiveClosureSbom = Copy-JsonObject -Value $baseSbom
    $transitiveClosureSbom.packages += [pscustomobject][ordered]@{
        SPDXID = 'SPDXRef-Package-Leaf'
        name = 'Leaf.Package'
        versionInfo = '3.0.0'
    }
    $transitiveClosureSbom.relationships += @(
        [pscustomobject][ordered]@{
            spdxElementId = 'SPDXRef-Package-Direct'
            relationshipType = 'DEPENDS_ON'
            relatedSpdxElement = 'SPDXRef-Package-Leaf'
        },
        [pscustomobject][ordered]@{
            spdxElementId = 'SPDXRef-Package-Transitive'
            relationshipType = 'DEPENDS_ON'
            relatedSpdxElement = 'SPDXRef-Package-Leaf'
        }
    )
    Assert-Accepted `
        -Name 'valid-transitive-closure' `
        -Sbom $transitiveClosureSbom `
        -LockFile $transitiveClosureLock

    $missingTransitiveClosureEdge =
        Copy-JsonObject -Value $transitiveClosureSbom
    $missingTransitiveClosureEdge.relationships = @(
        $missingTransitiveClosureEdge.relationships |
            Where-Object {
                -not (
                    [string]$_.spdxElementId -ceq
                        'SPDXRef-Package-Direct' -and
                    [string]$_.relatedSpdxElement -ceq
                        'SPDXRef-Package-Leaf')
            }
    )
    Assert-Rejected `
        -Name 'missing-transitive-closure-edge' `
        -Sbom $missingTransitiveClosureEdge `
        -LockFile $transitiveClosureLock `
        -MessageFragment 'relationship count'

    $packageNameOnlyDocument = Copy-JsonObject -Value $baseSbom
    $packageNameOnlyDocument.name = 'WireSockUI-test'
    Assert-Rejected `
        -Name 'document-name-missing-version' `
        -Sbom $packageNameOnlyDocument `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'expected SPDX 2.2'

    $hasFilesOnly = Copy-JsonObject -Value $baseSbom
    $hasFilesOnly.relationships = @(
        $hasFilesOnly.relationships |
            Where-Object { [string]$_.relationshipType -cne 'CONTAINS' }
    )
    Assert-Accepted `
        -Name 'valid-hasFiles-containment' `
        -Sbom $hasFilesOnly `
        -LockFile (Copy-JsonObject -Value $baseLock)

    $relationshipsOnly = Copy-JsonObject -Value $baseSbom
    $relationshipsOnly.packages[0].PSObject.Properties.Remove('hasFiles')
    Assert-Accepted `
        -Name 'valid-relationship-containment' `
        -Sbom $relationshipsOnly `
        -LockFile (Copy-JsonObject -Value $baseLock)

    $duplicateId = Copy-JsonObject -Value $baseSbom
    $duplicateId.files[1].SPDXID = $duplicateId.files[0].SPDXID
    Assert-Rejected `
        -Name 'duplicate-spdx-id' `
        -Sbom $duplicateId `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'not unique'

    $wrongDocumentRoot = Copy-JsonObject -Value $baseSbom
    $wrongDocumentRoot.documentDescribes =
        @('SPDXRef-Package-Direct')
    Assert-Rejected `
        -Name 'wrong-document-root' `
        -Sbom $wrongDocumentRoot `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'describe exactly'

    $missingContainment = Copy-JsonObject -Value $baseSbom
    $missingContainment.relationships = @(
        $missingContainment.relationships |
            Where-Object {
                [string]$_.relatedSpdxElement -cne
                    'SPDXRef-File-Configuration'
            }
    )
    Assert-Rejected `
        -Name 'missing-file-containment' `
        -Sbom $missingContainment `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'do not cover every'

    $incompleteHasFiles = Copy-JsonObject -Value $baseSbom
    $incompleteHasFiles.packages[0].hasFiles =
        @('SPDXRef-File-Application')
    Assert-Rejected `
        -Name 'incomplete-hasFiles' `
        -Sbom $incompleteHasFiles `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'does not contain every'

    $wrongDependencyVersion = Copy-JsonObject -Value $baseSbom
    $wrongDependencyVersion.packages[2].versionInfo = '2.0.1'
    Assert-Rejected `
        -Name 'wrong-dependency-version' `
        -Sbom $wrongDependencyVersion `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'wrong version'

    $missingDependencyEdge = Copy-JsonObject -Value $baseSbom
    $missingDependencyEdge.relationships = @(
        $missingDependencyEdge.relationships |
            Where-Object {
                -not (
                    [string]$_.spdxElementId -ceq
                        'SPDXRef-Package-Direct' -and
                    [string]$_.relationshipType -ceq 'DEPENDS_ON')
            }
    )
    Assert-Rejected `
        -Name 'missing-dependency-edge' `
        -Sbom $missingDependencyEdge `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'relationship count'

    $extraDependencyEdge = Copy-JsonObject -Value $baseSbom
    $extraDependencyEdge.relationships += [pscustomobject][ordered]@{
        spdxElementId = 'SPDXRef-Package-Transitive'
        relationshipType = 'DEPENDS_ON'
        relatedSpdxElement = 'SPDXRef-Package-Direct'
    }
    Assert-Rejected `
        -Name 'extra-dependency-edge' `
        -Sbom $extraDependencyEdge `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'relationship count'

    $danglingRelationship = Copy-JsonObject -Value $baseSbom
    $danglingRelationship.relationships[0].relatedSpdxElement =
        'SPDXRef-Missing'
    Assert-Rejected `
        -Name 'dangling-relationship' `
        -Sbom $danglingRelationship `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment 'unknown local element'

    $unlockedDependency = Copy-JsonObject -Value $baseLock
    $unlockedDependency.dependencies.net472.'Direct.Package'.
        dependencies.'Transitive.Package' = '2.0.1'
    Assert-Rejected `
        -Name 'lock-dependency-version-drift' `
        -Sbom (Copy-JsonObject -Value $baseSbom) `
        -LockFile $unlockedDependency `
        -MessageFragment 'unlocked dependency'

    $cyclicLock = Copy-JsonObject -Value $baseLock
    $cyclicLock.dependencies.net472.'Transitive.Package' |
        Add-Member `
            -NotePropertyName dependencies `
            -NotePropertyValue ([pscustomobject][ordered]@{
                'Direct.Package' = '1.0.0'
            })
    Assert-Rejected `
        -Name 'lock-dependency-cycle' `
        -Sbom (Copy-JsonObject -Value $baseSbom) `
        -LockFile $cyclicLock `
        -MessageFragment 'dependency cycle'

    $orphanedLock = Copy-JsonObject -Value $baseLock
    $orphanedLock.dependencies.net472 |
        Add-Member `
            -NotePropertyName 'Orphaned.Package' `
            -NotePropertyValue ([pscustomobject][ordered]@{
                type = 'Transitive'
                resolved = '3.0.0'
                contentHash = ('C' * 86) + '=='
            })
    Assert-Rejected `
        -Name 'orphaned-lock-entry' `
        -Sbom (Copy-JsonObject -Value $baseSbom) `
        -LockFile $orphanedLock `
        -MessageFragment 'unreachable'

    $tooManyRelationships = Copy-JsonObject -Value $baseSbom
    $relationshipTemplate = [pscustomobject][ordered]@{
        spdxElementId = 'SPDXRef-DOCUMENT'
        relationshipType = 'DESCRIBES'
        relatedSpdxElement = 'SPDXRef-RootPackage'
    }
    $tooManyRelationships.relationships = @(
        1..16385 | ForEach-Object {
            $relationshipTemplate
        }
    )
    Assert-Rejected `
        -Name 'relationship-limit' `
        -Sbom $tooManyRelationships `
        -LockFile (Copy-JsonObject -Value $baseLock) `
        -MessageFragment '16384'

    Write-Output "Validated $testCount release-SBOM validator fixtures."
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
