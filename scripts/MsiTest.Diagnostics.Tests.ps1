$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$diagnosticModule = Import-Module `
    (Join-Path $PSScriptRoot 'MsiTest.Diagnostics.psm1') `
    -Force `
    -PassThru

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'WireSockUI.Msi.Diagnostics.' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)

try {
    $missingPath = Join-Path $testRoot 'missing.log'
    $missingDiagnostic = Get-BoundedMsiLogDiagnostic -Path $missingPath
    if ($missingDiagnostic -notmatch 'was not created') {
        throw 'The missing-log diagnostic was not actionable.'
    }

    $failureLogPath = Join-Path $testRoot 'failure.log'
    $lines = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt 60; $index++) {
        [void]$lines.Add(
            "Error 1000. early failure marker $index " + ('x' * 600))
    }
    [void]$lines.Add('Error 1926. Could not set file security for file C:\example.')
    [void]$lines.Add('Action ended: InstallFinalize. Return value 3.')
    for ($index = 60; $index -lt 120; $index++) {
        [void]$lines.Add("tail log line $index")
    }
    [IO.File]::WriteAllLines(
        $failureLogPath,
        $lines,
        [Text.UnicodeEncoding]::new($false, $true))

    $failureDiagnostic = Get-BoundedMsiLogDiagnostic -Path $failureLogPath
    if ($failureDiagnostic -notmatch 'Error 1926' -or
        $failureDiagnostic -notmatch 'Return value 3' -or
        $failureDiagnostic -notmatch 'tail log line 119') {
        throw 'The bounded MSI diagnostic omitted failure evidence or the log tail.'
    }
    if ($failureDiagnostic -match 'early failure marker 0') {
        throw 'The bounded MSI diagnostic retained early markers instead of the latest evidence.'
    }
    if ($failureDiagnostic.Length -gt 17000) {
        throw "The bounded MSI diagnostic grew to $($failureDiagnostic.Length) characters."
    }

    $oversizedLogPath = Join-Path $testRoot 'oversized.log'
    $stream = [IO.File]::Open(
        $oversizedLogPath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None)
    try {
        $stream.SetLength(32MB + 1)
    }
    finally {
        $stream.Dispose()
    }
    $oversizedDiagnostic = Get-BoundedMsiLogDiagnostic -Path $oversizedLogPath
    if ($oversizedDiagnostic -notmatch 'larger than the 32 MiB diagnostic limit') {
        throw 'The oversized MSI log was not rejected before reading.'
    }

    $growingBytes = [Text.Encoding]::UTF8.GetBytes(
        'initial snapshot followed by appended writer data')
    $growingStream = [IO.MemoryStream]::new($growingBytes, $false)
    try {
        $snapshot = & $diagnosticModule {
            param($Stream, $SnapshotLength)

            Read-MsiLogSnapshot `
                -Stream $Stream `
                -SnapshotLength $SnapshotLength
        } $growingStream 16
        if ($snapshot.Count -ne 16 -or
            [Text.Encoding]::UTF8.GetString(
                $snapshot.Bytes,
                0,
                $snapshot.Count) -cne 'initial snapshot') {
            throw 'The MSI diagnostic snapshot consumed data appended after its length capture.'
        }
    }
    finally {
        $growingStream.Dispose()
    }
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $normalizedTempRoot = [IO.Path]::GetFullPath(
        [IO.Path]::GetTempPath()).TrimEnd('\', '/') + '\'
    if (-not $resolvedTestRoot.StartsWith(
            $normalizedTempRoot,
            [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $resolvedTestRoot).StartsWith(
            'WireSockUI.Msi.Diagnostics.',
            [StringComparison]::Ordinal)) {
        throw "Refusing to remove unexpected MSI diagnostic test path '$resolvedTestRoot'."
    }
    if ([IO.Directory]::Exists($resolvedTestRoot)) {
        $entry = Get-Item -LiteralPath $resolvedTestRoot -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove reparse-point MSI diagnostic test path '$resolvedTestRoot'."
        }
        [IO.Directory]::Delete($resolvedTestRoot, $true)
    }
}

Write-Output 'Validated bounded MSI failure diagnostics.'
