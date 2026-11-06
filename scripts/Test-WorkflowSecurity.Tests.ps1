#requires -Version 7.0

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$validator = Join-Path $PSScriptRoot 'Test-WorkflowSecurity.ps1'
$temporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("WireSockUI-WorkflowSecurity-" + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporaryRoot)

$validWorkflow = @'
name: fixture
permissions:
  contents: read
on:
  push:
    tags:
      - 'release-v*.*.*'
jobs:
  test:
    runs-on: windows-latest
    timeout-minutes: 5
    steps:
      - name: Checkout
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0
        with:
          persist-credentials: false
      - name: Safely consume context
        env:
          SAFE_REF: ${{ github.ref_name }}
        run: Write-Host $env:SAFE_REF
'@
$validShorthandWorkflow = $validWorkflow -replace (
    '(?m)^      - name: Checkout\r?\n        uses:'),
    '      - uses:'
$validManualWorkflow = $validWorkflow -replace (
    '(?m)^  push:\s*$'),
    "  workflow_dispatch:`n  push:"
$sdkIntegrationWorkflow = Get-Content `
    -LiteralPath (
        Join-Path (
            Split-Path -Parent $PSScriptRoot
        ) '.github\workflows\sdk-integration.yml') `
    -Raw `
    -Encoding UTF8
$productionMainWorkflow = Get-Content `
    -LiteralPath (
        Join-Path (
            Split-Path -Parent $PSScriptRoot
        ) '.github\workflows\main.yml') `
    -Raw `
    -Encoding UTF8
$productionWorkflowDirectory = Join-Path (
    Split-Path -Parent $PSScriptRoot
) '.github\workflows'
$productionCiWorkflow = Get-Content `
    -LiteralPath (Join-Path $productionWorkflowDirectory 'ci.yml') `
    -Raw `
    -Encoding UTF8
$productionHostedSdkExperimentWorkflow = Get-Content `
    -LiteralPath (
        Join-Path $productionWorkflowDirectory 'hosted-sdk-experiment.yml') `
    -Raw `
    -Encoding UTF8
$productionSdkContractDriftWorkflow = Get-Content `
    -LiteralPath (
        Join-Path $productionWorkflowDirectory 'sdk-contract-drift.yml') `
    -Raw `
    -Encoding UTF8
$productionSdkScheduleWorkflow = Get-Content `
    -LiteralPath (
        Join-Path $productionWorkflowDirectory 'sdk-integration-schedule.yml') `
    -Raw `
    -Encoding UTF8
