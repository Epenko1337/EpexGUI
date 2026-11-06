#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [AllowEmptyString()]
    [string] $ProtectedBranchRef = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryPath = [IO.Path]::GetFullPath($RepositoryRoot)
$configurationPath = Join-Path $repositoryPath 'version.json'
$configurationFile = Get-Item -LiteralPath $configurationPath -Force
if ($configurationFile.PSIsContainer -or
    ($configurationFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Build version configuration '$configurationPath' must be an ordinary file."
}
if ($configurationFile.Length -le 0 -or $configurationFile.Length -gt 4KB) {
    throw "Build version configuration '$configurationPath' is empty or too large."
}

$configuration = Get-Content `
    -LiteralPath $configurationFile.FullName `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json
$expectedProperties = @(
    'buildNumberStart',
    'major',
    'minor',
    'schema'
)
$actualProperties = @(
    $configuration.PSObject.Properties.Name | Sort-Object
)
if ([string]::Join("`n", $actualProperties) -cne
    [string]::Join("`n", $expectedProperties)) {
    throw 'Build version configuration has an unexpected schema.'
}

foreach ($propertyName in $expectedProperties) {
    $propertyValue = $configuration.$propertyName
    if ($propertyValue -isnot [long] -and $propertyValue -isnot [int]) {
        throw "Build version property '$propertyName' must be an integer."
    }
}
if ([long]$configuration.schema -ne 1) {
    throw "Unsupported build version schema '$($configuration.schema)'."
}
if ([long]$configuration.major -lt 0 -or
    [long]$configuration.major -gt 255 -or
    [long]$configuration.minor -lt 0 -or
    [long]$configuration.minor -gt 255 -or
    [long]$configuration.buildNumberStart -lt 0 -or
    [long]$configuration.buildNumberStart -gt 65535) {
    throw 'Build version configuration exceeds Windows Installer version limits.'
}

$gitDirectory = Join-Path $repositoryPath '.git'
if (-not (Test-Path -LiteralPath $gitDirectory)) {
    throw "Repository root '$repositoryPath' has no Git metadata."
}

function Resolve-GitCommit {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Reference,

        [Parameter()]
        [switch] $AllowMissing
    )

    $commitOutput = @(& git `
            -C $repositoryPath `
            rev-parse `
            --verify `
            "$Reference`^{commit}" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        if ($AllowMissing) {
            return $null
        }
        throw "Unable to resolve Git reference '$Reference': $($commitOutput -join ' ')"
    }

    $commit = [string]::Join('', $commitOutput).Trim()
    if ($commit -cnotmatch '\A[0-9a-f]{40,64}\z') {
        throw "Git reference '$Reference' resolved to invalid commit '$commit'."
    }
    return $commit
}

function Test-VersionConfigurationAtCommit {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Commit
    )

    & git `
        -C $repositoryPath `
        cat-file `
        -e `
        "${Commit}:version.json" 2>$null
    return $LASTEXITCODE -eq 0
}

$headCommit = Resolve-GitCommit -Reference 'HEAD'
if (-not (Test-VersionConfigurationAtCommit -Commit $headCommit)) {
    throw 'The current commit does not contain version.json.'
}

if ([string]::IsNullOrWhiteSpace($ProtectedBranchRef)) {
    $branchOutput = @(& git `
            -C $repositoryPath `
            symbolic-ref `
            --quiet `
            --short `
            HEAD 2>&1)
    $currentBranch = if ($LASTEXITCODE -eq 0) {
        [string]::Join('', $branchOutput).Trim()
    }
    else {
        ''
    }

    if ($currentBranch -ceq 'main') {
        $ProtectedBranchRef = 'HEAD'
    }
    elseif ($null -ne (Resolve-GitCommit `
            -Reference 'refs/remotes/origin/main' `
            -AllowMissing)) {
        $ProtectedBranchRef = 'refs/remotes/origin/main'
    }
    elseif ($null -ne (Resolve-GitCommit `
            -Reference 'refs/heads/main' `
            -AllowMissing)) {
        $ProtectedBranchRef = 'refs/heads/main'
    }
    else {
        throw (
            'Unable to locate the protected main branch. Fetch origin/main ' +
            'or pass -ProtectedBranchRef explicitly.')
    }
}

$protectedCommit = Resolve-GitCommit -Reference $ProtectedBranchRef
$candidateIncrement = 0
if ($headCommit -cne $protectedCommit) {
    $mergeBaseOutput = @(& git `
            -C $repositoryPath `
            merge-base `
            $protectedCommit `
            $headCommit 2>&1)
    $mergeBase = [string]::Join('', $mergeBaseOutput).Trim()
    if ($LASTEXITCODE -ne 0 -or $mergeBase -cne $protectedCommit) {
        throw (
            "Current commit '$headCommit' is not based on protected tip " +
            "'$protectedCommit'. Update the branch before resolving its " +
            'candidate version.')
    }
    $candidateIncrement = 1
}

$protectedHasConfiguration =
    Test-VersionConfigurationAtCommit -Commit $protectedCommit
if ($candidateIncrement -eq 1) {
    $configurationDiff = @(& git `
            -C $repositoryPath `
            diff `
            --name-only `
            $protectedCommit `
            $headCommit `
            -- `
            version.json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to compare candidate version configuration: $($configurationDiff -join ' ')"
    }
    $candidateStartsNewEpoch = @(
        $configurationDiff |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ -ceq 'version.json' }
    ).Count -eq 1
}
else {
    $candidateStartsNewEpoch = $false
}

if ($candidateStartsNewEpoch) {
    # The PR that changes the version configuration is the first build in the
    # new epoch. Its configured buildNumberStart is therefore used unchanged.
    $buildsAfterEpoch = 0
}
elseif (-not $protectedHasConfiguration) {
    if ($candidateIncrement -ne 1) {
        throw 'The protected commit does not contain version.json.'
    }
    $buildsAfterEpoch = 0
}
else {
    $epochOutput = @(& git `
            -C $repositoryPath `
            rev-list `
            --first-parent `
            $protectedCommit `
            -- `
            version.json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect first-parent version history: $($epochOutput -join ' ')"
    }
    $epochCommits = @(
        $epochOutput |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrEmpty($_) }
    )
    if ($epochCommits.Count -lt 1 -or
        $epochCommits[0] -cnotmatch '\A[0-9a-f]{40,64}\z') {
        throw 'Git did not identify the current first-parent build version epoch.'
    }

    $historyOutput = @(& git `
            -C $repositoryPath `
            rev-list `
            --count `
            --first-parent `
            "$($epochCommits[0])..$protectedCommit" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to count builds after the version epoch: $($historyOutput -join ' ')"
    }
    $historyText = [string]::Join('', $historyOutput).Trim()
    [long] $protectedBuildsAfterEpoch = 0
    if ($historyText -cnotmatch '\A[0-9]+\z' -or
        -not [long]::TryParse(
            $historyText,
            [ref]$protectedBuildsAfterEpoch)) {
        throw "Git returned an invalid post-epoch history count '$historyText'."
    }
    $buildsAfterEpoch =
        $protectedBuildsAfterEpoch + $candidateIncrement
}
$buildNumber =
    [long]$configuration.buildNumberStart + $buildsAfterEpoch
if ($buildNumber -gt 65535) {
    throw "Build number $buildNumber exceeds the Windows Installer patch limit."
}

Write-Output (
    "{0}.{1}.{2}" -f
    [long]$configuration.major,
    [long]$configuration.minor,
    $buildNumber)
