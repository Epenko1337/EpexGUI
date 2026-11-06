#requires -Version 7.0

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$resolver = Join-Path $PSScriptRoot 'Resolve-BuildVersion.ps1'
$temporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("WireSockUI-BuildVersion-" + [Guid]::NewGuid().ToString('N'))

function Invoke-FixtureGit {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $output = @(& git -C $temporaryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Fixture Git command failed: $($output -join ' ')"
    }
}

function Assert-Version {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Expected
    )

    $actual = & $resolver -RepositoryRoot $temporaryRoot
    if ($actual -cne $Expected) {
        throw "Expected build version '$Expected', got '$actual'."
    }
}

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    Invoke-FixtureGit -Arguments @('init', '--initial-branch=main')
    Invoke-FixtureGit -Arguments @('config', 'user.name', 'WireSockUI tests')
    Invoke-FixtureGit -Arguments @(
        'config',
        'user.email',
        'wiresockui-tests@example.invalid'
    )

    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'payload.txt') `
        -Value 'initial' `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'payload.txt')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Initial repository state')

    Invoke-FixtureGit -Arguments @('switch', '-c', 'versioning')
    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'version.json') `
        -Value @'
{
  "schema": 1,
  "major": 2,
  "minor": 3,
  "buildNumberStart": 1
}
'@ `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'version.json')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Introduce version epoch')
    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'payload.txt') `
        -Value 'versioning branch follow-up' `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'payload.txt')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Versioning follow-up')
    Assert-Version -Expected '2.3.1'
    Invoke-FixtureGit -Arguments @('switch', 'main')
    Invoke-FixtureGit -Arguments @(
        'merge',
        '--no-ff',
        '--no-edit',
        'versioning'
    )
    Assert-Version -Expected '2.3.1'

    Invoke-FixtureGit -Arguments @('switch', '-c', 'feature')
    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'payload.txt') `
        -Value 'feature commit one' `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'payload.txt')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Feature commit one')
    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'payload.txt') `
        -Value 'feature commit two' `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'payload.txt')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Feature commit two')
    Assert-Version -Expected '2.3.2'

    Invoke-FixtureGit -Arguments @('switch', '--detach', 'main')
    Invoke-FixtureGit -Arguments @(
        'merge',
        '--no-ff',
        '--no-edit',
        'feature'
    )
    Assert-Version -Expected '2.3.2'

    Invoke-FixtureGit -Arguments @('switch', 'main')
    Invoke-FixtureGit -Arguments @(
        'merge',
        '--no-ff',
        '--no-edit',
        'feature'
    )
    Assert-Version -Expected '2.3.2'

    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'payload.txt') `
        -Value 'direct protected update' `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'payload.txt')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Protected update')
    Assert-Version -Expected '2.3.3'

    Invoke-FixtureGit -Arguments @('switch', '-c', 'minor-release')
    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'version.json') `
        -Value @'
{
  "schema": 1,
  "major": 2,
  "minor": 4,
  "buildNumberStart": 0
}
'@ `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'version.json')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Start 2.4 release epoch')
    Assert-Version -Expected '2.4.0'

    Invoke-FixtureGit -Arguments @('switch', 'main')
    Invoke-FixtureGit -Arguments @(
        'merge',
        '--no-ff',
        '--no-edit',
        'minor-release'
    )
    Assert-Version -Expected '2.4.0'

    Invoke-FixtureGit -Arguments @('switch', '-c', 'post-minor-feature')
    Set-Content `
        -LiteralPath (Join-Path $temporaryRoot 'payload.txt') `
        -Value 'post minor feature' `
        -Encoding utf8
    Invoke-FixtureGit -Arguments @('add', 'payload.txt')
    Invoke-FixtureGit -Arguments @('commit', '-m', 'Post minor feature')
    Assert-Version -Expected '2.4.1'

    Write-Output 'Validated deterministic first-parent build versioning.'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