$productionUnsignedReleaseCandidateWorkflow = Get-Content `
    -LiteralPath (
        Join-Path $productionWorkflowDirectory 'unsigned-release-candidate.yml') `
    -Raw `
    -Encoding UTF8
$productionPinMatch = [regex]::Match(
    $productionMainWorkflow,
    'wiresock/WireSockUI/\.github/workflows/' +
        'sdk-integration\.yml@(?<sha>[0-9a-f]{40})')
if (-not $productionPinMatch.Success) {
    throw 'The production workflow fixture has no immutable implementation pin.'
}
$productionPinnedRevision = $productionPinMatch.Groups['sha'].Value
$privilegedCallerPattern =
    '(?m)(uses:\s+wiresock/WireSockUI/\.github/workflows/' +
    'sdk-integration\.yml)@[0-9a-f]{40}'
$mutableProductionMainWorkflow = [Text.RegularExpressions.Regex]::new(
    $privilegedCallerPattern
).Replace(
    $productionMainWorkflow,
    '$1@main',
    1)
if ($mutableProductionMainWorkflow -ceq $productionMainWorkflow) {
    throw 'The production workflow fixture has no pinned privileged caller to mutate.'
}

function Invoke-Fixture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Workflow,

        [Parameter(Mandatory = $true)]
        [bool] $ShouldPass,

        [Parameter()]
        [string] $SdkIntegrationWorkflow,

        [Parameter()]
        [bool] $RequireProductionContracts = $false,

        [Parameter()]
        [string] $AdditionalWorkflowName,

        [Parameter()]
        [string] $AdditionalWorkflow,

        [Parameter()]
        [string] $AuxiliaryPinReplacement,

        [Parameter()]
        [string] $ExpectedErrorPattern,

        [Parameter()]
        [hashtable] $AuxiliaryWorkflowOverrides
    )

    $fixture = Join-Path $temporaryRoot $Name
    [void](New-Item -ItemType Directory -Path $fixture)
    Set-Content `
        -LiteralPath (Join-Path $fixture 'main.yml') `
        -Value $Workflow `
        -Encoding utf8

    if (-not [string]::IsNullOrEmpty($SdkIntegrationWorkflow)) {
        Set-Content `
            -LiteralPath (Join-Path $fixture 'sdk-integration.yml') `
            -Value $SdkIntegrationWorkflow `
            -Encoding utf8
    }
    if ($RequireProductionContracts) {
        foreach ($workflowName in @(
                'ci.yml',
                'hosted-sdk-experiment.yml',
                'sdk-contract-drift.yml',
                'sdk-integration-schedule.yml',
                'unsigned-release-candidate.yml')) {
            $sourcePath = Join-Path `
                $productionWorkflowDirectory `
                $workflowName
            $destinationPath = Join-Path $fixture $workflowName
            $hasOverride =
                $null -ne $AuxiliaryWorkflowOverrides -and
                $AuxiliaryWorkflowOverrides.ContainsKey($workflowName)
            if (-not $hasOverride -and
                [string]::IsNullOrEmpty($AuxiliaryPinReplacement)) {
                Copy-Item `
                    -LiteralPath $sourcePath `
                    -Destination $destinationPath
            }
            else {
                $auxiliaryWorkflow = if ($hasOverride) {
                    [string]$AuxiliaryWorkflowOverrides[$workflowName]
                }
                else {
                    Get-Content `
                        -LiteralPath $sourcePath `
                        -Raw `
                        -Encoding UTF8
                }
                if (-not [string]::IsNullOrEmpty(
                        $AuxiliaryPinReplacement)) {
                    $auxiliaryWorkflow = $auxiliaryWorkflow.Replace(
                        $productionPinnedRevision,
                        $AuxiliaryPinReplacement)
                }
                Set-Content `
                    -LiteralPath $destinationPath `
                    -Value $auxiliaryWorkflow `
                    -Encoding utf8
            }
        }
    }
    if (-not [string]::IsNullOrEmpty($AdditionalWorkflowName)) {
        Set-Content `
            -LiteralPath (Join-Path $fixture $AdditionalWorkflowName) `
            -Value $AdditionalWorkflow `
            -Encoding utf8
    }

    $failed = $false
    $failureMessage = ''
    try {
        & $validator `
            -WorkflowDirectory $fixture `
            -RequireProductionContracts:$RequireProductionContracts |
            Out-Null
    }
    catch {
        $failed = $true
        $failureMessage = $_.Exception.Message
    }
    if ($failed -eq $ShouldPass) {
        throw "Workflow security fixture '$Name' produced the wrong result."
    }
    if (-not $ShouldPass -and
        -not [string]::IsNullOrEmpty($ExpectedErrorPattern) -and
        $failureMessage -notmatch $ExpectedErrorPattern) {
        throw (
            "Workflow security fixture '$Name' failed for an unexpected " +
            "reason: $failureMessage")
    }
}

function Invoke-ProductionContractFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter()]
        [string] $MainWorkflow = $productionMainWorkflow,

        [Parameter()]
        [string] $SdkWorkflow = $sdkIntegrationWorkflow,

        [Parameter()]
        [string] $AdditionalWorkflowName,

        [Parameter()]
        [string] $AdditionalWorkflow,

        [Parameter()]
        [string] $AuxiliaryPinReplacement,

        [Parameter()]
        [hashtable] $AuxiliaryWorkflowOverrides
    )

    Invoke-Fixture `
        -Name $Name `
        -Workflow $MainWorkflow `
        -SdkIntegrationWorkflow $SdkWorkflow `
        -RequireProductionContracts $true `
        -AdditionalWorkflowName $AdditionalWorkflowName `
        -AdditionalWorkflow $AdditionalWorkflow `
        -AuxiliaryPinReplacement $AuxiliaryPinReplacement `
        -AuxiliaryWorkflowOverrides $AuxiliaryWorkflowOverrides `
        -ExpectedErrorPattern (
            '(?i)(?:production workflow|audited control contract)') `
        -ShouldPass $false
}

