[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptUnderTest =
    Join-Path $PSScriptRoot 'Test-ReleaseRepositoryPolicy.ps1'
$previousToken = $env:GH_TOKEN
$global:ReleasePolicyTestMainRules = @()
$global:ReleasePolicyTestBranchProtection = $null
$global:ReleasePolicyTestRequestCount = 0
$global:ReleasePolicyTestTagRuleOverlap = $false
$global:ReleasePolicyTestOwnerType = 'User'
$global:ReleasePolicyTestEnvironmentHasReviewer = $false

$requiredChecks = @(
    'dependency-audit',
    'msi-architecture-isolation',
    'msi-install-smoke (ARM64)',
    'msi-install-smoke (x64)',
    'msi-install-smoke (x86)',
    'msi-transition-smoke',
    'native-host-smoke (ARM64)',
    'native-host-smoke (x64)',
    'native-host-smoke (x86)',
    'publish (Release UWP, ARM64)',
    'publish (Release UWP, x64)',
    'publish (Release UWP, x86)',
    'publish (Release, ARM64)',
    'publish (Release, x64)',
    'publish (Release, x86)',
    'sdk-contract',
    'test (Release UWP, ARM64)',
    'test (Release UWP, x64)',
    'test (Release UWP, x86)',
    'test (Release, ARM64)',
    'test (Release, x64)',
    'test (Release, x86)'
)

function New-StatusCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Context,

        [Int64] $IntegrationId = 15368
    )

    return [pscustomobject]@{
        context = $Context
        integration_id = $IntegrationId
    }
}

function New-MainRules {
    param(
        [switch] $ConflictingDuplicate,

        [switch] $WithApproval
    )

    $middle = [int][Math]::Floor($requiredChecks.Count / 2)
    $firstChecks = @(
        $requiredChecks[0..($middle - 1)] |
            ForEach-Object { New-StatusCheck -Context $_ }
    )
    $duplicateIntegrationId =
        if ($ConflictingDuplicate) { [Int64]999 } else { [Int64]15368 }
    $secondChecks = @(
        New-StatusCheck `
            -Context $requiredChecks[0] `
            -IntegrationId $duplicateIntegrationId
        $requiredChecks[$middle..($requiredChecks.Count - 1)] |
            ForEach-Object { New-StatusCheck -Context $_ }
    )

    return @(
        [pscustomobject]@{ type = 'deletion' },
        [pscustomobject]@{ type = 'non_fast_forward' },
        [pscustomobject]@{ type = 'required_signatures' },
        [pscustomobject]@{
            type = 'pull_request'
            parameters = [pscustomobject]@{
                dismiss_stale_reviews_on_push = $true
                require_last_push_approval = $false
                required_review_thread_resolution = $true
                required_approving_review_count = 0
            }
        },
        [pscustomobject]@{
            type = 'pull_request'
            parameters = [pscustomobject]@{
                dismiss_stale_reviews_on_push = $false
                require_last_push_approval = [bool]$WithApproval
                required_review_thread_resolution = $false
                required_approving_review_count =
                    if ($WithApproval) { 1 } else { 0 }
            }
        },
        [pscustomobject]@{
            type = 'required_status_checks'
            parameters = [pscustomobject]@{
                strict_required_status_checks_policy = $true
                required_status_checks = $firstChecks
            }
        },
        [pscustomobject]@{
            type = 'required_status_checks'
            parameters = [pscustomobject]@{
                strict_required_status_checks_policy = $false
                required_status_checks = $secondChecks
            }
        }
    )
}

