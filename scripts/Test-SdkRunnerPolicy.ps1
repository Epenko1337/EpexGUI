[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z')]
    [string] $Repository,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $GitHubApiUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[0-9a-f]{40}\z')]
    [string] $WorkflowSha,

    [Parameter()]
    [ValidatePattern('\A[A-Za-z0-9_.-]{1,100}\z')]
    [string] $RunnerGroupName = 'wiresock-sdk'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$minimumRunnerVersion = [Version]'2.329.0'
$maximumPages = 10

if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    throw 'GH_TOKEN is required to inspect organization SDK runner policy.'
}
if ($Repository -cne 'wiresock/WireSockUI') {
    throw "SDK runner policy may be checked only for canonical repository 'wiresock/WireSockUI', not '$Repository'."
}

$apiUri = $null
if (-not [Uri]::TryCreate($GitHubApiUrl, [UriKind]::Absolute, [ref]$apiUri) -or
    $apiUri.Scheme -cne 'https' -or
    $apiUri.DnsSafeHost -cne 'api.github.com' -or
    -not $apiUri.IsDefaultPort -or
    -not [string]::IsNullOrEmpty($apiUri.UserInfo) -or
    -not [string]::IsNullOrEmpty($apiUri.Query) -or
    -not [string]::IsNullOrEmpty($apiUri.Fragment) -or
    $apiUri.AbsolutePath.Trim('/') -ne '') {
    throw 'GitHubApiUrl must be the exact public GitHub HTTPS API origin.'
}
$apiRoot = $GitHubApiUrl.TrimEnd('/')
$headers = @{
    Accept = 'application/vnd.github+json'
    Authorization = "Bearer $env:GH_TOKEN"
    'X-GitHub-Api-Version' = '2026-03-10'
}
$repositoryOwner, $repositoryName = $Repository.Split('/', 2)
if ($repositoryOwner -cne 'wiresock' -or $repositoryName -cne 'WireSockUI') {
    throw 'The canonical SDK runner repository identity changed unexpectedly.'
}

function Invoke-GitHubRunnerPolicyRequest {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if (-not $Path.StartsWith('/') -or
        $Path.Contains('://') -or
        $Path.IndexOfAny([char[]]"`r`n") -ge 0) {
        throw "Unsafe GitHub runner-policy API path '$Path'."
    }
    try {
        return Invoke-RestMethod `
            -Method Get `
            -Headers $headers `
            -TimeoutSec 30 `
            -Uri "$apiRoot$Path"
    }
    catch {
        throw "Unable to verify SDK runner policy at '$Path': $($_.Exception.Message)"
    }
}

