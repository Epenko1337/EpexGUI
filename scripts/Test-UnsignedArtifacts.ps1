#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$maximumEntries = 4096
$supportedExtensions = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($extension in @('.dll', '.exe', '.msi')) {
    [void]$supportedExtensions.Add($extension)
}

function Assert-OrdinaryItem {
    param(
        [Parameter(Mandatory = $true)]
        [IO.FileSystemInfo] $Item
    )

    $linkType = $Item.PSObject.Properties['LinkType']
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ($null -ne $linkType -and
         -not [string]::IsNullOrEmpty([string]$linkType.Value))) {
        throw "Unsigned artifact input '$($Item.FullName)' must not be a link or reparse point."
    }
}

function Test-HasPeCertificateTable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ModulePath
    )

    $stream = [IO.File]::OpenRead($ModulePath)
    try {
        $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::UTF8, $true)
        try {
            if ($stream.Length -lt 256 -or $reader.ReadUInt16() -ne 0x5A4D) {
                throw "Release module '$ModulePath' is not a valid PE image."
            }
            $stream.Position = 0x3c
            [UInt32]$peOffset = $reader.ReadUInt32()
            if ($peOffset -gt $stream.Length - 256) {
                throw "Release module '$ModulePath' has an invalid PE offset."
            }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                throw "Release module '$ModulePath' has no PE signature."
            }
            $optionalHeaderOffset = [Int64]$peOffset + 24
            $stream.Position = $optionalHeaderOffset
            $magic = $reader.ReadUInt16()
            if ($magic -eq 0x10b) {
                $numberOfDirectoriesOffset = $optionalHeaderOffset + 92
                $dataDirectoryOffset = $optionalHeaderOffset + 96
            }
            elseif ($magic -eq 0x20b) {
                $numberOfDirectoriesOffset = $optionalHeaderOffset + 108
                $dataDirectoryOffset = $optionalHeaderOffset + 112
            }
            else {
                throw "Release module '$ModulePath' has unsupported PE optional-header magic."
            }
            $stream.Position = $numberOfDirectoriesOffset
            if ($reader.ReadUInt32() -lt 5) {
                return $false
            }
            $stream.Position = $dataDirectoryOffset + (4 * 8)
            $certificateOffset = $reader.ReadUInt32()
            $certificateSize = $reader.ReadUInt32()
            return $certificateOffset -ne 0 -or $certificateSize -ne 0
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-HasMzHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    $stream = [IO.File]::OpenRead($FilePath)
    try {
        if ($stream.Length -lt 2) {
            return $false
        }

        return $stream.ReadByte() -eq 0x4d -and $stream.ReadByte() -eq 0x5a
    }
    finally {
        $stream.Dispose()
    }
}

function Test-IsReleaseArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [IO.FileInfo] $File
    )

    return $supportedExtensions.Contains($File.Extension) -or
        (Test-HasMzHeader -FilePath $File.FullName)
}

$targets = [Collections.Generic.List[IO.FileInfo]]::new()
$seenPaths = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$pendingDirectories = [Collections.Generic.Queue[IO.DirectoryInfo]]::new()

foreach ($inputPath in $Path) {
    $item = Get-Item -LiteralPath $inputPath -Force -ErrorAction Stop
    Assert-OrdinaryItem -Item $item
    if ($item.PSIsContainer) {
        $pendingDirectories.Enqueue([IO.DirectoryInfo]$item)
    }
    elseif (Test-IsReleaseArtifact -File ([IO.FileInfo]$item)) {
        if ($seenPaths.Add($item.FullName)) {
            $targets.Add([IO.FileInfo]$item)
        }
    }
    else {
        throw "Unsigned artifact file '$($item.FullName)' is not a portable executable or MSI."
    }
}

$entryCount = 0
while ($pendingDirectories.Count -gt 0) {
    $directory = $pendingDirectories.Dequeue()
    foreach ($child in @(Get-ChildItem -LiteralPath $directory.FullName -Force)) {
        Assert-OrdinaryItem -Item $child
        $entryCount++
        if ($entryCount -gt $maximumEntries) {
            throw "Unsigned artifact input exceeds the $maximumEntries-entry limit."
        }
        if ($child.PSIsContainer) {
            $pendingDirectories.Enqueue([IO.DirectoryInfo]$child)
        }
        elseif ((Test-IsReleaseArtifact -File ([IO.FileInfo]$child)) -and
                $seenPaths.Add($child.FullName)) {
            $targets.Add([IO.FileInfo]$child)
        }
    }
}

if ($targets.Count -lt 1) {
    throw 'Unsigned artifact input contains no portable executable or MSI files.'
}

foreach ($target in $targets) {
    $isUnsigned = if ($target.Extension -ieq '.msi') {
        (Get-AuthenticodeSignature -LiteralPath $target.FullName).Status -eq
            [Management.Automation.SignatureStatus]::NotSigned
    }
    else {
        -not (Test-HasPeCertificateTable -ModulePath $target.FullName)
    }
    if (-not $isUnsigned) {
        throw (
            "Release artifact '$($target.FullName)' must not contain an " +
            'embedded Authenticode certificate table.')
    }
}

Write-Output "Validated $($targets.Count) unsigned release artifact(s)."