function New-BranchProtection {
    param(
        [switch] $WithBypass,

        [switch] $WithApproval
    )

    $bypassUsers =
        if ($WithBypass) {
            @([pscustomobject]@{ login = 'release-admin' })
        }
        else {
            @()
        }
    return [pscustomobject]@{
        enforce_admins = [pscustomobject]@{ enabled = $true }
        required_pull_request_reviews = [pscustomobject]@{
            dismiss_stale_reviews = $true
            require_last_push_approval = [bool]$WithApproval
            required_approving_review_count =
                if ($WithApproval) { 1 } else { 0 }
            bypass_pull_request_allowances = [pscustomobject]@{
                users = $bypassUsers
                teams = @()
                apps = @()
            }
        }
        required_conversation_resolution =
            [pscustomobject]@{ enabled = $true }
        required_signatures = [pscustomobject]@{ enabled = $true }
    }
}

function New-TagRulesets {
    $creationRules = @([pscustomobject]@{ type = 'creation' })
    if ($global:ReleasePolicyTestTagRuleOverlap) {
        $creationRules += [pscustomobject]@{ type = 'update' }
    }
    return @(
        [pscustomobject]@{
            id = [Int64]100
            name = 'WireSockUI release tag creation'
            target = 'tag'
            source_type = 'Repository'
            source = 'wiresock/WireSockUI'
            enforcement = 'active'
            conditions = [pscustomobject]@{
                ref_name = [pscustomobject]@{
                    include = @('refs/tags/release-v*.*.*')
                    exclude = @()
                }
            }
            rules = $creationRules
        },
        [pscustomobject]@{
            id = [Int64]200
            name = 'WireSockUI immutable release tags'
            target = 'tag'
            source_type = 'Repository'
            source = 'wiresock/WireSockUI'
            enforcement = 'active'
            conditions = [pscustomobject]@{
                ref_name = [pscustomobject]@{
                    include = @('refs/tags/release-v*.*.*')
                    exclude = @()
                }
            }
            rules = @(
                [pscustomobject]@{ type = 'update' },
                [pscustomobject]@{ type = 'deletion' }
            )
        },
        [pscustomobject]@{
            id = [Int64]300
            name = 'WireSockUI retired legacy tags'
            target = 'tag'
            source_type = 'Repository'
            source = 'wiresock/WireSockUI'
            enforcement = 'active'
            conditions = [pscustomobject]@{
                ref_name = [pscustomobject]@{
                    include = @('refs/tags/v*')
                    exclude = @()
                }
            }
            rules = @(
                [pscustomobject]@{ type = 'creation' },
                [pscustomobject]@{ type = 'update' },
                [pscustomobject]@{ type = 'deletion' }
            )
        }
    )
}

