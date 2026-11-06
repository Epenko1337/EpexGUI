[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptUnderTest = Join-Path $PSScriptRoot 'Test-SdkRunnerPolicy.ps1'
$workflowSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$global:SdkRunnerPolicyTestRunners = @()
$global:SdkRunnerPolicySelectedWorkflow = (
    "wiresock/WireSockUI/.github/workflows/sdk-integration.yml@$workflowSha")

function New-TestRunner {
    param(
        [Parameter(Mandatory = $true)]
        [Int64] $Id,

        [Parameter(Mandatory = $true)]
        [string] $RoutingLabel,

        [Parameter(Mandatory = $true)]
        [string] $HardwareLabel
    )

    return [pscustomobject]@{
        id = $Id
        name = "fixture-$RoutingLabel"
        os = 'windows'
        status = 'online'
        busy = $false
        ephemeral = $true
        version = '2.329.0'
        labels = @(
            [pscustomobject]@{ name = 'self-hosted' },
            [pscustomobject]@{ name = 'Windows' },
            [pscustomobject]@{ name = $HardwareLabel },
            [pscustomobject]@{ name = 'wiresock-sdk' },
            [pscustomobject]@{ name = $RoutingLabel }
        )
    }
}

function global:Invoke-RestMethod {
    param(
        [string] $Method,
        [hashtable] $Headers,
        [int] $TimeoutSec,
        [string] $Uri
    )

    if ($Uri -eq 'https://api.github.com/repos/wiresock/WireSockUI') {
        return [pscustomobject]@{
            id = [Int64]42
            full_name = 'wiresock/WireSockUI'
            private = $false
            owner = [pscustomobject]@{
                login = 'wiresock'
                type = 'Organization'
            }
        }
    }
    if ($Uri -eq 'https://api.github.com/orgs/wiresock/actions/runner-groups?per_page=100&page=1') {
        return [pscustomobject]@{
            total_count = 1
            runner_groups = @(
                [pscustomobject]@{
                    id = [Int64]7
                    name = 'wiresock-sdk'
                }
            )
        }
    }
    if ($Uri -eq 'https://api.github.com/orgs/wiresock/actions/runner-groups/7') {
        return [pscustomobject]@{
            id = [Int64]7
            name = 'wiresock-sdk'
            visibility = 'selected'
            default = $false
            inherited = $false
            allows_public_repositories = $true
            restricted_to_workflows = $true
            selected_workflows = @($global:SdkRunnerPolicySelectedWorkflow)
            workflow_restrictions_read_only = $false
        }
    }
    if ($Uri -eq 'https://api.github.com/orgs/wiresock/actions/runner-groups/7/repositories?per_page=100&page=1') {
        return [pscustomobject]@{
            total_count = 1
            repositories = @(
                [pscustomobject]@{
                    id = [Int64]42
                    full_name = 'wiresock/WireSockUI'
                }
            )
        }
    }
    if ($Uri -eq 'https://api.github.com/orgs/wiresock/actions/runner-groups/7/runners?per_page=100&page=1') {
        return [pscustomobject]@{
            total_count = $global:SdkRunnerPolicyTestRunners.Count
            runners = @($global:SdkRunnerPolicyTestRunners)
        }
    }
    throw "Unexpected fixture REST request: $Method $Uri"
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedMessage
    )

    try {
        & $Action
        throw "Expected failure containing '$ExpectedMessage', but the command succeeded."
    }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "Expected failure containing '$ExpectedMessage', got '$($_.Exception.Message)'."
        }
    }
}

$arguments = @{
    Repository = 'wiresock/WireSockUI'
    GitHubApiUrl = 'https://api.github.com'
    WorkflowSha = $workflowSha
}
$env:GH_TOKEN = 'fixture-token'

try {
    $global:SdkRunnerPolicyTestRunners = @()
    $null = & $scriptUnderTest @arguments -WarningAction SilentlyContinue

    $global:SdkRunnerPolicyTestRunners = @(
        New-TestRunner `
            -Id 101 `
            -RoutingLabel 'wiresock-sdk-x86' `
            -HardwareLabel 'X64'
        New-TestRunner `
            -Id 102 `
            -RoutingLabel 'wiresock-sdk-x64' `
            -HardwareLabel 'X64'
        New-TestRunner `
            -Id 103 `
            -RoutingLabel 'wiresock-sdk-arm64' `
            -HardwareLabel 'ARM64'
    )
    $null = & $scriptUnderTest @arguments

    $global:SdkRunnerPolicyTestRunners[0].labels[2].name = 'ARM64'
    Assert-Throws `
        -Action {
            & $scriptUnderTest @arguments
        } `
        -ExpectedMessage 'exact common, hardware, and logical routing labels'

    $global:SdkRunnerPolicyTestRunners = @()
    $global:SdkRunnerPolicySelectedWorkflow = (
        'wiresock/WireSockUI/.github/workflows/sdk-integration.yml@' +
        ('b' * 40))
    Assert-Throws `
        -Action {
            & $scriptUnderTest @arguments -WarningAction SilentlyContinue
        } `
        -ExpectedMessage 'restricted to exact workflow'

    Write-Output 'SDK runner policy tests passed.'
}
finally {
    Remove-Item -LiteralPath Function:\Invoke-RestMethod -Force
    Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
    Remove-Variable -Name SdkRunnerPolicyTestRunners -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name SdkRunnerPolicySelectedWorkflow -Scope Global -ErrorAction SilentlyContinue
}