try {
    Invoke-Fixture -Name valid -Workflow $validWorkflow -ShouldPass $true
    Invoke-Fixture `
        -Name valid-shorthand `
        -Workflow $validShorthandWorkflow `
        -ShouldPass $true
    Invoke-Fixture `
        -Name valid-manual `
        -Workflow $validManualWorkflow `
        -ShouldPass $true
    Invoke-Fixture `
        -Name valid-production-workflow `
        -Workflow $productionMainWorkflow `
        -SdkIntegrationWorkflow $sdkIntegrationWorkflow `
        -RequireProductionContracts $true `
        -ShouldPass $true
    Invoke-Fixture `
        -Name mutable-production-privileged-caller `
        -Workflow $mutableProductionMainWorkflow `
        -SdkIntegrationWorkflow $sdkIntegrationWorkflow `
        -RequireProductionContracts $true `
        -ShouldPass $false
    Invoke-ProductionContractFixture `
        -Name production-release-drops-hosted-sdk-prerequisite `
        -MainWorkflow $productionMainWorkflow.Replace(
            '          foreach ($workflow in @($env:CI_WORKFLOW, $env:HOSTED_SDK_WORKFLOW)) {',
            '          foreach ($workflow in @($env:CI_WORKFLOW)) {')
    Invoke-ProductionContractFixture `
        -Name production-contract-detects-unmodeled-change `
        -MainWorkflow (
            $productionMainWorkflow +
            "`n# Any production workflow change requires contract review.")
    Invoke-ProductionContractFixture `
        -Name production-contract-locks-sdk-workflow `
        -SdkWorkflow (
            $sdkIntegrationWorkflow +
            "`n# Any production workflow change requires contract review.")
    Invoke-ProductionContractFixture `
        -Name production-contract-locks-ci-workflow `
        -AuxiliaryWorkflowOverrides @{
            'ci.yml' = (
                $productionCiWorkflow +
                "`n# Any production workflow change requires contract review.")
        }
    Invoke-ProductionContractFixture `
        -Name production-contract-locks-hosted-sdk-experiment-workflow `
        -AuxiliaryWorkflowOverrides @{
            'hosted-sdk-experiment.yml' = (
                $productionHostedSdkExperimentWorkflow +
                "`n# Any production workflow change requires contract review.")
        }
    Invoke-ProductionContractFixture `
        -Name production-contract-locks-sdk-drift-workflow `
        -AuxiliaryWorkflowOverrides @{
            'sdk-contract-drift.yml' = (
                $productionSdkContractDriftWorkflow +
                "`n# Any production workflow change requires contract review.")
        }
    Invoke-ProductionContractFixture `
        -Name production-contract-locks-sdk-schedule-workflow `
        -AuxiliaryWorkflowOverrides @{
            'sdk-integration-schedule.yml' = (
                $productionSdkScheduleWorkflow +
                "`n# Any production workflow change requires contract review.")
        }
    Invoke-ProductionContractFixture `
        -Name production-contract-locks-unsigned-rc-workflow `
        -AuxiliaryWorkflowOverrides @{
            'unsigned-release-candidate.yml' = (
                $productionUnsignedReleaseCandidateWorkflow +
                "`n# Any production workflow change requires contract review.")
        }
    Invoke-ProductionContractFixture `
        -Name production-contract-rejects-extra-workflow `
        -AdditionalWorkflowName 'unreviewed.yml' `
        -AdditionalWorkflow $validWorkflow
    $unapprovedRevision = '1111111111111111111111111111111111111111'
    Invoke-ProductionContractFixture `
        -Name production-contract-rejects-coordinated-pin-change `
        -MainWorkflow $productionMainWorkflow.Replace(
            $productionPinnedRevision,
            $unapprovedRevision) `
        -AuxiliaryPinReplacement $unapprovedRevision
    Invoke-ProductionContractFixture `
        -Name production-build-drops-sdk-dependency `
        -MainWorkflow ([regex]::Replace(
            $productionMainWorkflow,
            '(?m)^      - sdk-integration\r?\n',
            '',
            1))
    Invoke-ProductionContractFixture `
        -Name production-package-drops-build-dependency `
        -MainWorkflow ([regex]::Replace(
            $productionMainWorkflow,
            '(?m)(^  package:\r?\n(?:.*\r?\n){0,5}?)^      - build\r?\n',
            '$1',
            1))
    Invoke-ProductionContractFixture `
        -Name production-upload-runs-after-failure `
        -MainWorkflow $productionMainWorkflow.Replace(
            '  upload-release:
    if: ${{ success() }}',
            '  upload-release:
    if: ${{ always() }}')
    Invoke-ProductionContractFixture `
        -Name production-upload-drops-attestation-dependency `
        -MainWorkflow ([regex]::Replace(
            $productionMainWorkflow,
            '(?m)(^  upload-release:\r?\n(?:.*\r?\n){0,5}?)^      - attest\r?\n',
            '$1',
            1))
    Invoke-ProductionContractFixture `
        -Name production-verification-job-skipped `
        -MainWorkflow $productionMainWorkflow.Replace(
            '  verify-release:
    if: ${{ success() }}',
            '  verify-release:
    if: ${{ false }}')
    Invoke-ProductionContractFixture `
        -Name production-publication-error-suppressed `
        -MainWorkflow $productionMainWorkflow.Replace(
            '      - name: Publish or safely resume immutable release
        shell: pwsh',
            '      - name: Publish or safely resume immutable release
        continue-on-error: true
        shell: pwsh')
    Invoke-ProductionContractFixture `
        -Name production-repository-policy-short-circuited `
        -MainWorkflow $productionMainWorkflow.Replace(
            '        run: >
          ./scripts/Test-ReleaseRepositoryPolicy.ps1',
            '        run: |
          return
          ./scripts/Test-ReleaseRepositoryPolicy.ps1')
    Invoke-ProductionContractFixture `
        -Name production-sdk-configuration-skipped `
        -SdkWorkflow $sdkIntegrationWorkflow.Replace(
            '  configuration:
    runs-on:',
            '  configuration:
    if: ${{ false }}
    runs-on:')
    Invoke-ProductionContractFixture `
        -Name production-sdk-runner-policy-error-suppressed `
        -SdkWorkflow $sdkIntegrationWorkflow.Replace(
            '  runner-policy:
    needs:',
            '  runner-policy:
    continue-on-error: true
    needs:')
    Invoke-ProductionContractFixture `
        -Name production-sdk-smoke-drops-policy-dependency `
        -SdkWorkflow ([regex]::Replace(
            $sdkIntegrationWorkflow,
            '(?m)(^  elevated-sdk-smoke:\r?\n(?:.*\r?\n){0,5}?)' +
                '^      - runner-policy\r?\n',
            '$1',
            1))
    Invoke-ProductionContractFixture `
        -Name production-sdk-matrix-loses-arm64 `
        -SdkWorkflow ([regex]::Replace(
            $sdkIntegrationWorkflow,
            '(?ms)^          - platform: ARM64\r?\n' +
                '.*?(?=^    runs-on:)',
            '',
            1))
    Invoke-ProductionContractFixture `
        -Name production-sdk-context-rebound `
        -SdkWorkflow $sdkIntegrationWorkflow.Replace(
            '          SDK_WORKFLOW_SHA: ${{ inputs.sdk_workflow_sha }}',
            '          SDK_WORKFLOW_SHA: ${{ job.workflow_sha }}')
    Invoke-ProductionContractFixture `
        -Name production-sdk-authorization-short-circuited `
        -SdkWorkflow $sdkIntegrationWorkflow.Replace(
            '      - name: Authorize trusted candidate revision
        id: authorize',
            '      - name: Authorize trusted candidate revision
        id: authorize
        if: ${{ false }}')
    Invoke-ProductionContractFixture `
        -Name production-sdk-policy-invocation-swallowed `
        -SdkWorkflow $sdkIntegrationWorkflow.Replace(
            '        run: >
          ./.trusted-sdk-tooling/scripts/Test-SdkRunnerPolicy.ps1',
            '        run: |
          try {
            ./.trusted-sdk-tooling/scripts/Test-SdkRunnerPolicy.ps1
          }
          catch {
          }')
    Invoke-Fixture `
        -Name caller-sha-used-as-sdk-tooling-source `
        -Workflow $validWorkflow `
        -SdkIntegrationWorkflow $sdkIntegrationWorkflow.Replace(
            '${{ job.workflow_sha }}',
            '${{ github.workflow_sha }}') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name skipped-sdk-authorization `
        -Workflow $validWorkflow `
        -SdkIntegrationWorkflow $sdkIntegrationWorkflow.Replace(
            '      - name: Authorize trusted candidate revision
        id: authorize',
            '      - name: Authorize trusted candidate revision
        if: ${{ false }}
        id: authorize') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name suppressed-sdk-runner-policy-failure `
        -Workflow $validWorkflow `
        -SdkIntegrationWorkflow $sdkIntegrationWorkflow.Replace(
            '      - name: Verify exact SDK runner-group policy
        shell: pwsh',
            '      - name: Verify exact SDK runner-group policy
        continue-on-error: true
        shell: pwsh') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name mutable `
        -Workflow $validWorkflow.Replace(
            'actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0',
            'actions/checkout@main') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name credentials `
        -Workflow $validWorkflow.Replace(
            'persist-credentials: false',
            'persist-credentials: true') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name duplicate-quoted-credentials `
        -Workflow $validWorkflow.Replace(
            '          persist-credentials: false',
            "          persist-credentials: false`n          persist-credentials: `"true`"") `
        -ShouldPass $false
    Invoke-Fixture `
        -Name dangerous-trigger `
        -Workflow ($validWorkflow -replace
            '(?m)^  push:\r?$',
            '  pull_request_target:') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name wrong-tags `
        -Workflow $validWorkflow.Replace(
            "'release-v*.*.*'",
            "'v*'") `
        -ShouldPass $false
    Invoke-Fixture `
        -Name shorthand-mutable `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            "    steps:`n      - uses: actions/checkout@main") `
        -ShouldPass $false
    Invoke-Fixture `
        -Name quoted-uses-key `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            "    steps:`n      - `"uses`": actions/checkout@main") `
        -ShouldPass $false
    Invoke-Fixture `
        -Name escaped-uses-key `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            '    steps:
      - "u\u0073es": actions/checkout@main') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name escaped-flow-uses-key `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            '    steps:
      - { "u\u0073es": actions/checkout@main }') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name flow-uses-key `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            "    steps:`n      - { uses: actions/checkout@main }") `
        -ShouldPass $false
    Invoke-Fixture `
        -Name explicit-uses-key `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            "    steps:`n      - ? uses`n        : actions/checkout@main") `
        -ShouldPass $false
    Invoke-Fixture `
        -Name compact-explicit-escaped-uses-key `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            '    steps:
      - { ?"u\u0073es": actions/checkout@main }') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name inline-trigger-map `
        -Workflow $validWorkflow.Replace(
            'on:',
            'on: { pull_request_target: {} }') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name inline-trigger-list `
        -Workflow $validWorkflow.Replace(
            'on:',
            'on: [push, pull_request_target]') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name quoted-write-all `
        -Workflow ($validWorkflow -replace
            '(?m)^  test:\r?\n    runs-on:',
            "  test:`n    permissions: `"write-all`"`n    runs-on:") `
        -ShouldPass $false
    Invoke-Fixture `
        -Name escaped-write-all-key `
        -Workflow ($validWorkflow -replace
            '(?m)^  test:\r?\n    runs-on:',
            '  test:
    "permiss\u0069ons": write-all
    runs-on:') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name escaped-persist-credentials-key `
        -Workflow $validWorkflow.Replace(
            '          persist-credentials: false',
            '          persist-credentials: false
          "persist-cr\u0065dentials": true') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name direct-run-expression `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        run: Write-Host ''${{ github.ref_name }}''') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name escaped-run-expression `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        run: "\u0024{{ github.ref_name }}"') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name next-line-run-block-expression `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        run:
          |
            Write-Host ''${{ github.ref_name }}''') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name plain-run-continuation-expression `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        run: Write-Host
          ''${{ github.ref_name }}''') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name indentation-indicator-run-expression `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        run: |2
          Write-Host ''${{ github.ref_name }}''') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name chomping-indicator-run-expression `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        run: >-
          Write-Host ''${{ github.ref_name }}''') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name bare-tagged-run-expression `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        run: ! |
          Write-Host ''${{ github.ref_name }}''') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name block-scalar-permissions `
        -Workflow $validWorkflow.Replace(
            'permissions:
  contents: read',
            'permissions:
  |-
    write-all') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name deferred-plain-permissions `
        -Workflow $validWorkflow.Replace(
            'permissions:
  contents: read',
            'permissions:
  write-all') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name escaped-forbidden-secret `
        -Workflow $validWorkflow.Replace(
            '          SAFE_REF: ${{ github.ref_name }}',
            '          SAFE_REF: ${{ github.ref_name }}
          TOKEN: "${{ secrets.MY_GITHUB_\u0050AT }}"') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name deferred-escaped-forbidden-secret `
        -Workflow $validWorkflow.Replace(
            '          SAFE_REF: ${{ github.ref_name }}',
            '          SAFE_REF: ${{ github.ref_name }}
          TOKEN:
            "${{ secrets.MY_GITHUB_\u0050AT }}"') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name computed-forbidden-secret `
        -Workflow $validWorkflow.Replace(
            '          SAFE_REF: ${{ github.ref_name }}',
            '          SAFE_REF: ${{ github.ref_name }}
          TOKEN: ${{ secrets[format(''MY_GITHUB_{0}'', ''PAT'')] }}') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name computed-forbidden-secret-in-attestation-block `
        -Workflow $validWorkflow.Replace(
            '    steps:',
            '    steps:
      - name: Unsafe attestation input
        uses: actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6
        with:
          subject-path: |
            ${{ secrets[format(''MY_GITHUB_{0}'', ''PAT'')] }}') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name child-powershell-command-injection `
        -Workflow $validWorkflow.Replace(
            '          SAFE_REF: ${{ github.ref_name }}
        run: Write-Host $env:SAFE_REF',
            '          SAFE_REF: ${{ github.ref_name }}
          UNTRUSTED: ${{ github.event.pull_request.title }}
        run: pwsh -NoProfile -Command $env:UNTRUSTED') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name dynamic-shell `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        shell: ${{ github.event.pull_request.title }}
        run: Write-Host $env:SAFE_REF') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name dynamic-working-directory `
        -Workflow $validWorkflow.Replace(
            '        run: Write-Host $env:SAFE_REF',
            '        working-directory: ${{ github.event.pull_request.title }}
        run: Write-Host $env:SAFE_REF') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name dynamic-runner `
        -Workflow $validWorkflow.Replace(
            '    runs-on: windows-latest',
            '    runs-on: ${{ github.event.pull_request.title }}') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name self-hosted-runner `
        -Workflow $validWorkflow.Replace(
            '    runs-on: windows-latest',
            '    runs-on: self-hosted') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name job-container `
        -Workflow $validWorkflow.Replace(
            '    runs-on: windows-latest',
            '    runs-on: windows-latest
    container: attacker.invalid/image:latest') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name aliased-permissions `
        -Workflow $validWorkflow.Replace(
            'permissions:
  contents: read',
            'permission-value: &write_all write-all
permissions: *write_all') `
        -ShouldPass $false
    Invoke-Fixture `
        -Name tagged-permissions `
        -Workflow $validWorkflow.Replace(
            'permissions:
  contents: read',
            'permissions: !!str write-all') `
        -ShouldPass $false
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output 'Workflow security fixtures passed.'