function global:Invoke-RestMethod {
    param(
        [string] $Method,
        [hashtable] $Headers,
        [int] $TimeoutSec,
        [string] $Uri
    )

    if ($Method -cne 'Get' -or
        $TimeoutSec -ne 30 -or
        [string]::IsNullOrWhiteSpace([string]$Headers.Authorization)) {
        throw 'The policy script made an unhardened GitHub API request.'
    }
    $global:ReleasePolicyTestRequestCount++

    switch -CaseSensitive ($Uri) {
        'https://api.github.com/repos/wiresock/WireSockUI' {
            return [pscustomobject]@{
                full_name = 'wiresock/WireSockUI'
                owner = [pscustomobject]@{
                    login = 'wiresock'
                    type = $global:ReleasePolicyTestOwnerType
                }
                default_branch = 'main'
            }
        }
        'https://api.github.com/repos/wiresock/WireSockUI/immutable-releases' {
            return [pscustomobject]@{ enabled = $true }
        }
        'https://api.github.com/repos/wiresock/WireSockUI/actions/permissions' {
            return [pscustomobject]@{
                enabled = $true
                allowed_actions = 'selected'
                sha_pinning_required = $true
            }
        }
        'https://api.github.com/repos/wiresock/WireSockUI/actions/permissions/selected-actions' {
            return [pscustomobject]@{
                github_owned_allowed = $false
                verified_allowed = $false
                patterns_allowed = @(
                    'actions/attest@*',
                    'actions/checkout@*',
                    'actions/create-github-app-token@*',
                    'actions/download-artifact@*',
                    'actions/setup-dotnet@*',
                    'actions/upload-artifact@*'
                )
            }
        }
        'https://api.github.com/repos/wiresock/WireSockUI/actions/oidc/customization/sub' {
            return [pscustomobject]@{
                use_default = $false
                include_claim_keys = @(
                    'repo',
                    'context',
                    'job_workflow_ref'
                )
            }
        }
        'https://api.github.com/repos/wiresock/WireSockUI/branches/main/protection' {
            return $global:ReleasePolicyTestBranchProtection
        }
        'https://api.github.com/repos/wiresock/WireSockUI/rules/branches/main?per_page=100&page=1' {
            Write-Output `
                -NoEnumerate `
                -InputObject $global:ReleasePolicyTestMainRules
            return
        }
        'https://api.github.com/repos/wiresock/WireSockUI/rulesets?per_page=100&page=1&includes_parents=true&targets=tag' {
            $summaries = @(
                New-TagRulesets |
                    Select-Object id, name, target, source_type, source, enforcement
            )
            Write-Output -NoEnumerate -InputObject $summaries
            return
        }
        { $_ -cmatch '^https://api\.github\.com/repos/wiresock/WireSockUI/rulesets/(100|200|300)$' } {
            $rulesetId = [Int64]($Uri -replace '^.*/', '')
            return @(
                New-TagRulesets |
                    Where-Object { [Int64]$_.id -eq $rulesetId }
            )[0]
        }
        'https://api.github.com/repos/wiresock/WireSockUI/environments/release-publish' {
            $protectionRules = @(
                [pscustomobject]@{ type = 'branch_policy' }
            )
            if ($global:ReleasePolicyTestEnvironmentHasReviewer) {
                $protectionRules += [pscustomobject]@{
                    type = 'required_reviewers'
                    prevent_self_review = $true
                    reviewers = @(
                        [pscustomobject]@{
                            type = 'User'
                            reviewer = [pscustomobject]@{
                                login = 'wiresock'
                                slug = ''
                            }
                        }
                    )
                }
            }
            return [pscustomobject]@{
                name = 'release-publish'
                can_admins_bypass = $true
                protection_rules = $protectionRules
                deployment_branch_policy = [pscustomobject]@{
                    protected_branches = $false
                    custom_branch_policies = $true
                }
            }
        }
        'https://api.github.com/repos/wiresock/WireSockUI/environments/release-publish/deployment-branch-policies?per_page=100' {
            return [pscustomobject]@{
                total_count = 1
                branch_policies = @(
                    [pscustomobject]@{
                        type = 'tag'
                        name = 'release-v*.*.*'
                    }
                )
            }
        }
        default {
            throw "Unexpected test API request '$Uri'."
        }
    }
}

function Invoke-PolicyFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [object[]] $MainRules,

        [Parameter(Mandatory = $true)]
        [object] $BranchProtection,

        [Parameter(Mandatory = $true)]
        [bool] $ShouldPass
        ,
        [switch] $TagRuleOverlap,

        [ValidateSet('User', 'Organization')]
        [string] $OwnerType = 'User',

        [switch] $EnvironmentHasReviewer
    )

    $global:ReleasePolicyTestMainRules = $MainRules
    $global:ReleasePolicyTestBranchProtection = $BranchProtection
    $global:ReleasePolicyTestRequestCount = 0
    $global:ReleasePolicyTestTagRuleOverlap = [bool]$TagRuleOverlap
    $global:ReleasePolicyTestOwnerType = $OwnerType
    $global:ReleasePolicyTestEnvironmentHasReviewer =
        [bool]$EnvironmentHasReviewer
    $failed = $false
    try {
        & $scriptUnderTest `
            -Repository 'wiresock/WireSockUI' `
            -GitHubApiUrl 'https://api.github.com' `
            -ReleaseTag 'release-v1.2.3' `
            -RequiredEnvironment 'release-publish' |
            Out-Null
    }
    catch {
        $failed = $true
    }

    if ($failed -eq $ShouldPass) {
        throw "Release policy fixture '$Name' produced the wrong result."
    }
    if ($global:ReleasePolicyTestRequestCount -lt 1) {
        throw "Release policy fixture '$Name' made no API requests."
    }
}