function Get-PagedResponseItems {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $CollectionProperty
    )

    $items = [Collections.Generic.List[object]]::new()
    $reportedTotal = $null
    foreach ($page in 1..$maximumPages) {
        $separator = if ($Path.Contains('?')) { '&' } else { '?' }
        $response = Invoke-GitHubRunnerPolicyRequest `
            -Path "$Path${separator}per_page=100&page=$page"
        $property = $response.PSObject.Properties[$CollectionProperty]
        if ($null -eq $property) {
            throw "GitHub response for '$Path' is missing '$CollectionProperty'."
        }
        [Int64]$pageTotal = $response.total_count
        if ($pageTotal -lt 0 -or
            ($null -ne $reportedTotal -and $reportedTotal -ne $pageTotal)) {
            throw "GitHub response for '$Path' has an invalid or unstable total count."
        }
        $reportedTotal = $pageTotal
        $pageItems = @($property.Value)
        foreach ($item in $pageItems) {
            $items.Add($item)
        }
        if ($pageItems.Count -lt 100) {
            if ($items.Count -ne $reportedTotal) {
                throw "GitHub response for '$Path' returned $($items.Count) items but reported $reportedTotal."
            }
            return @($items)
        }
    }
    throw "GitHub response for '$Path' exceeds the bounded $($maximumPages * 100)-item scan."
}

$repositoryMetadata =
    Invoke-GitHubRunnerPolicyRequest -Path "/repos/$Repository"
if ([string]$repositoryMetadata.full_name -cne $Repository -or
    [string]$repositoryMetadata.owner.login -cne $repositoryOwner -or
    [string]$repositoryMetadata.owner.type -cne 'Organization' -or
    [Int64]$repositoryMetadata.id -le 0) {
    throw "GitHub returned an invalid canonical repository identity for '$Repository'."
}

$runnerGroups = @(
    Get-PagedResponseItems `
        -Path "/orgs/$repositoryOwner/actions/runner-groups" `
        -CollectionProperty 'runner_groups'
)
$matchingGroups = @(
    $runnerGroups |
        Where-Object { [string]$_.name -ceq $RunnerGroupName }
)
if ($matchingGroups.Count -ne 1) {
    throw "Organization must contain exactly one runner group named '$RunnerGroupName'."
}
[Int64]$runnerGroupId = $matchingGroups[0].id
if ($runnerGroupId -le 0) {
    throw "Runner group '$RunnerGroupName' has an invalid identifier."
}
$runnerGroup =
    Invoke-GitHubRunnerPolicyRequest `
        -Path "/orgs/$repositoryOwner/actions/runner-groups/$runnerGroupId"
$expectedWorkflow = (
    "$Repository/.github/workflows/sdk-integration.yml@$WorkflowSha")
if ([Int64]$runnerGroup.id -ne $runnerGroupId -or
    [string]$runnerGroup.name -cne $RunnerGroupName -or
    [string]$runnerGroup.visibility -cne 'selected' -or
    $runnerGroup.default -ne $false -or
    $runnerGroup.inherited -ne $false -or
    $runnerGroup.restricted_to_workflows -ne $true -or
    $runnerGroup.workflow_restrictions_read_only -ne $false -or
    @($runnerGroup.selected_workflows).Count -ne 1 -or
    [string]@($runnerGroup.selected_workflows)[0] -cne $expectedWorkflow) {
    throw (
        "Runner group '$RunnerGroupName' must be organization-owned, non-default, " +
        "selected-repository-only, and restricted to exact workflow '$expectedWorkflow'.")
}
if ($repositoryMetadata.private -eq $false) {
    if ($runnerGroup.allows_public_repositories -ne $true) {
        throw "Public repository '$Repository' cannot use runner group '$RunnerGroupName' while public repositories are disabled."
    }
}
elseif ($runnerGroup.allows_public_repositories -ne $false) {
    throw "Private repository '$Repository' must not enable public-repository access on runner group '$RunnerGroupName'."
}

$selectedRepositories = @(
    Get-PagedResponseItems `
        -Path "/orgs/$repositoryOwner/actions/runner-groups/$runnerGroupId/repositories" `
        -CollectionProperty 'repositories'
)
if ($selectedRepositories.Count -ne 1 -or
    [Int64]$selectedRepositories[0].id -ne [Int64]$repositoryMetadata.id -or
    [string]$selectedRepositories[0].full_name -cne $Repository) {
    throw "Runner group '$RunnerGroupName' must grant access only to '$Repository'."
}

$runners = @(
    Get-PagedResponseItems `
        -Path "/orgs/$repositoryOwner/actions/runner-groups/$runnerGroupId/runners" `
        -CollectionProperty 'runners'
)
if ($runners.Count -eq 0) {
    Write-Warning (
        "Runner group '$RunnerGroupName' currently has no registered runners. " +
        'This is acceptable for just-in-time pools; external provisioning must guarantee disposable instances.')
    Write-Output "Validated exact SDK runner-group access policy for '$expectedWorkflow'; no runners are currently registered."
    return
}

$seenRunnerIds = [Collections.Generic.HashSet[Int64]]::new()
$seenRunnerNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$seenPools = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$requiredPools = [ordered]@{
    'wiresock-sdk-x86' = 'X64'
    'wiresock-sdk-x64' = 'X64'
    'wiresock-sdk-arm64' = 'ARM64'
}
$warnedMissingEphemeralField = $false
foreach ($runner in $runners) {
    [Int64]$runnerId = $runner.id
    $runnerName = [string]$runner.name
    if ($runnerId -le 0 -or
        -not $seenRunnerIds.Add($runnerId) -or
        [string]::IsNullOrWhiteSpace($runnerName) -or
        $runnerName.Length -gt 255 -or
        -not $seenRunnerNames.Add($runnerName) -or
        [string]$runner.os -ine 'windows' -or
        [string]$runner.status -inotmatch '^(online|offline)$') {
        throw "Runner group '$RunnerGroupName' contains an invalid or duplicate runner identity."
    }

    $runnerVersion = $null
    if (-not [Version]::TryParse([string]$runner.version, [ref]$runnerVersion) -or
        $runnerVersion -lt $minimumRunnerVersion) {
        throw "SDK runner '$runnerName' must use Actions Runner $minimumRunnerVersion or newer."
    }

    $ephemeralProperty = $runner.PSObject.Properties['ephemeral']
    if ($null -ne $ephemeralProperty) {
        if ($ephemeralProperty.Value -ne $true) {
            throw "SDK runner '$runnerName' must be registered as ephemeral."
        }
    }
    elseif (-not $warnedMissingEphemeralField) {
        Write-Warning (
            'GitHub did not expose runner ephemerality. External just-in-time provisioning ' +
            'must guarantee one job per disposable host.')
        $warnedMissingEphemeralField = $true
    }

    $labels = @($runner.labels)
    $labelNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($label in $labels) {
        $labelName = [string]$label.name
        if ([string]::IsNullOrWhiteSpace($labelName) -or
            -not $labelNames.Add($labelName)) {
            throw "SDK runner '$runnerName' contains an invalid or duplicate label."
        }
    }
    $routingLabels = @(
        $requiredPools.Keys |
            Where-Object { $labelNames.Contains($_) }
    )
    if ($routingLabels.Count -ne 1) {
        throw "SDK runner '$runnerName' must have exactly one wiresock-sdk-x86, wiresock-sdk-x64, or wiresock-sdk-arm64 routing label."
    }
    $routingLabel = $routingLabels[0]
    $hardwareLabel = [string]$requiredPools[$routingLabel]
    $expectedLabels = @(
        'self-hosted',
        'windows',
        'wiresock-sdk',
        $hardwareLabel,
        $routingLabel
    )
    if ($labelNames.Count -ne $expectedLabels.Count -or
        @($expectedLabels | Where-Object {
                -not $labelNames.Contains($_)
            }).Count -ne 0) {
        throw "SDK runner '$runnerName' must have only the exact common, hardware, and logical routing labels."
    }
    [void]$seenPools.Add($routingLabel)
}

$missingPools = @(
    $requiredPools.Keys |
        Where-Object { -not $seenPools.Contains($_) }
)
if ($missingPools.Count -ne 0) {
    throw "Registered SDK runner inventory is missing logical routing pools: $($missingPools -join ', ')."
}

Write-Output (
    "Validated exact SDK runner-group policy, $($runners.Count) ephemeral runner(s), " +
    "minimum version $minimumRunnerVersion, and x86/x64/ARM64 logical routing coverage.")
