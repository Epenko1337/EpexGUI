Set-StrictMode -Version Latest

$maximumMsiDiagnosticBytes = 32MB

function Read-MsiLogSnapshot {
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][Int64]$SnapshotLength
    )

    if ($SnapshotLength -lt 0 -or
        $SnapshotLength -gt $maximumMsiDiagnosticBytes) {
        return [pscustomobject]@{
            IsOversized = $true
            Bytes = [byte[]]::new(0)
            Count = 0
        }
    }

    $bytes = [byte[]]::new([int]$SnapshotLength)
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -le 0) {
            break
        }
        $offset += $read
    }
    return [pscustomobject]@{
        IsOversized = $false
        Bytes = $bytes
        Count = $offset
    }
}

function Get-BoundedMsiLogDiagnostic {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [IO.File]::Exists($Path)) {
        return "MSI log '$Path' was not created."
    }

    $evidence = New-Object 'System.Collections.Generic.Queue[string]'
    $tail = New-Object 'System.Collections.Generic.Queue[string]'
    $stream = $null
    $snapshotStream = $null
    $reader = $null
    try {
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $snapshot = Read-MsiLogSnapshot `
            -Stream $stream `
            -SnapshotLength $stream.Length
        $stream.Dispose()
        $stream = $null
        if ($snapshot.IsOversized) {
            return "MSI log '$Path' is larger than the 32 MiB diagnostic limit."
        }
        $snapshotStream = [IO.MemoryStream]::new(
            $snapshot.Bytes,
            0,
            $snapshot.Count,
            $false)
        $reader = [IO.StreamReader]::new(
            $snapshotStream,
            [Text.Encoding]::Default,
            $true,
            4096,
            $false)
        while (($line = $reader.ReadLine()) -ne $null) {
            $boundedLine = if ($line.Length -gt 512) {
                $line.Substring(0, 512) + '...'
            }
            else {
                $line
            }
            if ($boundedLine -match
                    '(?i)(return value 3|error [0-9]{3,5}|failed|failure|exception|could not|cannot|access is denied)') {
                if ($evidence.Count -eq 40) {
                    [void]$evidence.Dequeue()
                }
                $evidence.Enqueue($boundedLine)
            }
            if ($tail.Count -eq 40) {
                [void]$tail.Dequeue()
            }
            $tail.Enqueue($boundedLine)
        }
    }
    catch {
        return "MSI log '$Path' could not be read: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $snapshotStream) {
            $snapshotStream.Dispose()
        }
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    $newLine = [Environment]::NewLine
    $evidenceText = @($evidence.ToArray()) -join $newLine
    if ($evidenceText.Length -gt 8000) {
        $evidenceText =
            '...' + $evidenceText.Substring($evidenceText.Length - 8000)
    }
    if ([string]::IsNullOrWhiteSpace($evidenceText)) {
        $evidenceText = '(no common failure markers found)'
    }
    $tailText = @($tail.ToArray()) -join $newLine
    if ($tailText.Length -gt 8000) {
        $tailText = '...' + $tailText.Substring($tailText.Length - 8000)
    }
    return (
        "MSI failure evidence from '$Path':$newLine$evidenceText" +
        "$newLine--- MSI log tail ---$newLine$tailText")
}

Export-ModuleMember -Function Get-BoundedMsiLogDiagnostic