try {
    $env:GH_TOKEN = 'fixture-token'
    $global:ReleasePolicyTestRequestCount = 0
    $trailingNewlineRejected = $false
    try {
        & $scriptUnderTest `
            -Repository 'wiresock/WireSockUI' `
            -GitHubApiUrl 'https://api.github.com' `
            -ReleaseTag "release-v1.2.3`n" `
            -RequiredEnvironment 'release-publish' |
            Out-Null
    }
    catch {
        $trailingNewlineRejected = $true
    }
    if (-not $trailingNewlineRejected -or
        $global:ReleasePolicyTestRequestCount -ne 0) {
        throw 'A release identity with a trailing newline was not rejected before the first API request.'
    }

    Invoke-PolicyFixture `
        -Name 'overlapping-rules' `
        -MainRules (New-MainRules) `
        -BranchProtection (New-BranchProtection) `
        -ShouldPass $true
    Invoke-PolicyFixture `
        -Name 'conflicting-status-integration' `
        -MainRules (New-MainRules -ConflictingDuplicate) `
        -BranchProtection (New-BranchProtection) `
        -ShouldPass $false
    Invoke-PolicyFixture `
        -Name 'classic-pr-bypass' `
        -MainRules (New-MainRules) `
        -BranchProtection (New-BranchProtection -WithBypass) `
        -ShouldPass $false
    Invoke-PolicyFixture `
        -Name 'unsatisfiable-independent-approval' `
        -MainRules (New-MainRules -WithApproval) `
        -BranchProtection (New-BranchProtection -WithApproval) `
        -ShouldPass $false
    Invoke-PolicyFixture `
        -Name 'active-tag-ruleset-overlap' `
        -MainRules (New-MainRules) `
        -BranchProtection (New-BranchProtection) `
        -ShouldPass $false `
        -TagRuleOverlap
    Invoke-PolicyFixture `
        -Name 'organization-owner' `
        -MainRules (New-MainRules) `
        -BranchProtection (New-BranchProtection) `
        -ShouldPass $false `
        -OwnerType Organization
    Invoke-PolicyFixture `
        -Name 'personal-owner-environment-reviewer' `
        -MainRules (New-MainRules) `
        -BranchProtection (New-BranchProtection) `
        -ShouldPass $false `
        -EnvironmentHasReviewer
}
finally {
    if ($null -eq $previousToken) {
        Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
    }
    else {
        $env:GH_TOKEN = $previousToken
    }
    Remove-Item Function:\Invoke-RestMethod -Force -ErrorAction SilentlyContinue
    Remove-Variable `
        -Name ReleasePolicyTestMainRules `
        -Scope Global `
        -Force `
        -ErrorAction SilentlyContinue
    Remove-Variable `
        -Name ReleasePolicyTestBranchProtection `
        -Scope Global `
        -Force `
        -ErrorAction SilentlyContinue
    Remove-Variable `
        -Name ReleasePolicyTestRequestCount `
        -Scope Global `
        -Force `
        -ErrorAction SilentlyContinue
    Remove-Variable `
        -Name ReleasePolicyTestTagRuleOverlap `
        -Scope Global `
        -Force `
        -ErrorAction SilentlyContinue
    Remove-Variable `
        -Name ReleasePolicyTestOwnerType `
        -Scope Global `
        -Force `
        -ErrorAction SilentlyContinue
    Remove-Variable `
        -Name ReleasePolicyTestEnvironmentHasReviewer `
        -Scope Global `
        -Force `
        -ErrorAction SilentlyContinue
}

Write-Output 'Release repository policy fixtures passed.'
