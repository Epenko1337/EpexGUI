[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('x86', 'x64', 'arm64')]
    [string]$ExpectedArchitecture,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [Parameter(Mandatory = $true)]
    [ValidateSet('uwp', 'no-uwp')]
    [string]$ExpectedFlavor,

    [string]$ExpectedProductCode,

    [string]$ExpectedFilesPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ValidationMetadataPath,

    [string]$WixToolPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nativeBootstrapValidationModule = Join-Path $PSScriptRoot 'NativeBootstrap.Validation.psm1'
Import-Module -Name $nativeBootstrapValidationModule -Force -ErrorAction Stop

$maximumMsiBytes = [Int64](2GB)
$maximumValidationMetadataBytes = [Int64](4MB)
$maximumPayloadEntries = 4096
$maximumPayloadFileBytes = [Int64](512MB)
$maximumPayloadBytes = [Int64](2GB)

$ExpectedArchitecture = $ExpectedArchitecture.ToLowerInvariant()
$ExpectedFlavor = $ExpectedFlavor.ToLowerInvariant()
$versionMatch = [regex]::Match(
    $ExpectedVersion,
    '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
if (-not $versionMatch.Success -or
    [int]$versionMatch.Groups[1].Value -gt 255 -or
    [int]$versionMatch.Groups[2].Value -gt 255 -or
    [int]$versionMatch.Groups[3].Value -gt 65535) {
    throw "ExpectedVersion '$ExpectedVersion' is not a canonical Windows Installer version."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedProductCode) -and
    $ExpectedProductCode -cnotmatch '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$') {
    throw "ExpectedProductCode '$ExpectedProductCode' is not a canonical uppercase product code."
}

$expectedUpgradeCode = '{5C1DDAE5-6681-41BF-B153-AB2952AA6DF1}'
$resolvedMsiPath = [IO.Path]::GetFullPath($MsiPath)
if (-not [IO.File]::Exists($resolvedMsiPath)) {
    throw "MSI '$resolvedMsiPath' does not exist."
}
$msiFile = Get-Item -LiteralPath $resolvedMsiPath -Force
if (($msiFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "MSI '$resolvedMsiPath' must not be a reparse point."
}
$msiLength = [Int64]$msiFile.Length
if ($msiLength -le 0 -or $msiLength -gt $maximumMsiBytes) {
    throw "MSI '$resolvedMsiPath' has invalid length $msiLength; the limit is $maximumMsiBytes bytes."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedFilesPath) -and -not [IO.File]::Exists($ExpectedFilesPath)) {
    throw "Expected file list '$ExpectedFilesPath' does not exist."
}
if (-not [string]::IsNullOrWhiteSpace($ValidationMetadataPath) -and
    -not [IO.File]::Exists($ValidationMetadataPath)) {
    throw "Validation metadata '$ValidationMetadataPath' does not exist."
}
if (-not [string]::IsNullOrWhiteSpace($ValidationMetadataPath)) {
    $validationMetadataFile =
        Get-Item -LiteralPath $ValidationMetadataPath -Force
    if (($validationMetadataFile.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Validation metadata '$ValidationMetadataPath' must not be a reparse point."
    }
    $validationMetadataLength = [Int64]$validationMetadataFile.Length
    if ($validationMetadataLength -le 0 -or
        $validationMetadataLength -gt $maximumValidationMetadataBytes) {
        throw "Validation metadata '$ValidationMetadataPath' has invalid length $validationMetadataLength; the limit is $maximumValidationMetadataBytes bytes."
    }
}

& (Join-Path $PSScriptRoot 'Test-UnsignedArtifacts.ps1') `
    -Path $resolvedMsiPath |
    Out-Null

$installer = $null
$database = $null

function Invoke-ComMethod {
    param(
        [object]$Instance,
        [string]$Name,
        [object[]]$Arguments
    )

    return $Instance.GetType().InvokeMember(
        $Name,
        [Reflection.BindingFlags]::InvokeMethod,
        $null,
        $Instance,
        $Arguments)
}

function Get-ComProperty {
    param(
        [object]$Instance,
        [string]$Name,
        [object[]]$Arguments
    )

    return $Instance.GetType().InvokeMember(
        $Name,
        [Reflection.BindingFlags]::GetProperty,
        $null,
        $Instance,
        $Arguments)
}

function Get-MsiRows {
    param(
        [string]$Sql,
        [int]$MaximumRows = 8192,
        [int]$MaximumFields = 64,
        [int]$MaximumFieldCharacters = 32768,
        [Int64]$MaximumQueryCharacters = 16MB
    )

    if ($MaximumRows -lt 1 -or
        $MaximumFields -lt 1 -or
        $MaximumFieldCharacters -lt 1 -or
        $MaximumQueryCharacters -lt 1) {
        throw 'MSI query bounds must be positive.'
    }

    $view = $null
    try {
        $view = Invoke-ComMethod -Instance $database -Name 'OpenView' -Arguments @($Sql)
        Invoke-ComMethod -Instance $view -Name 'Execute' -Arguments @() | Out-Null

        $rows = New-Object 'System.Collections.Generic.List[object]'
        [Int64]$queryCharacters = 0
        while ($true) {
            $record = Invoke-ComMethod -Instance $view -Name 'Fetch' -Arguments @()
            if ($null -eq $record) {
                break
            }

            try {
                if ($rows.Count -ge $MaximumRows) {
                    throw "MSI query exceeded the $MaximumRows-row validation limit."
                }
                $fieldCount = [int](Get-ComProperty -Instance $record -Name 'FieldCount' -Arguments @())
                if ($fieldCount -lt 1 -or $fieldCount -gt $MaximumFields) {
                    throw "MSI query returned invalid field count $fieldCount."
                }
                $values = New-Object 'System.Collections.Generic.List[string]'
                for ($fieldIndex = 1; $fieldIndex -le $fieldCount; $fieldIndex++) {
                    $value = [string](Get-ComProperty `
                        -Instance $record `
                        -Name 'StringData' `
                        -Arguments @($fieldIndex))
                    if ($value.Length -gt $MaximumFieldCharacters -or
                        $queryCharacters -gt $MaximumQueryCharacters - $value.Length) {
                        throw 'MSI query returned an overlong field or exceeded its aggregate text limit.'
                    }
                    $queryCharacters += $value.Length
                    $values.Add($value)
                }
                $rows.Add($values.ToArray())
            }
            finally {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) | Out-Null
            }
        }

        return $rows.ToArray()
    }
    catch {
        throw "MSI query failed: $Sql$([Environment]::NewLine)$($_.Exception.Message)"
    }
    finally {
        if ($null -ne $view) {
            try {
                Invoke-ComMethod -Instance $view -Name 'Close' -Arguments @() | Out-Null
            }
            finally {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) | Out-Null
            }
        }
    }
}

function Get-MsiProperty {
    param([string]$Name)

    $escapedName = $Name.Replace("'", "''")
    $rows = @(Get-MsiRows -Sql "SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$escapedName'")
    if ($rows.Count -ne 1) {
        throw "MSI property '$Name' is missing or duplicated."
    }
    return [string]$rows[0][0]
}

function Assert-ExactMsiSequenceTable {
    param(
        [string]$TableName,
        [hashtable]$ExpectedActions
    )

    if ($TableName -cnotmatch '^[A-Za-z][A-Za-z0-9_]{0,71}$') {
        throw "Invalid MSI sequence table name '$TableName'."
    }
    $rows = @(Get-MsiRows -Sql "SELECT * FROM ``$TableName``")
    if ($rows.Count -ne $ExpectedActions.Count) {
        throw "MSI $TableName has $($rows.Count) rows; expected $($ExpectedActions.Count)."
    }
    $seenActions = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    foreach ($row in $rows) {
        $action = [string]$row[0]
        [int]$sequence = 0
        $expectedAction = if ($ExpectedActions.ContainsKey($action)) {
            $ExpectedActions[$action]
        }
        else {
            $null
        }
        $expectedCondition = if ($expectedAction -is [hashtable]) {
            [string]$expectedAction.Condition
        }
        else {
            ''
        }
        $expectedSequence = if ($expectedAction -is [hashtable]) {
            [int]$expectedAction.Sequence
        }
        else {
            [int]$expectedAction
        }
        if (-not $ExpectedActions.ContainsKey($action) -or
            -not $seenActions.Add($action) -or
            [string]$row[1] -cne $expectedCondition -or
            -not [int]::TryParse(
                [string]$row[2],
                [Globalization.NumberStyles]::AllowLeadingSign,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$sequence) -or
            $sequence -ne $expectedSequence) {
            throw "MSI $TableName contains unexpected action, condition, or sequence metadata for '$action'."
        }
    }
}

function Get-DeterministicGuid {
    param([string]$Identity)

    $namespacedIdentity = "3DCCF284-7EB4-442D-A94B-4B6E56FAC03A|WireSockUI|$Identity"
    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $hashAlgorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($namespacedIdentity))
    }
    finally {
        $hashAlgorithm.Dispose()
    }

    $guidBytes = New-Object byte[] 16
    [Array]::Copy($hash, $guidBytes, $guidBytes.Length)
    $guidBytes[7] = ($guidBytes[7] -band 0x0f) -bor 0x50
    $guidBytes[8] = ($guidBytes[8] -band 0x3f) -bor 0x80
    return (New-Object Guid (,$guidBytes)).ToString('B').ToUpperInvariant()
}

function Get-DeterministicMsiIdentifier {
    param(
        [string]$Prefix,
        [string]$Identity
    )

    $guid = Get-DeterministicGuid -Identity "MsiIdentifier|$Identity"
    return $Prefix + $guid.Substring(1, 36).Replace('-', '')
}

function Get-DeterministicProductCode {
    param(
        [string]$Architecture,
        [string]$ProductVersion,
        [string]$ProductFlavor
    )

    return Get-DeterministicGuid `
        -Identity "ProductCode|$Architecture|$ProductFlavor|$ProductVersion"
}

function Get-LongMsiName {
    param([string]$Value)

    $targetName = ($Value -split ':', 2)[0]
    if ($targetName.Contains('|')) {
        return ($targetName -split '\|', 2)[1]
    }
    return $targetName
}

function Get-PortableExecutableArchitecture {
    param([string]$Path)

    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 64) {
            throw "Portable executable '$Path' is truncated."
        }

        $reader = New-Object IO.BinaryReader $stream
        try {
            if ($reader.ReadUInt16() -ne 0x5a4d) {
                throw "Portable executable '$Path' has no DOS header."
            }
            $stream.Position = 0x3c
            $peOffset = [uint32]$reader.ReadUInt32()
            if ($peOffset -gt $stream.Length - 6) {
                throw "Portable executable '$Path' has an invalid PE header offset."
            }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                throw "Portable executable '$Path' has no PE signature."
            }
            switch ($reader.ReadUInt16()) {
                0x014c { return 'x86' }
                0x8664 { return 'x64' }
                0xaa64 { return 'arm64' }
                default { throw "Portable executable '$Path' uses an unsupported machine type." }
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Export-MsiStream {
    param(
        [string]$DatabasePath,
        [string]$StreamName,
        [string]$OutputPath,
        [Int64]$MaximumBytes
    )

    if ($null -eq ('WireSockUI.Installer.MsiStreamExporter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

namespace WireSockUI.Installer
{
    public static class MsiStreamExporter
    {
        private const uint ErrorSuccess = 0;
        private const uint ErrorNoMoreItems = 259;

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern uint MsiOpenDatabase(
            string databasePath,
            IntPtr persist,
            out uint database);

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern uint MsiDatabaseOpenView(
            uint database,
            string query,
            out uint view);

        [DllImport("msi.dll")]
        private static extern uint MsiViewExecute(uint view, uint record);

        [DllImport("msi.dll")]
        private static extern uint MsiViewFetch(uint view, out uint record);

        [DllImport("msi.dll")]
        private static extern uint MsiRecordDataSize(uint record, uint field);

        [DllImport("msi.dll")]
        private static extern uint MsiRecordReadStream(
            uint record,
            uint field,
            [Out] byte[] buffer,
            ref uint bufferSize);

        [DllImport("msi.dll")]
        private static extern uint MsiCloseHandle(uint handle);

        private static void ThrowOnError(uint result, string operation)
        {
            if (result != ErrorSuccess)
                throw new Win32Exception(
                    unchecked((int)result),
                    operation + " failed with Windows Installer error " + result + ".");
        }

        public static long Export(
            string databasePath,
            string streamName,
            string outputPath,
            long maximumBytes)
        {
            if (string.IsNullOrEmpty(databasePath))
                throw new ArgumentException("A database path is required.", "databasePath");
            if (string.IsNullOrEmpty(streamName))
                throw new ArgumentException("A stream name is required.", "streamName");
            if (string.IsNullOrEmpty(outputPath))
                throw new ArgumentException("An output path is required.", "outputPath");
            if (maximumBytes <= 0 || maximumBytes > uint.MaxValue)
                throw new ArgumentOutOfRangeException("maximumBytes");

            uint database = 0;
            uint view = 0;
            uint record = 0;
            try
            {
                ThrowOnError(
                    MsiOpenDatabase(databasePath, IntPtr.Zero, out database),
                    "Opening the MSI database");
                var escapedName = streamName.Replace("'", "''");
                var query =
                    "SELECT `Data` FROM `_Streams` WHERE `Name`='" +
                    escapedName +
                    "'";
                ThrowOnError(
                    MsiDatabaseOpenView(database, query, out view),
                    "Opening the MSI stream query");
                ThrowOnError(MsiViewExecute(view, 0), "Executing the MSI stream query");

                var fetchResult = MsiViewFetch(view, out record);
                ThrowOnError(fetchResult, "Fetching the MSI stream");
                var length = (long)MsiRecordDataSize(record, 1);
                if (length <= 0 || length > maximumBytes)
                    throw new InvalidDataException(
                        "The MSI stream has invalid length " + length + ".");

                using (var output = new FileStream(
                    outputPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    65536,
                    FileOptions.SequentialScan))
                {
                    var buffer = new byte[65536];
                    long total = 0;
                    while (total < length)
                    {
                        var requested = (uint)Math.Min(
                            (long)buffer.Length,
                            length - total);
                        var read = requested;
                        ThrowOnError(
                            MsiRecordReadStream(record, 1, buffer, ref read),
                            "Reading the MSI stream");
                        if (read == 0 || read > requested)
                            throw new InvalidDataException(
                                "The MSI stream ended before its declared length.");
                        output.Write(buffer, 0, checked((int)read));
                        total += read;
                    }
                    output.Flush(true);
                }

                MsiCloseHandle(record);
                record = 0;
                uint unexpectedRecord;
                fetchResult = MsiViewFetch(view, out unexpectedRecord);
                if (fetchResult == ErrorSuccess)
                {
                    MsiCloseHandle(unexpectedRecord);
                    throw new InvalidDataException(
                        "The MSI contains duplicate streams with the requested name.");
                }
                if (fetchResult != ErrorNoMoreItems)
                    ThrowOnError(fetchResult, "Completing the MSI stream query");
                return length;
            }
            finally
            {
                if (record != 0)
                    MsiCloseHandle(record);
                if (view != 0)
                    MsiCloseHandle(view);
                if (database != 0)
                    MsiCloseHandle(database);
            }
        }
    }
}
'@
    }

    return [WireSockUI.Installer.MsiStreamExporter]::Export(
        $DatabasePath,
        $StreamName,
        $OutputPath,
        $MaximumBytes)
}

function Read-CabinetAsciiName {
    param(
        [IO.BinaryReader]$Reader,
        [Int64]$CabinetLength
    )

    $bytes = New-Object 'System.Collections.Generic.List[byte]'
    while ($Reader.BaseStream.Position -lt $CabinetLength) {
        $value = $Reader.ReadByte()
        if ($value -eq 0) {
            if ($bytes.Count -eq 0) {
                throw 'The cabinet contains an empty file identifier.'
            }
            return [Text.Encoding]::ASCII.GetString($bytes.ToArray())
        }
        if ($value -lt 0x21 -or $value -gt 0x7e -or $bytes.Count -ge 72) {
            throw 'The cabinet contains a noncanonical or overlong file identifier.'
        }
        $bytes.Add($value)
    }

    throw 'The cabinet file table contains an unterminated file identifier.'
}

function Assert-CabinetMetadata {
    param(
        [string]$Path,
        [hashtable]$ExpectedFileSizes,
        [Int64]$ExpectedTotalBytes
    )

    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read)
    try {
        $cabinetLength = [Int64]$stream.Length
        if ($cabinetLength -lt 36 -or $cabinetLength -gt $maximumMsiBytes) {
            throw "Embedded cabinet has invalid length $cabinetLength."
        }

        $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::ASCII, $true)
        try {
            if ($reader.ReadUInt32() -ne 0x4643534d) {
                throw 'Embedded MSI stream is not a Microsoft Cabinet file.'
            }
            if ($reader.ReadUInt32() -ne 0) {
                throw 'Cabinet header reserved field 1 is nonzero.'
            }
            [Int64]$declaredCabinetLength = $reader.ReadUInt32()
            if ($declaredCabinetLength -ne $cabinetLength) {
                throw "Cabinet declares length $declaredCabinetLength, but its MSI stream is $cabinetLength bytes."
            }
            if ($reader.ReadUInt32() -ne 0) {
                throw 'Cabinet header reserved field 2 is nonzero.'
            }
            [Int64]$fileTableOffset = $reader.ReadUInt32()
            if ($reader.ReadUInt32() -ne 0) {
                throw 'Cabinet header reserved field 3 is nonzero.'
            }
            $minorVersion = $reader.ReadByte()
            $majorVersion = $reader.ReadByte()
            $folderCount = [int]$reader.ReadUInt16()
            $fileCount = [int]$reader.ReadUInt16()
            $flags = $reader.ReadUInt16()
            $setId = $reader.ReadUInt16()
            $cabinetIndex = $reader.ReadUInt16()

            if ($majorVersion -ne 1 -or $minorVersion -ne 3) {
                throw "Cabinet version $majorVersion.$minorVersion is unsupported."
            }
            if ($folderCount -lt 1 -or $folderCount -gt 64) {
                throw "Cabinet has invalid folder count $folderCount."
            }
            if ($fileCount -ne $ExpectedFileSizes.Count -or
                $fileCount -gt $maximumPayloadEntries) {
                throw "Cabinet has $fileCount files; expected $($ExpectedFileSizes.Count)."
            }
            if ($flags -ne 0 -and $flags -ne 4) {
                throw "Cabinet uses unsupported continuation or reserved flags 0x$($flags.ToString('X4'))."
            }
            if ($cabinetIndex -ne 0) {
                throw 'A single embedded cabinet must have cabinet index zero.'
            }

            $folderReserveBytes = 0
            $dataReserveBytes = 0
            if (($flags -band 4) -ne 0) {
                $headerReserveBytes = [int]$reader.ReadUInt16()
                $folderReserveBytes = [int]$reader.ReadByte()
                $dataReserveBytes = [int]$reader.ReadByte()
                if ($reader.BaseStream.Position + $headerReserveBytes -gt $cabinetLength) {
                    throw 'Cabinet header reserve data exceeds the stream.'
                }
                $reader.BaseStream.Position += $headerReserveBytes
            }

            $folders = New-Object 'System.Collections.Generic.List[object]'
            for ($folderIndex = 0; $folderIndex -lt $folderCount; $folderIndex++) {
                if ($reader.BaseStream.Position + 8 + $folderReserveBytes -gt $cabinetLength) {
                    throw 'Cabinet folder table is truncated.'
                }
                [Int64]$dataOffset = $reader.ReadUInt32()
                $dataBlockCount = [int]$reader.ReadUInt16()
                $compression = $reader.ReadUInt16()
                $compressionKind = $compression -band 0x000f
                if ($dataBlockCount -lt 1 -or
                    $compressionKind -lt 0 -or
                    $compressionKind -gt 3 -or
                    $dataOffset -ge $cabinetLength) {
                    throw "Cabinet folder $folderIndex has invalid compression or data metadata."
                }
                $reader.BaseStream.Position += $folderReserveBytes
                $folders.Add([pscustomobject]@{
                    Index = $folderIndex
                    DataOffset = $dataOffset
                    DataBlockCount = $dataBlockCount
                    ExpectedBytes = [Int64]0
                })
            }

            if ($fileTableOffset -ne $reader.BaseStream.Position -or
                $fileTableOffset -ge $cabinetLength) {
                throw 'Cabinet file table offset is noncanonical or outside the stream.'
            }
            $reader.BaseStream.Position = $fileTableOffset

            $seenCabinetFiles = New-Object 'System.Collections.Generic.HashSet[string]' (
                [StringComparer]::Ordinal)
            $filesByFolder = @{}
            [Int64]$cabinetTotalBytes = 0
            for ($fileIndex = 0; $fileIndex -lt $fileCount; $fileIndex++) {
                if ($reader.BaseStream.Position + 16 -gt $cabinetLength) {
                    throw 'Cabinet file table is truncated.'
                }
                [Int64]$size = $reader.ReadUInt32()
                [Int64]$folderOffset = $reader.ReadUInt32()
                $folderIndex = [int]$reader.ReadUInt16()
                $reader.ReadUInt16() | Out-Null
                $reader.ReadUInt16() | Out-Null
                $attributes = $reader.ReadUInt16()
                $fileId = Read-CabinetAsciiName -Reader $reader -CabinetLength $cabinetLength

                if ($folderIndex -lt 0 -or $folderIndex -ge $folderCount) {
                    throw "Cabinet file '$fileId' uses a split or invalid folder index."
                }
                if (($attributes -band 0x0080) -ne 0 -or
                    $fileId -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
                    -not $seenCabinetFiles.Add($fileId) -or
                    -not $ExpectedFileSizes.ContainsKey($fileId)) {
                    throw "Cabinet contains unknown, duplicate, or noncanonical file identifier '$fileId'."
                }
                if ($size -ne [Int64]$ExpectedFileSizes[$fileId] -or
                    $size -gt $maximumPayloadFileBytes -or
                    $folderOffset -gt $maximumPayloadBytes - $size) {
                    throw "Cabinet file '$fileId' has invalid size or folder offset metadata."
                }
                if ($cabinetTotalBytes -gt $maximumPayloadBytes - $size) {
                    throw 'Cabinet file table describes more than 2 GiB.'
                }
                $cabinetTotalBytes += $size
                if (-not $filesByFolder.ContainsKey($folderIndex)) {
                    $filesByFolder[$folderIndex] =
                        New-Object 'System.Collections.Generic.List[object]'
                }
                $filesByFolder[$folderIndex].Add([pscustomobject]@{
                    Id = $fileId
                    Offset = $folderOffset
                    Size = $size
                })
            }

            if ($cabinetTotalBytes -ne $ExpectedTotalBytes -or
                $seenCabinetFiles.Count -ne $ExpectedFileSizes.Count) {
                throw 'Cabinet file inventory does not exactly match the MSI File table.'
            }

            $fileTableEnd = [Int64]$reader.BaseStream.Position
            [Int64]$totalDataBlocks = 0
            [Int64]$previousDataEnd = $fileTableEnd
            foreach ($folder in @($folders | Sort-Object DataOffset)) {
                if (-not $filesByFolder.ContainsKey($folder.Index)) {
                    throw "Cabinet folder $($folder.Index) contains no files."
                }
                [Int64]$expectedOffset = 0
                $seenFolderRanges = New-Object 'System.Collections.Generic.HashSet[string]' (
                    [StringComparer]::Ordinal)
                foreach ($cabinetFile in @($filesByFolder[$folder.Index] | Sort-Object Offset)) {
                    $rangeIdentity = "$($cabinetFile.Offset):$($cabinetFile.Size)"
                    if ($cabinetFile.Offset -lt $expectedOffset -and
                        $seenFolderRanges.Contains($rangeIdentity)) {
                        # WiX may deduplicate byte-identical files by pointing
                        # multiple CFFILE records at one exact folder range.
                        continue
                    }
                    if ($cabinetFile.Offset -ne $expectedOffset -or
                        -not $seenFolderRanges.Add($rangeIdentity)) {
                        throw "Cabinet folder $($folder.Index) has overlapping, sparse, or reordered file '$($cabinetFile.Id)' at offset $($cabinetFile.Offset); expected $expectedOffset."
                    }
                    $expectedOffset += $cabinetFile.Size
                }
                $folder.ExpectedBytes = $expectedOffset

                if ($folder.DataOffset -lt $previousDataEnd) {
                    throw "Cabinet folder $($folder.Index) data overlaps metadata or another folder."
                }
                $reader.BaseStream.Position = $folder.DataOffset
                [Int64]$folderExpandedBytes = 0
                for ($blockIndex = 0; $blockIndex -lt $folder.DataBlockCount; $blockIndex++) {
                    $totalDataBlocks++
                    if ($totalDataBlocks -gt 131072 -or
                        $reader.BaseStream.Position + 8 + $dataReserveBytes -gt $cabinetLength) {
                        throw 'Cabinet data block inventory is excessive or truncated.'
                    }
                    $reader.ReadUInt32() | Out-Null
                    $compressedBytes = [int]$reader.ReadUInt16()
                    $expandedBytes = [int]$reader.ReadUInt16()
                    if ($compressedBytes -lt 1 -or $expandedBytes -lt 1) {
                        throw "Cabinet folder $($folder.Index) contains an empty or split data block."
                    }
                    if ($folderExpandedBytes -gt $maximumPayloadBytes - $expandedBytes) {
                        throw 'Cabinet data blocks expand beyond the 2 GiB limit.'
                    }
                    $folderExpandedBytes += $expandedBytes
                    [Int64]$nextBlock = $reader.BaseStream.Position +
                        $dataReserveBytes +
                        $compressedBytes
                    if ($nextBlock -gt $cabinetLength) {
                        throw 'Cabinet data block exceeds the embedded stream.'
                    }
                    $reader.BaseStream.Position = $nextBlock
                }
                if ($folderExpandedBytes -ne $folder.ExpectedBytes) {
                    throw "Cabinet folder $($folder.Index) expands to $folderExpandedBytes bytes; its files require $($folder.ExpectedBytes)."
                }
                $previousDataEnd = [Int64]$reader.BaseStream.Position
            }

            if ($previousDataEnd -ne $cabinetLength) {
                throw 'Cabinet contains trailing or unreferenced compressed data.'
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-EmbeddedPayloadManifestRecords {
    param([string]$Path)

    if ($null -eq ('WireSockUI.Installer.PayloadManifestReader' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

namespace WireSockUI.Installer
{
    public static class PayloadManifestReader
    {
        private const uint LoadLibraryAsImageResource = 0x00000020;
        private const uint LoadLibraryAsDataFileExclusive = 0x00000040;
        private const int PayloadManifestResourceId = 201;
        private const int RcDataResourceType = 10;
        private const uint MaximumManifestBytes = 2U * 1024U * 1024U;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(
            string fileName,
            IntPtr file,
            uint flags);

        [DllImport("kernel32.dll", EntryPoint = "FindResourceW", SetLastError = true)]
        private static extern IntPtr FindResource(
            IntPtr module,
            IntPtr name,
            IntPtr type);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SizeofResource(IntPtr module, IntPtr resource);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LockResource(IntPtr resourceData);

        [DllImport("kernel32.dll")]
        private static extern bool FreeLibrary(IntPtr module);

        public static byte[] Read(string path)
        {
            var module = LoadLibraryEx(
                path,
                IntPtr.Zero,
                LoadLibraryAsImageResource | LoadLibraryAsDataFileExclusive);
            if (module == IntPtr.Zero)
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Unable to map the launcher as a non-executable image resource.");

            try
            {
                var resource = FindResource(
                    module,
                    new IntPtr(PayloadManifestResourceId),
                    new IntPtr(RcDataResourceType));
                if (resource == IntPtr.Zero)
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "The launcher has no embedded payload manifest.");

                var size = SizeofResource(module, resource);
                if (size == 0 || size > MaximumManifestBytes)
                    throw new InvalidDataException(
                        "The embedded payload manifest has an invalid size.");

                var loaded = LoadResource(module, resource);
                if (loaded == IntPtr.Zero)
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "The embedded payload manifest could not be loaded.");
                var data = LockResource(loaded);
                if (data == IntPtr.Zero)
                    throw new InvalidDataException(
                        "The embedded payload manifest could not be locked.");

                var bytes = new byte[checked((int)size)];
                Marshal.Copy(data, bytes, 0, bytes.Length);
                return bytes;
            }
            finally
            {
                FreeLibrary(module);
            }
        }
    }
}
'@
    }

    $bytes = [WireSockUI.Installer.PayloadManifestReader]::Read($Path)
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    $text = $strictUtf8.GetString($bytes)
    if ($text.Contains("`r") -or
        -not $text.EndsWith("`n", [StringComparison]::Ordinal)) {
        throw 'The embedded payload manifest is not canonical LF-terminated UTF-8.'
    }
    $lines = $text.Split([char]10)
    if ($lines.Count -lt 2 -or
        $lines[0] -cne 'WireSockUI-Payload-v1' -or
        $lines[$lines.Count - 1] -cne '') {
        throw 'The launcher contains an unsupported embedded payload manifest.'
    }

    $records = New-Object 'System.Collections.Generic.List[object]'
    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase)
    $previousPath = $null
    for ($lineIndex = 1; $lineIndex -lt $lines.Count - 1; $lineIndex++) {
        $fields = $lines[$lineIndex].Split([char]9)
        [Int64]$size = 0
        if ($fields.Count -ne 3 -or
            $fields[0] -cnotmatch '^[0-9a-f]{64}$' -or
            $fields[1] -cnotmatch '^(0|[1-9][0-9]*)$' -or
            -not [Int64]::TryParse(
                $fields[1],
                [Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$size) -or
            $size -lt 0 -or
            $size -gt $maximumPayloadFileBytes -or
            [string]::IsNullOrEmpty($fields[2]) -or
            $fields[2] -ceq 'WireSockUI.exe' -or
            -not $seenPaths.Add($fields[2]) -or
            ($null -ne $previousPath -and
                [StringComparer]::OrdinalIgnoreCase.Compare(
                    $previousPath,
                    $fields[2]) -ge 0)) {
            throw "The embedded payload manifest has an invalid record on line $($lineIndex + 1)."
        }
        $previousPath = $fields[2]
        $records.Add([pscustomobject]@{
            Sha256 = $fields[0]
            Size = $size
            Path = $fields[2]
        })
    }
    if ($records.Count -lt 2 -or $records.Count -gt $maximumPayloadEntries) {
        throw "The embedded payload manifest has invalid record count $($records.Count)."
    }
    return $records.ToArray()
}

function Resolve-WixToolPath {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $resolvedExplicitPath = [IO.Path]::GetFullPath($ExplicitPath)
        if (-not [IO.File]::Exists($resolvedExplicitPath)) {
            throw "WiX tool '$resolvedExplicitPath' does not exist."
        }
        return $resolvedExplicitPath
    }

    $packageRoots = New-Object 'System.Collections.Generic.List[string]'
    $configuredPackageRoot = [Environment]::GetEnvironmentVariable('NUGET_PACKAGES')
    if (-not [string]::IsNullOrWhiteSpace($configuredPackageRoot)) {
        $packageRoots.Add([IO.Path]::GetFullPath($configuredPackageRoot))
    }
    $packageRoots.Add((Join-Path ([Environment]::GetFolderPath('UserProfile')) '.nuget\packages'))

    foreach ($packageRoot in $packageRoots | Select-Object -Unique) {
        $candidate = Join-Path $packageRoot 'wixtoolset.sdk\6.0.2\tools\net6.0\wix.dll'
        if ([IO.File]::Exists($candidate)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Pinned WiX 6.0.2 CLI was not found. Restore the installer project or pass -WixToolPath.'
}

$validationMetadata = $null
$metadataFiles = @()
$metadataByPath = @{}
$expectedSecurityComponentGuid = Get-DeterministicGuid `
    -Identity "Component|ApplicationDirectorySecurity|$ExpectedArchitecture"
$expectedShortcutComponentGuid = Get-DeterministicGuid `
    -Identity "Component|StartMenuShortcut|$ExpectedArchitecture"
$expectedDesktopShortcutComponentGuid = Get-DeterministicGuid `
    -Identity "Component|DesktopShortcut|$ExpectedArchitecture"
$expectedRuntimeHostComponentGuid = Get-DeterministicGuid `
    -Identity "Component|RuntimeHost|$ExpectedArchitecture"
$expectedFileComponentGuidSeed = Get-DeterministicGuid `
    -Identity "ComponentSeed|RuntimeFiles|$ExpectedArchitecture"
if ([string]::IsNullOrWhiteSpace($ExpectedProductCode)) {
    $ExpectedProductCode = Get-DeterministicProductCode `
        -Architecture $ExpectedArchitecture `
        -ProductVersion $ExpectedVersion `
        -ProductFlavor $ExpectedFlavor
}
if (-not [string]::IsNullOrWhiteSpace($ValidationMetadataPath)) {
    $validationMetadata = Get-Content -LiteralPath $ValidationMetadataPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ($validationMetadata.Schema -cne 'WireSockUI-Msi-Validation-v1' -or
        $validationMetadata.ProductName -cne 'WireSock UI' -or
        $validationMetadata.ProductVersion -cne $ExpectedVersion -or
        $validationMetadata.ProductCode -cne $ExpectedProductCode -or
        $validationMetadata.UpgradeCode -cne $expectedUpgradeCode -or
        $validationMetadata.Architecture -cne $ExpectedArchitecture -or
        $validationMetadata.Flavor -cne $ExpectedFlavor -or
        $validationMetadata.SecurityComponentGuid -cne $expectedSecurityComponentGuid -or
        $validationMetadata.ShortcutComponentGuid -cne $expectedShortcutComponentGuid -or
        $validationMetadata.DesktopShortcutComponentGuid -cne $expectedDesktopShortcutComponentGuid -or
        $validationMetadata.RuntimeHostComponentGuid -cne $expectedRuntimeHostComponentGuid -or
        $validationMetadata.FileComponentGuidSeed -cne $expectedFileComponentGuidSeed) {
        throw 'Validation metadata does not match the requested MSI identity.'
    }

    $seenMetadataPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [Int64]$metadataTotalBytes = 0
    foreach ($file in @($validationMetadata.Files)) {
        $metadataPath = [string]$file.Path
        $metadataSegments = $metadataPath.Split('/')
        if ([string]::IsNullOrWhiteSpace($metadataPath) -or
            $metadataPath.Contains('\') -or
            $metadataPath.StartsWith('/', [StringComparison]::Ordinal) -or
            $metadataPath.EndsWith('/', [StringComparison]::Ordinal) -or
            $metadataPath.Contains(':') -or
            @($metadataSegments | Where-Object {
                [string]::IsNullOrWhiteSpace($_) -or
                $_ -eq '.' -or
                $_ -eq '..' -or
                $_.EndsWith('.', [StringComparison]::Ordinal) -or
                $_.EndsWith(' ', [StringComparison]::Ordinal) -or
                $_.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0
            }).Count -ne 0 -or
            $file.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            [Int64]$file.Size -lt 0 -or
            [Int64]$file.Size -gt $maximumPayloadFileBytes -or
            -not $seenMetadataPaths.Add($metadataPath)) {
            throw "Validation metadata contains an invalid file record for '$($file.Path)'."
        }
        if ($metadataTotalBytes -gt $maximumPayloadBytes - [Int64]$file.Size) {
            throw 'Validation metadata describes a payload larger than 2 GiB.'
        }
        $metadataTotalBytes += [Int64]$file.Size
        $metadataFiles += $file
        $metadataByPath[$metadataPath] = $file
    }
    if ($metadataFiles.Count -lt 3 -or $metadataFiles.Count -gt $maximumPayloadEntries) {
        throw "Validation metadata contains an invalid file count: $($metadataFiles.Count)."
    }
}

try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = Invoke-ComMethod -Instance $installer -Name 'OpenDatabase' -Arguments @($resolvedMsiPath, 0)

    if ((Get-MsiProperty -Name 'ProductName') -cne 'WireSock UI') {
        throw 'Unexpected ProductName.'
    }
    if ((Get-MsiProperty -Name 'Manufacturer') -cne 'WireSock Foundation') {
        throw 'Unexpected Manufacturer.'
    }
    if ((Get-MsiProperty -Name 'ProductVersion') -cne $ExpectedVersion) {
        throw 'The MSI ProductVersion does not match the requested version.'
    }
    if ((Get-MsiProperty -Name 'ProductCode') -cne $ExpectedProductCode) {
        throw 'The MSI ProductCode is not the deterministic requested value.'
    }
    if ((Get-MsiProperty -Name 'UpgradeCode') -cne $expectedUpgradeCode) {
        throw 'The MSI UpgradeCode changed; this would break major upgrades.'
    }
    if ((Get-MsiProperty -Name 'ALLUSERS') -cne '1') {
        throw 'The MSI is not authored as a per-machine ALLUSERS package.'
    }
    if ((Get-MsiProperty -Name 'WIRESOCKUIARCHITECTURE') -cne $ExpectedArchitecture) {
        throw 'The MSI architecture identity does not match the requested architecture.'
    }
    if ((Get-MsiProperty -Name 'WIRESOCKUIFLAVOR') -cne $ExpectedFlavor) {
        throw 'The MSI flavor identity does not match the requested flavor.'
    }
    if ((Get-MsiProperty -Name 'ARPPRODUCTICON') -cne 'WireSockUI.ico') {
        throw 'The Add/Remove Programs icon identity is not stable.'
    }
    $expectedProperties = @{
        ALLUSERS = '1'
        WIRESOCKUIARCHITECTURE = $ExpectedArchitecture
        WIRESOCKUIFLAVOR = $ExpectedFlavor
        ARPPRODUCTICON = 'WireSockUI.ico'
        Manufacturer = 'WireSock Foundation'
        ProductCode = $ExpectedProductCode
        ProductLanguage = '1033'
        ProductName = 'WireSock UI'
        ProductVersion = $ExpectedVersion
        UpgradeCode = $expectedUpgradeCode
        DefaultUIFont = 'WixUI_Font_Normal'
        ErrorDialog = 'ErrorDlg'
        WixUIRMOption = 'UseRM'
        SecureCustomProperties =
            'BURNMSIMODIFY;BURNMSIREPAIR;BURNMSIUNINSTALL;NETFRAMEWORK472RELEASE;WIX_DOWNGRADE_DETECTED;WIX_UPGRADE_DETECTED'
    }
    $propertyRows = @(Get-MsiRows -Sql 'SELECT * FROM `Property`')
    $seenProperties = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    foreach ($propertyRow in $propertyRows) {
        $propertyName = [string]$propertyRow[0]
        if (-not $expectedProperties.ContainsKey($propertyName) -or
            -not $seenProperties.Add($propertyName) -or
            [string]$propertyRow[1] -cne [string]$expectedProperties[$propertyName]) {
            throw "MSI Property table contains unexpected or mismatched property '$propertyName'."
        }
    }
    if ($seenProperties.Count -ne $expectedProperties.Count) {
        throw 'MSI Property table is missing one or more required properties.'
    }

    $summaryInformation = $null
    try {
        $summaryInformation = Get-ComProperty `
            -Instance $installer `
            -Name 'SummaryInformation' `
            -Arguments @($resolvedMsiPath, 0)
        $template = [string](Get-ComProperty -Instance $summaryInformation -Name 'Property' -Arguments @(7))
        $expectedTemplateArchitecture = switch ($ExpectedArchitecture) {
            'x86' { 'Intel' }
            'x64' { 'x64' }
            'arm64' { 'Arm64' }
        }
        if ($template -cne ($expectedTemplateArchitecture + ';1033')) {
            throw "MSI summary template '$template' does not target $ExpectedArchitecture."
        }
        $summaryCodePage = [int](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(1))
        $summaryTitle = [string](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(2))
        $summarySubject = [string](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(3))
        $summaryAuthor = [string](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(4))
        $summaryKeywords = [string](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(5))
        $summaryComments = [string](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(6))
        $minimumInstallerVersion = [int](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(14))
        $summaryWordCount = [int](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(15))
        $creatingApplication = [string](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(18))
        $summarySecurity = [int](Get-ComProperty `
            -Instance $summaryInformation -Name 'Property' -Arguments @(19))
        if ($summaryCodePage -ne 1252 -or
            $summaryTitle -cne 'Installation Database' -or
            $summarySubject -cne 'WireSock UI per-machine installer' -or
            $summaryAuthor -cne 'WireSock Foundation' -or
            $summaryKeywords -cne 'Installer' -or
            $summaryComments -cne 'Installs the architecture-specific WireSock UI runtime payload.' -or
            $minimumInstallerVersion -ne 500 -or
            $summaryWordCount -ne 2 -or
            $creatingApplication -cne 'WiX Toolset (6.0.2.0)' -or
            $summarySecurity -ne 2) {
            throw 'MSI SummaryInformation differs from the exact compressed per-machine WiX 6.0.2 package policy.'
        }
    }
    finally {
        if ($null -ne $summaryInformation) {
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject($summaryInformation) | Out-Null
        }
    }

    $installFolderRows = @(Get-MsiRows -Sql "SELECT ``Directory_Parent``, ``DefaultDir`` FROM ``Directory`` WHERE ``Directory``='WireSockInstallFolder'")
    if ($installFolderRows.Count -ne 1 -or
        [string]$installFolderRows[0][0] -cne 'ProgramFiles6432Folder' -or
        (Get-LongMsiName -Value ([string]$installFolderRows[0][1])) -cne 'WireSock Foundation WireSock UI') {
        throw 'The private install folder is not the stable vendor-owned WireSock UI directory.'
    }

    # Schema order: UpgradeCode, VersionMin, VersionMax, Language,
    # Attributes, Remove, ActionProperty.
    $upgradeRows = @(Get-MsiRows -Sql 'SELECT * FROM `Upgrade`')
    if ($upgradeRows.Count -ne 2) {
        throw 'Expected exactly one major-upgrade row and one downgrade-blocking Upgrade table row.'
    }
    $upgradeDetectionRows = @($upgradeRows | Where-Object {
        [string]$_[0] -ceq $expectedUpgradeCode -and
        [string]$_[1] -eq '' -and
        [string]$_[2] -ceq $ExpectedVersion -and
        [string]$_[3] -eq '' -and
        [int]$_[4] -eq 513 -and
        [string]$_[5] -eq '' -and
        [string]$_[6] -ceq 'WIX_UPGRADE_DETECTED'
    })
    $downgradeDetectionRows = @($upgradeRows | Where-Object {
        [string]$_[0] -ceq $expectedUpgradeCode -and
        [string]$_[1] -ceq $ExpectedVersion -and
        [string]$_[2] -eq '' -and
        [string]$_[3] -eq '' -and
        [int]$_[4] -eq 2 -and
        [string]$_[5] -eq '' -and
        [string]$_[6] -ceq 'WIX_DOWNGRADE_DETECTED'
    })
    if ($upgradeDetectionRows.Count -ne 1 -or $downgradeDetectionRows.Count -ne 1) {
        $upgradeDescription = (
            $upgradeRows |
                ForEach-Object {
                    "UpgradeCode='$($_[0])', VersionMin='$($_[1])', VersionMax='$($_[2])', Attributes='$($_[4])', ActionProperty='$($_[6])'"
                }
        ) -join '; '
        throw "Upgrade table does not implement same-version replacement and newer-version downgrade blocking exactly: $upgradeDescription"
    }

    # SELECT * avoids Windows Installer SQL's parser ambiguity around the
    # RegLocator.Key column name. Schema order is Signature_, Root, Key, Name,
    # Type as defined by MSI 5.
    $registrySearchRows = @(Get-MsiRows -Sql 'SELECT * FROM `RegLocator`')
    $frameworkSearchRows = @(
        $registrySearchRows |
            Where-Object {
                [string]$_[0] -ceq 'NetFramework472ReleaseSearch'
            }
    )
    if ($frameworkSearchRows.Count -ne 1 -or
        [string]$frameworkSearchRows[0][0] -cne 'NetFramework472ReleaseSearch' -or
        [int]$frameworkSearchRows[0][1] -ne 2 -or
        [string]$frameworkSearchRows[0][2] -cne 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -or
        [string]$frameworkSearchRows[0][3] -cne 'Release' -or
        [int]$frameworkSearchRows[0][4] -ne 2) {
        throw 'MSI does not search the documented 32-bit .NET Framework release key.'
    }
    if ($registrySearchRows.Count -ne 1) {
        throw 'MSI contains an unexpected registry search in addition to the .NET Framework release check.'
    }
    $appSearchRows = @(Get-MsiRows -Sql 'SELECT * FROM `AppSearch`')
    $frameworkAppSearchRows = @(
        $appSearchRows |
            Where-Object {
                [string]$_[0] -ceq 'NETFRAMEWORK472RELEASE' -and
                [string]$_[1] -ceq 'NetFramework472ReleaseSearch'
            }
    )
    if ($appSearchRows.Count -ne 1 -or
        $frameworkAppSearchRows.Count -ne 1) {
        throw 'MSI AppSearch table differs from the expected .NET Framework registry search.'
    }
    if (@(Get-MsiRows -Sql 'SELECT * FROM `Signature`').Count -ne 0) {
        throw 'MSI Signature table unexpectedly contains file-search signatures.'
    }

    # Condition is also an MSI SQL keyword, so select the complete two-column
    # LaunchCondition row in schema order (Condition, Description).
    $allLaunchConditionRows = @(Get-MsiRows -Sql 'SELECT * FROM `LaunchCondition`')
    $frameworkConditionRows = @(
        $allLaunchConditionRows |
            Where-Object {
                [string]$_[0] -like 'Installed OR NETFRAMEWORK472RELEASE*'
            }
    )
    $expectedFrameworkRelease = if ($ExpectedArchitecture -eq 'arm64') {
        '#533320'
    }
    else {
        '#461808'
    }
    $expectedFrameworkMessage = if ($ExpectedArchitecture -eq 'arm64') {
        'WireSock UI for ARM64 requires Microsoft .NET Framework 4.8.1 or later.'
    }
    else {
        'WireSock UI requires Microsoft .NET Framework 4.7.2 or later.'
    }
    if ($frameworkConditionRows.Count -ne 1 -or
        [string]$frameworkConditionRows[0][0] -cne "Installed OR NETFRAMEWORK472RELEASE >= `"$expectedFrameworkRelease`"" -or
        [string]$frameworkConditionRows[0][1] -cne $expectedFrameworkMessage) {
        $actualFrameworkConditions = (
            $frameworkConditionRows |
                ForEach-Object { "Condition='$($_[0])', Description='$($_[1])'" }
        ) -join '; '
        throw "MSI does not contain the exact $ExpectedArchitecture .NET Framework launch condition: $actualFrameworkConditions"
    }
    $downgradeConditionRows = @(
        $allLaunchConditionRows |
            Where-Object {
                [string]$_[0] -ceq 'NOT WIX_DOWNGRADE_DETECTED' -and
                [string]$_[1] -ceq 'A newer version of [ProductName] is already installed.'
            }
    )
    $expectedWindowsCondition = if ($ExpectedFlavor -eq 'uwp') {
        'Installed OR VersionNT >= 603'
    }
    else {
        'Installed OR VersionNT >= 603 OR (VersionNT = 601 AND ServicePackLevel >= 1)'
    }
    $expectedWindowsMessage = if ($ExpectedFlavor -eq 'uwp') {
        'WireSock UI UWP requires Windows 8.1 or later.'
    }
    else {
        'WireSock UI requires Windows 7 SP1, Windows 8.1, or later.'
    }
    $windowsConditionRows = @(
        $allLaunchConditionRows |
            Where-Object {
                [string]$_[0] -ceq $expectedWindowsCondition -and
                [string]$_[1] -ceq $expectedWindowsMessage
            }
    )
    if ($allLaunchConditionRows.Count -ne 3 -or
        $downgradeConditionRows.Count -ne 1 -or
        $windowsConditionRows.Count -ne 1) {
        throw 'MSI launch conditions contain unexpected rows or do not block a detected downgrade.'
    }

    # Schema order: Action, Condition, Sequence.
    $sequenceRows = @(
        Get-MsiRows -Sql 'SELECT * FROM `InstallExecuteSequence`' |
            Where-Object {
                [string]$_[0] -in @(
                    'InstallInitialize',
                    'RemoveExistingProducts',
                    'InstallFiles')
            }
    )
    $sequences = @{}
    foreach ($row in $sequenceRows) {
        $sequences[[string]$row[0]] = [int]$row[2]
    }
    if (-not $sequences.ContainsKey('InstallInitialize') -or
        -not $sequences.ContainsKey('RemoveExistingProducts') -or
        -not $sequences.ContainsKey('InstallFiles') -or
        $sequences['RemoveExistingProducts'] -le $sequences['InstallInitialize'] -or
        $sequences['RemoveExistingProducts'] -ge $sequences['InstallFiles']) {
        throw 'RemoveExistingProducts is not scheduled transactionally before new files are installed.'
    }
    Assert-ExactMsiSequenceTable -TableName 'AdminExecuteSequence' -ExpectedActions @{
        CostInitialize = 800
        FileCost = 900
        CostFinalize = 1000
        InstallValidate = 1400
        InstallInitialize = 1500
        InstallAdminPackage = 3900
        InstallFiles = 4000
        InstallFinalize = 6600
    }
    Assert-ExactMsiSequenceTable -TableName 'AdminUISequence' -ExpectedActions @{
        CostInitialize = 800
        FileCost = 900
        CostFinalize = 1000
        ExecuteAction = 1300
        ExitDialog = -1
        FatalError = -3
        UserExit = -2
    }
    Assert-ExactMsiSequenceTable -TableName 'AdvtExecuteSequence' -ExpectedActions @{
        CostInitialize = 800
        CostFinalize = 1000
        InstallValidate = 1400
        InstallInitialize = 1500
        InstallFinalize = 6600
        CreateShortcuts = 4500
        PublishFeatures = 6300
        PublishProduct = 6400
    }
    Assert-ExactMsiSequenceTable -TableName 'InstallUISequence' -ExpectedActions @{
        AppSearch = 50
        CostInitialize = 800
        FileCost = 900
        CostFinalize = 1000
        ExecuteAction = 1300
        ExitDialog = -1
        FatalError = -3
        FindRelatedProducts = 25
        LaunchConditions = 100
        MaintenanceWelcomeDlg = @{
            Sequence = 1298
            Condition = 'Installed AND NOT RESUME AND NOT Preselected AND NOT PATCH'
        }
        MigrateFeatureStates = 1200
        PrepareDlg = 49
        ProgressDlg = 1299
        ResumeDlg = @{
            Sequence = 1296
            Condition = 'Installed AND (RESUME OR Preselected)'
        }
        UserExit = -2
        ValidateProductID = 700
        WelcomeDlg = @{
            Sequence = 1297
            Condition = 'NOT Installed OR PATCH'
        }
    }
    Assert-ExactMsiSequenceTable -TableName 'InstallExecuteSequence' -ExpectedActions @{
        AppSearch = 50
        CostInitialize = 800
        FileCost = 900
        CostFinalize = 1000
        InstallValidate = 1400
        InstallInitialize = 1500
        InstallFiles = 4000
        InstallFinalize = 6600
        CreateShortcuts = 4500
        PublishFeatures = 6300
        PublishProduct = 6400
        FindRelatedProducts = 25
        LaunchConditions = 100
        MigrateFeatureStates = 1200
        ValidateProductID = 700
        ProcessComponents = 1600
        UnpublishFeatures = 1800
        RemoveRegistryValues = 2600
        RemoveShortcuts = 3200
        RemoveFiles = 3500
        RemoveFolders = 3600
        CreateFolders = 3700
        WriteRegistryValues = 5000
        RegisterUser = 6000
        RegisterProduct = 6100
        RemoveExistingProducts = 1501
    }

    # Schema order: DiskId, LastSequence, DiskPrompt, Cabinet, VolumeLabel,
    # Source. The package is deliberately a single embedded cabinet so there is
    # no external-media trust boundary or multi-cab continuation state.
    $mediaRows = @(Get-MsiRows -Sql 'SELECT * FROM `Media`')
    if ($mediaRows.Count -ne 1 -or
        [int]$mediaRows[0][0] -ne 1 -or
        [string]::IsNullOrEmpty([string]$mediaRows[0][1]) -or
        -not [string]::IsNullOrEmpty([string]$mediaRows[0][2]) -or
        [string]$mediaRows[0][3] -cnotmatch '^#[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
        -not [string]::IsNullOrEmpty([string]$mediaRows[0][4]) -or
        -not [string]::IsNullOrEmpty([string]$mediaRows[0][5])) {
        throw 'MSI media authoring must contain exactly one canonical embedded cabinet.'
    }
    $embeddedCabinetStreamName = ([string]$mediaRows[0][3]).Substring(1)

    $tableRows = @(Get-MsiRows -Sql 'SELECT * FROM `_Tables`')
    $expectedTableNames = @(
        '_Validation',
        'AdminExecuteSequence',
        'AdminUISequence',
        'AdvtExecuteSequence',
        'AppSearch',
        'Binary',
        'CheckBox',
        'Component',
        'Control',
        'ControlCondition',
        'ControlEvent',
        'CreateFolder',
        'Directory',
        'Dialog',
        'EventMapping',
        'Feature',
        'FeatureComponents',
        'File',
        'Icon',
        'InstallExecuteSequence',
        'InstallUISequence',
        'LaunchCondition',
        'ListBox',
        'Media',
        'MsiLockPermissionsEx',
        'MsiShortcutProperty',
        'Property',
        'Registry',
        'RegLocator',
        'RadioButton',
        'Shortcut',
        'Signature',
        'TextStyle',
        'UIText',
        'Upgrade'
    )
    $actualTableNames = @($tableRows | ForEach-Object { [string]$_[0] })
    $missingTableNames = @(
        $expectedTableNames |
            Where-Object { $_ -cnotin $actualTableNames }
    )
    $unexpectedTableNames = @(
        $actualTableNames |
            Where-Object { $_ -cnotin $expectedTableNames }
    )
    if ($actualTableNames.Count -ne $expectedTableNames.Count -or
        $missingTableNames.Count -ne 0 -or
        $unexpectedTableNames.Count -ne 0) {
        throw "MSI table inventory differs from the closed-world allowlist. Missing: $($missingTableNames -join ', '); unexpected: $($unexpectedTableNames -join ', ')."
    }

    $expectedUiBinaryNames = @(
        'WixUI_Bmp_Banner',
        'WixUI_Bmp_Dialog',
        'WixUI_Bmp_New',
        'WixUI_Bmp_Up',
        'WixUI_Ico_Exclam',
        'WixUI_Ico_Info'
    )
    $uiBinaryNames = @(
        Get-MsiRows -Sql 'SELECT `Name` FROM `Binary`' |
            ForEach-Object { [string]$_[0] } |
            Sort-Object
    )
    if (@(
            Compare-Object `
                -ReferenceObject $expectedUiBinaryNames `
                -DifferenceObject $uiBinaryNames `
                -CaseSensitive
        ).Count -ne 0) {
        throw 'MSI Binary table differs from the exact pinned WixUI image resources.'
    }

    $createFolderRows = @(Get-MsiRows -Sql 'SELECT * FROM `CreateFolder`')
    if ($createFolderRows.Count -lt 1 -or
        $createFolderRows.Count -gt $maximumPayloadEntries) {
        throw "MSI CreateFolder table contains an invalid number of rows: $($createFolderRows.Count)."
    }
    $createFolderComponentByDirectory = @{}
    foreach ($createFolderRow in $createFolderRows) {
        $directoryId = [string]$createFolderRow[0]
        $componentId = [string]$createFolderRow[1]
        if ($directoryId -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
            $componentId -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
            $createFolderComponentByDirectory.ContainsKey($directoryId)) {
            throw 'MSI CreateFolder table contains a duplicate or noncanonical row.'
        }
        $createFolderComponentByDirectory[$directoryId] = $componentId
    }
    if (-not $createFolderComponentByDirectory.ContainsKey(
            'WireSockInstallFolder') -or
        [string]$createFolderComponentByDirectory[
            'WireSockInstallFolder'] -cne
            'ApplicationDirectorySecurity') {
        throw 'The protected application directory is not owned by its dedicated component.'
    }

    $fileIdentityRows = @(Get-MsiRows -Sql 'SELECT `File` FROM `File`')
    $fileIdsForPermissions =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
    foreach ($fileIdentityRow in $fileIdentityRows) {
        $fileId = [string]$fileIdentityRow[0]
        if ($fileId -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
            -not $fileIdsForPermissions.Add($fileId)) {
            throw "MSI File table contains duplicate or noncanonical identifier '$fileId'."
        }
    }

    # WiX/MSI 5 schema order: MsiLockPermissionsEx, LockObject, Table,
    # SDDLText, Condition. Every installed file and explicitly created
    # directory must have one exact protected descriptor so repair normalizes
    # pre-existing ACLs instead of relying only on one-time inheritance.
    $permissionRows = @(Get-MsiRows -Sql 'SELECT * FROM `MsiLockPermissionsEx`')
    $expectedDirectorySddl = 'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)'
    $expectedFileSddl = 'O:BAG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;BU)'
    if ($permissionRows.Count -ne
        $fileIdsForPermissions.Count +
            $createFolderComponentByDirectory.Count) {
        throw 'MSI permissions do not cover every File and CreateFolder row exactly once.'
    }
    $permissionIds =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
    $securedFileIds =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
    $securedDirectoryIds =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
    $filePermissionIdByFileId = @{}
    $directoryPermissionIdByDirectoryId = @{}
    foreach ($permissionRow in $permissionRows) {
        $permissionId = [string]$permissionRow[0]
        $lockObject = [string]$permissionRow[1]
        $tableName = [string]$permissionRow[2]
        $sddl = [string]$permissionRow[3]
        $condition = [string]$permissionRow[4]
        if ($permissionId -cnotmatch
                '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
            -not $permissionIds.Add($permissionId) -or
            -not [string]::IsNullOrEmpty($condition)) {
            throw "MSI permission '$permissionId' has invalid identity, condition, or duplication."
        }

        if ($tableName -ceq 'File') {
            if (-not $fileIdsForPermissions.Contains($lockObject) -or
                -not $securedFileIds.Add($lockObject) -or
                $sddl -cne $expectedFileSddl) {
                throw "MSI file permission '$permissionId' has an unknown target, duplicate target, or unexpected SDDL."
            }
            $filePermissionIdByFileId[$lockObject] = $permissionId
        }
        elseif ($tableName -ceq 'CreateFolder') {
            if (-not $createFolderComponentByDirectory.ContainsKey(
                    $lockObject) -or
                -not $securedDirectoryIds.Add($lockObject) -or
                $sddl -cne $expectedDirectorySddl) {
                throw "MSI directory permission '$permissionId' has an unknown target, duplicate target, or unexpected SDDL."
            }
            $directoryPermissionIdByDirectoryId[$lockObject] =
                $permissionId
            if ($lockObject -ceq 'WireSockInstallFolder' -and
                $permissionId -cne 'ApplicationDirectoryPermission') {
                throw 'The application-directory permission identity changed unexpectedly.'
            }
        }
        else {
            throw "MSI permission '$permissionId' targets unexpected table '$tableName'."
        }
    }
    if ($securedFileIds.Count -ne $fileIdsForPermissions.Count -or
        $securedDirectoryIds.Count -ne
            $createFolderComponentByDirectory.Count) {
        throw 'MSI permission coverage is incomplete.'
    }

    # Schema order begins Shortcut, Directory_, Name, Component_, Target,
    # Arguments, Description, Hotkey, Icon_, IconIndex, ShowCmd, WkDir.
    $shortcutRows = @(Get-MsiRows -Sql 'SELECT * FROM `Shortcut`')
    $expectedShortcuts = @{
        WireSockStartMenuShortcut = @{
            Directory = 'ProgramMenuFolder'
            Component = 'StartMenuShortcutComponent'
        }
        WireSockDesktopShortcut = @{
            Directory = 'DesktopFolder'
            Component = 'DesktopShortcutComponent'
        }
    }
    $seenShortcuts = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    foreach ($shortcutRow in $shortcutRows) {
        $shortcutId = [string]$shortcutRow[0]
        if (-not $expectedShortcuts.ContainsKey($shortcutId) -or
            -not $seenShortcuts.Add($shortcutId) -or
            [string]$shortcutRow[1] -cne
                [string]$expectedShortcuts[$shortcutId].Directory -or
            (Get-LongMsiName -Value ([string]$shortcutRow[2])) -cne 'WireSock UI' -or
            [string]$shortcutRow[3] -cne
                [string]$expectedShortcuts[$shortcutId].Component -or
            [string]$shortcutRow[4] -cne '[WireSockInstallFolder]WireSockUI.exe' -or
            -not [string]::IsNullOrEmpty([string]$shortcutRow[5]) -or
            [string]$shortcutRow[8] -cne 'WireSockUI.ico' -or
            [int]$shortcutRow[9] -ne 0 -or
            -not [string]::IsNullOrEmpty([string]$shortcutRow[10]) -or
            [string]$shortcutRow[11] -cne 'WireSockInstallFolder') {
            throw "MSI shortcut '$shortcutId' differs from its exact non-advertised shell shortcut invariant."
        }
    }
    if ($shortcutRows.Count -ne $expectedShortcuts.Count -or
        $seenShortcuts.Count -ne $expectedShortcuts.Count) {
        $shortcutDescription = (
            $shortcutRows |
                ForEach-Object {
                    $row = $_
                    (0..($row.Count - 1) | ForEach-Object { "[$_]='$($row[$_])'" }) -join ', '
                }
        ) -join '; '
        throw "MSI does not contain exactly the Start menu and desktop WireSock UI shortcuts: $shortcutDescription"
    }

    # Schema order: MsiShortcutProperty, Shortcut_, PropertyKey,
    # PropVariantValue. The installer-owned Start-menu shortcut is the sole
    # registration point for the UWP notification AppUserModelID.
    $shortcutPropertyRows = @(Get-MsiRows -Sql 'SELECT * FROM `MsiShortcutProperty`')
    if ($shortcutPropertyRows.Count -ne 1 -or
        [string]$shortcutPropertyRows[0][0] -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
        [string]$shortcutPropertyRows[0][1] -cne 'WireSockStartMenuShortcut' -or
        [string]$shortcutPropertyRows[0][2] -cne 'System.AppUserModel.ID' -or
        [string]$shortcutPropertyRows[0][3] -cne 'WireSock.Foundation.WireSock.UI') {
        throw 'MSI notification AppUserModelID authoring differs from its exact installer-owned shortcut invariant.'
    }

    # Schema order: Registry, Root, Key, Name, Value, Component_.
    $registryRows = @(Get-MsiRows -Sql 'SELECT * FROM `Registry`')
    $expectedRegistryValueByComponent = @{
        StartMenuShortcutComponent = 'StartMenuShortcut'
        DesktopShortcutComponent = 'DesktopShortcut'
    }
    $registryKeyPathByComponent = @{}
    foreach ($registryRow in $registryRows) {
        $componentId = [string]$registryRow[5]
        if (-not $expectedRegistryValueByComponent.ContainsKey($componentId) -or
            $registryKeyPathByComponent.ContainsKey($componentId) -or
            [string]$registryRow[0] -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
            [int]$registryRow[1] -ne 2 -or
            [string]$registryRow[2] -cne 'Software\WireSock Foundation\WireSock UI' -or
            [string]$registryRow[3] -cne
                [string]$expectedRegistryValueByComponent[$componentId] -or
            [string]$registryRow[4] -cne '#1') {
            throw "MSI shortcut registry key path for '$componentId' differs from its exact invariant."
        }
        $registryKeyPathByComponent[$componentId] = [string]$registryRow[0]
    }
    if ($registryRows.Count -ne $expectedRegistryValueByComponent.Count -or
        $registryKeyPathByComponent.Count -ne
            $expectedRegistryValueByComponent.Count) {
        throw 'MSI Registry table differs from the two expected shortcut key-path values.'
    }

    $iconRows = @(Get-MsiRows -Sql 'SELECT `Name` FROM `Icon`')
    if ($iconRows.Count -ne 1 -or [string]$iconRows[0][0] -cne 'WireSockUI.ico') {
        throw 'MSI icon authoring is missing or contains unexpected binary resources.'
    }

    $removeFileTableRows = @(
        $tableRows |
            Where-Object { [string]$_[0] -ceq 'RemoveFile' }
    )
    if ($removeFileTableRows.Count -ne 0) {
        throw 'MSI contains unexpected file/folder removal authoring.'
    }

    $componentRows = @(Get-MsiRows -Sql 'SELECT `Component`, `ComponentId`, `Attributes` FROM `Component`')
    $componentIdentity = @{}
    $componentDirectory = @{}
    foreach ($componentRow in $componentRows) {
        $componentIdentity[[string]$componentRow[0]] = [string]$componentRow[1]
        $is64BitComponent = (([int]$componentRow[2] -band 256) -ne 0)
        if (($ExpectedArchitecture -eq 'x86' -and $is64BitComponent) -or
            ($ExpectedArchitecture -ne 'x86' -and -not $is64BitComponent)) {
            throw "Component '$($componentRow[0])' has bitness inconsistent with $ExpectedArchitecture."
        }
    }
    if ($componentIdentity['ApplicationDirectorySecurity'] -cne $expectedSecurityComponentGuid -or
        $componentIdentity['StartMenuShortcutComponent'] -cne $expectedShortcutComponentGuid -or
        $componentIdentity['DesktopShortcutComponent'] -cne
            $expectedDesktopShortcutComponentGuid) {
        throw 'Installer-owned directory and shortcut component GUIDs are not architecture-specific deterministic values.'
    }

    $directoryRows = @(Get-MsiRows -Sql 'SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`')
    $directories = @{}
    foreach ($row in $directoryRows) {
        if ($directories.ContainsKey([string]$row[0]) -or
            [string]$row[0] -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$') {
            throw "Directory table contains duplicate or noncanonical identifier '$($row[0])'."
        }
        $directories[[string]$row[0]] = [pscustomobject]@{
            Parent = [string]$row[1]
            Name = Get-LongMsiName -Value ([string]$row[2])
        }
    }

    function Get-RelativeDirectory {
        param([string]$DirectoryId)

        $segments = New-Object 'System.Collections.Generic.List[string]'
        $current = $DirectoryId
        $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        while (-not [string]::Equals($current, 'WireSockInstallFolder', [StringComparison]::Ordinal)) {
            if (-not $visited.Add($current)) {
                throw "Directory table cycle at '$current'."
            }
            if (-not $directories.ContainsKey($current)) {
                throw "Unknown Directory table identifier '$current'."
            }

            $directory = $directories[$current]
            if (-not [string]::IsNullOrEmpty($directory.Name) -and $directory.Name -ne '.') {
                $segments.Insert(0, $directory.Name)
            }
            $current = $directory.Parent
        }

        return [string]::Join([IO.Path]::DirectorySeparatorChar, $segments)
    }

    # Component schema order: Component, ComponentId, Directory_, Attributes,
    # Condition, KeyPath. Read it separately because MSI SQL joins are not
    # supported consistently by the Windows Installer automation interface.
    $completeComponentRows = @(Get-MsiRows -Sql 'SELECT * FROM `Component`')
    foreach ($componentRow in $completeComponentRows) {
        $componentDirectory[[string]$componentRow[0]] = [string]$componentRow[2]
    }

    # File schema begins File, Component_, FileName.
    $fileRows = @(Get-MsiRows -Sql 'SELECT * FROM `File`')
    if ($fileRows.Count -lt 3 -or $fileRows.Count -gt $maximumPayloadEntries) {
        throw "MSI File table contains an invalid number of rows: $($fileRows.Count)."
    }
    $actualFiles = @()
    $fileIdToRelativePath = @{}
    $fileIdToSize = @{}
    $fileIdToVersion = @{}
    $fileIdToComponent = @{}
    $companionParentByFileId = @{}
    $payloadComponentIds =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
    $seenFileSequences = New-Object 'System.Collections.Generic.HashSet[int]'
    $seenInstalledPaths = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase)
    $runtimeHostFileId = 'WireSockRuntimeHostFile'
    $runtimeConfigFileId = 'WireSockRuntimeConfigFile'
    $sawRuntimeHostFile = $false
    $sawRuntimeConfigFile = $false
    [Int64]$fileTableTotalBytes = 0
    foreach ($row in $fileRows) {
        $fileId = [string]$row[0]
        $fileName = Get-LongMsiName -Value ([string]$row[2])
        $fileComponent = [string]$row[1]
        if (-not $componentDirectory.ContainsKey($fileComponent)) {
            throw "File table references unknown component '$fileComponent'."
        }
        $relativeDirectory = Get-RelativeDirectory -DirectoryId $componentDirectory[$fileComponent]
        $relativePath = if ([string]::IsNullOrEmpty($relativeDirectory)) {
            $fileName
        }
        else {
            Join-Path $relativeDirectory $fileName
        }
        $manifestRelativePath = $relativePath.Replace('\', '/')
        if ($manifestRelativePath -ceq 'WireSockUI.exe') {
            if ($fileId -cne $runtimeHostFileId -or
                $fileComponent -cne $runtimeHostFileId -or
                $sawRuntimeHostFile) {
                throw 'The native runtime host is not the one exact component key-path file.'
            }
            $sawRuntimeHostFile = $true
        }
        elseif ($manifestRelativePath -ceq 'WireSockUI.exe.config') {
            if ($fileId -cne $runtimeConfigFileId -or
                $fileComponent -cne $runtimeHostFileId -or
                $sawRuntimeConfigFile) {
                throw 'The runtime configuration is not paired with the native host component.'
            }
            $sawRuntimeConfigFile = $true
        }
        if ($fileIdToRelativePath.ContainsKey($fileId)) {
            throw "File table contains duplicate identifier '$fileId'."
        }
        if ($fileId -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$') {
            throw "File table identifier '$fileId' is not canonical."
        }
        if (-not $seenInstalledPaths.Add($manifestRelativePath)) {
            throw "File table installs more than one file at '$manifestRelativePath'."
        }

        [Int64]$declaredSize = 0
        if (-not [Int64]::TryParse(
                [string]$row[3],
                [Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$declaredSize) -or
            $declaredSize -lt 0 -or
            $declaredSize -gt $maximumPayloadFileBytes) {
            throw "File table entry '$manifestRelativePath' has invalid declared size '$($row[3])'."
        }
        if ($fileTableTotalBytes -gt $maximumPayloadBytes - $declaredSize) {
            throw 'MSI File table describes a payload larger than 2 GiB.'
        }
        $fileTableTotalBytes += $declaredSize

        $fileVersion = [string]$row[4]
        $fileLanguage = [string]$row[5]
        if ($manifestRelativePath -ceq 'WireSockUI.exe.config') {
            if ($fileVersion -cne $runtimeHostFileId -or
                -not [string]::IsNullOrEmpty($fileLanguage)) {
                throw 'The runtime configuration is not an exact companion of the versioned native host.'
            }
        }
        if ([string]::IsNullOrEmpty($fileVersion)) {
            throw (
                "Manifest-bound runtime file '$manifestRelativePath' is " +
                'standalone and unversioned. Product-owned unversioned files ' +
                'must be companions of a versioned file so ordinary MSI repair ' +
                'cannot preserve tampered bytes.')
        }
        elseif ($fileVersion -cmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
            if ($fileLanguage -cnotmatch '^(0|1033)$') {
                throw "Versioned file '$manifestRelativePath' uses noncanonical language metadata."
            }
            if ($fileComponent -cne $fileId) {
                throw "Versioned file '$fileId' is not the key-path file of its identically named component."
            }
        }
        elseif ($fileVersion -cmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$') {
            if (-not [string]::IsNullOrEmpty($fileLanguage) -or
                $companionParentByFileId.ContainsKey($fileId)) {
                throw "Companion file '$manifestRelativePath' has invalid language or duplicate parent metadata."
            }
            $companionParentByFileId[$fileId] = $fileVersion
        }
        else {
            throw "File '$manifestRelativePath' uses noncanonical version, companion, or language metadata."
        }
        if ([int]$row[6] -ne 512) {
            throw "File '$manifestRelativePath' is not authored as an exact vital file."
        }

        [int]$fileSequence = 0
        if (-not [int]::TryParse(
                [string]$row[7],
                [Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$fileSequence) -or
            $fileSequence -lt 1 -or
            $fileSequence -gt $fileRows.Count -or
            -not $seenFileSequences.Add($fileSequence)) {
            throw "File table entry '$manifestRelativePath' has an invalid or duplicate media sequence."
        }

        if ($metadataFiles.Count -gt 0) {
            if (-not $metadataByPath.ContainsKey($manifestRelativePath)) {
                throw "MSI File table contains '$manifestRelativePath', which is absent from validation metadata."
            }
            if ($declaredSize -ne [Int64]$metadataByPath[$manifestRelativePath].Size) {
                throw "MSI File table size for '$manifestRelativePath' differs from validation metadata."
            }
        }

        $fileIdToRelativePath[$fileId] = $manifestRelativePath
        $fileIdToSize[$fileId] = $declaredSize
        $fileIdToVersion[$fileId] = $fileVersion
        $fileIdToComponent[$fileId] = $fileComponent
        [void]$payloadComponentIds.Add($fileComponent)
        $actualFiles += $relativePath
    }

    foreach ($fileId in $fileIdToRelativePath.Keys) {
        $manifestPath = [string]$fileIdToRelativePath[$fileId]
        $expectedFilePermissionId = if (
            $manifestPath -ceq 'WireSockUI.exe') {
            'WireSockRuntimeHostPermission'
        }
        elseif ($manifestPath -ceq 'WireSockUI.exe.config') {
            'WireSockRuntimeConfigPermission'
        }
        else {
            Get-DeterministicMsiIdentifier `
                -Prefix 'PayloadFilePermission_' `
                -Identity "PayloadFilePermission|$manifestPath"
        }
        if ([string]$filePermissionIdByFileId[$fileId] -cne
            $expectedFilePermissionId) {
            throw "File '$manifestPath' does not use its deterministic permission identity."
        }
    }

    $payloadDirectoryIds =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
    [void]$payloadDirectoryIds.Add('WireSockInstallFolder')
    foreach ($fileComponent in $fileIdToComponent.Values) {
        $currentDirectoryId = [string]$componentDirectory[$fileComponent]
        $visitedDirectoryIds =
            New-Object 'System.Collections.Generic.HashSet[string]' (
                [StringComparer]::Ordinal)
        while (-not [string]::Equals(
                $currentDirectoryId,
                'WireSockInstallFolder',
                [StringComparison]::Ordinal)) {
            if (-not $visitedDirectoryIds.Add($currentDirectoryId) -or
                -not $directories.ContainsKey($currentDirectoryId)) {
                throw "Payload file component '$fileComponent' has an invalid directory ancestry."
            }
            [void]$payloadDirectoryIds.Add($currentDirectoryId)
            $currentDirectoryId =
                [string]$directories[$currentDirectoryId].Parent
        }
    }
    if ($payloadDirectoryIds.Count -ne
            $createFolderComponentByDirectory.Count) {
        throw 'MSI CreateFolder rows do not match the exact payload directory tree.'
    }
    $seenPayloadDirectoryPaths =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::OrdinalIgnoreCase)
    foreach ($payloadDirectoryId in $payloadDirectoryIds) {
        if (-not $createFolderComponentByDirectory.ContainsKey(
                $payloadDirectoryId)) {
            throw "Payload directory '$payloadDirectoryId' has no protected CreateFolder row."
        }
        $expectedDirectoryPermissionId = if (
            $payloadDirectoryId -ceq 'WireSockInstallFolder') {
            'ApplicationDirectoryPermission'
        }
        else {
            $relativeDirectory = (
                Get-RelativeDirectory -DirectoryId $payloadDirectoryId
            ).Replace('\', '/')
            if (-not $seenPayloadDirectoryPaths.Add(
                    $relativeDirectory)) {
                throw "More than one Directory-table row resolves to '$relativeDirectory'."
            }
            Get-DeterministicMsiIdentifier `
                -Prefix 'PayloadDirectoryPermission_' `
                -Identity "PayloadDirectoryPermission|$relativeDirectory"
        }
        if ([string]$directoryPermissionIdByDirectoryId[
                $payloadDirectoryId] -cne
            $expectedDirectoryPermissionId) {
            throw "Payload directory '$payloadDirectoryId' does not use its deterministic permission identity."
        }
    }

    if (-not $sawRuntimeHostFile -or -not $sawRuntimeConfigFile) {
        throw 'MSI does not contain the required native-host/configuration companion pair.'
    }
    if ($seenFileSequences.Count -ne $fileRows.Count -or
        [int]$mediaRows[0][1] -ne $fileRows.Count) {
        throw 'MSI file sequences are not a complete one-based inventory in the sole embedded cabinet.'
    }
    foreach ($companionFileId in $companionParentByFileId.Keys) {
        $parentFileId = [string]$companionParentByFileId[$companionFileId]
        if (-not $fileIdToVersion.ContainsKey($parentFileId) -or
            [string]$fileIdToVersion[$parentFileId] -cnotmatch
                '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or
            [string]$fileIdToComponent[$companionFileId] -cne
                [string]$fileIdToComponent[$parentFileId]) {
            throw (
                "Companion file '$($fileIdToRelativePath[$companionFileId])' " +
                'does not share a component with one directly versioned parent.')
        }
    }

    $directorySecurityDirectoryByComponent = @{}
    foreach ($directoryId in $createFolderComponentByDirectory.Keys) {
        if ($directoryId -ceq 'WireSockInstallFolder') {
            continue
        }
        $directoryComponentId =
            [string]$createFolderComponentByDirectory[$directoryId]
        if ($directorySecurityDirectoryByComponent.ContainsKey(
                $directoryComponentId) -or
            $payloadComponentIds.Contains($directoryComponentId) -or
            $directoryComponentId -in @(
                'ApplicationDirectorySecurity',
                'DesktopShortcutComponent',
                'StartMenuShortcutComponent')) {
            throw 'A payload-directory security component is duplicated or owns unrelated resources.'
        }
        $directorySecurityDirectoryByComponent[
            $directoryComponentId] = $directoryId
    }

    $expectedComponentAttributes =
        if ($ExpectedArchitecture -eq 'x86') { 0 } else { 256 }
    if ($completeComponentRows.Count -ne
        $payloadComponentIds.Count +
            $directorySecurityDirectoryByComponent.Count +
            3) {
        throw 'MSI Component table does not contain the exact payload-file, payload-directory, and installer-owned component inventory.'
    }
    $seenComponentGuids = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase)
    $componentIds = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    $seenDirectorySecurityComponentIds =
        New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
    foreach ($componentRow in $completeComponentRows) {
        $componentId = [string]$componentRow[0]
        $componentGuid = [string]$componentRow[1]
        $componentDirectoryId = [string]$componentRow[2]
        [int]$componentAttributes = [int]$componentRow[3]
        $componentCondition = [string]$componentRow[4]
        $componentKeyPath = [string]$componentRow[5]
        if ($componentId -cnotmatch '^[A-Za-z_][A-Za-z0-9_.]{0,71}$' -or
            $componentGuid -cnotmatch '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$' -or
            -not $componentIds.Add($componentId) -or
            -not $seenComponentGuids.Add($componentGuid) -or
            -not [string]::IsNullOrEmpty($componentCondition)) {
            throw "MSI component '$componentId' has invalid identity, condition, or duplicate GUID metadata."
        }

        if ($componentId -ceq 'ApplicationDirectorySecurity') {
            if ($componentGuid -cne $expectedSecurityComponentGuid -or
                $componentDirectoryId -cne 'WireSockInstallFolder' -or
                $componentAttributes -ne $expectedComponentAttributes -or
                -not [string]::IsNullOrEmpty($componentKeyPath)) {
                throw 'The application-directory security component differs from its exact invariant.'
            }
            continue
        }
        if ($componentId -ceq 'StartMenuShortcutComponent') {
            if ($componentGuid -cne $expectedShortcutComponentGuid -or
                $componentDirectoryId -cne 'ProgramMenuFolder' -or
                $componentAttributes -ne ($expectedComponentAttributes -bor 4) -or
                $componentKeyPath -cne
                    [string]$registryKeyPathByComponent[$componentId]) {
                throw 'The Start Menu shortcut component differs from its exact invariant.'
            }
            continue
        }
        if ($componentId -ceq 'DesktopShortcutComponent') {
            if ($componentGuid -cne $expectedDesktopShortcutComponentGuid -or
                $componentDirectoryId -cne 'DesktopFolder' -or
                $componentAttributes -ne ($expectedComponentAttributes -bor 4) -or
                $componentKeyPath -cne
                    [string]$registryKeyPathByComponent[$componentId]) {
                throw 'The desktop shortcut component differs from its exact invariant.'
            }
            continue
        }

        if ($directorySecurityDirectoryByComponent.ContainsKey(
                $componentId)) {
            $directoryId =
                [string]$directorySecurityDirectoryByComponent[$componentId]
            $relativeDirectory = (
                Get-RelativeDirectory -DirectoryId $directoryId
            ).Replace('\', '/')
            $expectedDirectoryComponentId =
                Get-DeterministicMsiIdentifier `
                    -Prefix 'PayloadDirectorySecurity_' `
                    -Identity "PayloadDirectorySecurity|$relativeDirectory"
            $expectedDirectoryComponentGuid =
                Get-DeterministicGuid `
                    -Identity (
                        'Component|PayloadDirectorySecurity|' +
                        "$ExpectedArchitecture|$relativeDirectory")
            if ([string]::IsNullOrEmpty($relativeDirectory) -or
                $componentId -cne $expectedDirectoryComponentId -or
                $componentGuid -cne $expectedDirectoryComponentGuid -or
                $componentDirectoryId -cne $directoryId -or
                $componentAttributes -ne $expectedComponentAttributes -or
                -not [string]::IsNullOrEmpty($componentKeyPath) -or
                $fileIdToRelativePath.ContainsKey($componentId) -or
                -not $seenDirectorySecurityComponentIds.Add($componentId)) {
                throw "Payload-directory security component '$componentId' differs from its exact invariant."
            }
            continue
        }

        if (-not $payloadComponentIds.Contains($componentId) -or
            -not $fileIdToRelativePath.ContainsKey($componentId) -or
            [string]$fileIdToVersion[$componentId] -cnotmatch
                '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or
            $componentAttributes -ne $expectedComponentAttributes -or
            $componentKeyPath -cne $componentId) {
            throw "Payload component '$componentId' is not keyed by one directly versioned parent or is otherwise noncanonical."
        }
        if ($componentId -ceq $runtimeHostFileId -and
            $componentGuid -cne $expectedRuntimeHostComponentGuid) {
            throw 'The runtime-host component does not use its architecture-specific deterministic GUID.'
        }
        if ($componentId -cne $runtimeHostFileId) {
            $manifestPath =
                [string]$fileIdToRelativePath[$componentId]
            $expectedPayloadComponentId =
                Get-DeterministicMsiIdentifier `
                    -Prefix 'PayloadFile_' `
                    -Identity "PayloadFile|$manifestPath"
            if ($componentId -cne $expectedPayloadComponentId) {
                throw "Payload component '$componentId' does not use its installed-path identity."
            }
        }
    }
    if ($seenDirectorySecurityComponentIds.Count -ne
        $directorySecurityDirectoryByComponent.Count) {
        throw 'MSI omits one or more payload-directory security components.'
    }

    $reachableDirectoryIds = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    foreach ($componentDirectoryId in $componentDirectory.Values) {
        $currentDirectoryId = [string]$componentDirectoryId
        while (-not [string]::IsNullOrEmpty($currentDirectoryId)) {
            if (-not $directories.ContainsKey($currentDirectoryId)) {
                throw "Component directory '$currentDirectoryId' is absent from the Directory table."
            }
            if (-not $reachableDirectoryIds.Add($currentDirectoryId)) {
                break
            }
            $currentDirectoryId = [string]$directories[$currentDirectoryId].Parent
        }
    }
    if ($reachableDirectoryIds.Count -ne $directoryRows.Count) {
        throw 'MSI Directory table contains an unused or unreachable directory.'
    }

    $featureRows = @(Get-MsiRows -Sql 'SELECT * FROM `Feature`')
    $expectedFeatures = @{
        CoreFeature = @{
            Parent = ''
            Title = 'WireSock UI'
            Description = 'WireSock UI application files'
            Display = 1
            Level = 1
            Attributes = 24
        }
        StartMenuShortcutFeature = @{
            Parent = 'CoreFeature'
            Title = 'Start menu shortcut'
            Description = 'Add WireSock UI to the Start menu and enable notifications'
            Display = 2
            Level = 1
            Attributes = 8
        }
        DesktopShortcutFeature = @{
            Parent = 'CoreFeature'
            Title = 'Desktop shortcut'
            Description = 'Create a WireSock UI shortcut on the desktop'
            Display = 4
            Level = 1
            Attributes = 8
        }
    }
    $seenFeatures = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    foreach ($featureRow in $featureRows) {
        $featureId = [string]$featureRow[0]
        if (-not $expectedFeatures.ContainsKey($featureId) -or
            -not $seenFeatures.Add($featureId) -or
            [string]$featureRow[1] -cne
                [string]$expectedFeatures[$featureId].Parent -or
            [string]$featureRow[2] -cne
                [string]$expectedFeatures[$featureId].Title -or
            [string]$featureRow[3] -cne
                [string]$expectedFeatures[$featureId].Description -or
            [int]$featureRow[4] -ne
                [int]$expectedFeatures[$featureId].Display -or
            [int]$featureRow[5] -ne
                [int]$expectedFeatures[$featureId].Level -or
            -not [string]::IsNullOrEmpty([string]$featureRow[6]) -or
            [int]$featureRow[7] -ne
                [int]$expectedFeatures[$featureId].Attributes) {
            throw "MSI feature '$featureId' differs from its exact selectable-shortcut invariant."
        }
    }
    if ($featureRows.Count -ne $expectedFeatures.Count -or
        $seenFeatures.Count -ne $expectedFeatures.Count) {
        throw 'MSI Feature table differs from the mandatory application and two optional shortcut features.'
    }
    $featureComponentRows = @(Get-MsiRows -Sql 'SELECT * FROM `FeatureComponents`')
    $seenFeatureComponents = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal)
    foreach ($featureComponentRow in $featureComponentRows) {
        $featureId = [string]$featureComponentRow[0]
        $componentId = [string]$featureComponentRow[1]
        $expectedFeatureId = if ($componentId -ceq
            'StartMenuShortcutComponent') {
            'StartMenuShortcutFeature'
        }
        elseif ($componentId -ceq 'DesktopShortcutComponent') {
            'DesktopShortcutFeature'
        }
        else {
            'CoreFeature'
        }
        if ($featureId -cne $expectedFeatureId -or
            -not $componentIds.Contains($componentId) -or
            -not $seenFeatureComponents.Add($componentId)) {
            throw 'MSI FeatureComponents contains an unknown, duplicate, or incorrectly assigned component.'
        }
    }
    if ($seenFeatureComponents.Count -ne $componentIds.Count) {
        throw 'The MSI features do not reference every component exactly once.'
    }

    if ($metadataFiles.Count -gt 0 -and $fileTableTotalBytes -ne $metadataTotalBytes) {
        throw "MSI File table describes $fileTableTotalBytes bytes; validation metadata describes $metadataTotalBytes bytes."
    }

    $actualFiles = @($actualFiles | Sort-Object -Unique)
    if (-not [string]::IsNullOrWhiteSpace($ExpectedFilesPath)) {
        $expectedFiles = @(
            Get-Content -LiteralPath $ExpectedFilesPath |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $differences = @(Compare-Object -ReferenceObject $expectedFiles -DifferenceObject $actualFiles)
        if ($differences.Count -ne 0) {
            $differenceText = ($differences | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join [Environment]::NewLine
            throw "MSI runtime payload differs from the filtered source list:$([Environment]::NewLine)$differenceText"
        }
    }
    if ($metadataFiles.Count -gt 0) {
        $metadataPaths = @(
            $metadataFiles |
                ForEach-Object { ([string]$_.Path).Replace('/', [IO.Path]::DirectorySeparatorChar) } |
                Sort-Object -Unique
        )
        $differences = @(Compare-Object -ReferenceObject $metadataPaths -DifferenceObject $actualFiles)
        if ($differences.Count -ne 0) {
            $differenceText = ($differences | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join [Environment]::NewLine
            throw "MSI File table differs from validation metadata:$([Environment]::NewLine)$differenceText"
        }
    }

    foreach ($requiredFile in @('WireSockUI.exe', 'WireSockUI.exe.config', 'WireSockUI.Managed.dll')) {
        if (-not ($actualFiles -icontains $requiredFile)) {
            throw "MSI is missing required root runtime file '$requiredFile'."
        }
    }

    foreach ($file in $actualFiles) {
        if ($file -imatch '(^|[\\/])_manifest([\\/]|$)' -or
            $file -imatch '\.(pdb|wixpdb|msi|msix|msp|cab|zip|nupkg|snupkg|sha256|obj|res|exp|lib|ilk|map)$' -or
            $file -imatch '\.(spdx|sbom)\.json$' -or
            $file -imatch '\.intoto\.jsonl$') {
            throw "MSI contains forbidden build/release metadata '$file'."
        }
    }

    if ($metadataFiles.Count -gt 0) {
        $extractionRoot = Join-Path ([IO.Path]::GetTempPath()) (
            'WireSockUI.Msi.Extract.' + [Guid]::NewGuid().ToString('N'))
        try {
            [IO.Directory]::CreateDirectory($extractionRoot) | Out-Null
            $extractionDrive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($extractionRoot))
            $requiredFreeBytes = $metadataTotalBytes + $msiLength + [Int64](256MB)
            if ($extractionDrive.AvailableFreeSpace -lt $requiredFreeBytes) {
                throw "MSI validation requires at least $requiredFreeBytes free bytes on '$($extractionDrive.Name)' before cabinet extraction."
            }
            $decompiledSourcePath = Join-Path $extractionRoot 'package.wxs'
            $extractedPayloadPath = Join-Path $extractionRoot 'payload'
            [IO.Directory]::CreateDirectory($extractedPayloadPath) | Out-Null
            $exportedCabinetPath = Join-Path $extractionRoot 'embedded.cab'
            [Int64]$exportedCabinetLength = Export-MsiStream `
                -DatabasePath $resolvedMsiPath `
                -StreamName $embeddedCabinetStreamName `
                -OutputPath $exportedCabinetPath `
                -MaximumBytes $maximumMsiBytes
            if ($exportedCabinetLength -gt $msiLength) {
                throw 'Embedded cabinet stream is larger than its containing MSI.'
            }
            Assert-CabinetMetadata `
                -Path $exportedCabinetPath `
                -ExpectedFileSizes $fileIdToSize `
                -ExpectedTotalBytes $fileTableTotalBytes

            $resolvedWixToolPath = Resolve-WixToolPath -ExplicitPath $WixToolPath
            if ($resolvedWixToolPath.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase)) {
                & dotnet $resolvedWixToolPath msi decompile `
                    -sct `
                    -sui `
                    -o $decompiledSourcePath `
                    -x $extractedPayloadPath `
                    $resolvedMsiPath
            }
            else {
                & $resolvedWixToolPath msi decompile `
                    -sct `
                    -sui `
                    -o $decompiledSourcePath `
                    -x $extractedPayloadPath `
                    $resolvedMsiPath
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Pinned WiX cabinet extraction failed with exit code $LASTEXITCODE."
            }

            $extractedEntries = @(
                Get-ChildItem -LiteralPath $extractedPayloadPath -Recurse -Force
            )
            foreach ($extractedEntry in $extractedEntries) {
                if (($extractedEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "MSI cabinet export contains reparse point '$($extractedEntry.FullName)'."
                }
            }

            $extractedFileRoot = Join-Path $extractedPayloadPath 'File'
            if (-not [IO.Directory]::Exists($extractedFileRoot)) {
                throw 'Pinned WiX did not export the MSI cabinet File payload.'
            }
            $extractedFiles = @(
                Get-ChildItem -LiteralPath $extractedFileRoot -File -Force
            )
            if ($extractedFiles.Count -ne $metadataFiles.Count) {
                throw "MSI cabinet export contains $($extractedFiles.Count) files; expected $($metadataFiles.Count)."
            }

            $seenExtractedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $extractedLauncherPath = $null
            $extractedManagedAssemblyPath = $null
            foreach ($file in $extractedFiles) {
                if (-not $fileIdToRelativePath.ContainsKey($file.Name)) {
                    throw "MSI cabinet export contains unknown File identifier '$($file.Name)'."
                }
                $relativePath = $fileIdToRelativePath[$file.Name]
                if (-not $seenExtractedPaths.Add($relativePath) -or
                    -not $metadataByPath.ContainsKey($relativePath)) {
                    throw "MSI cabinet export contains unexpected file '$relativePath'."
                }
                $expectedFile = $metadataByPath[$relativePath]
                if ($file.Length -ne [Int64]$expectedFile.Size) {
                    throw "MSI cabinet export file '$relativePath' has an unexpected size."
                }
                $actualHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualHash -cne [string]$expectedFile.Sha256) {
                    throw "MSI cabinet export file '$relativePath' has an unexpected SHA-256 hash."
                }
                if ($relativePath -ceq 'WireSockUI.exe') {
                    $extractedLauncherPath = $file.FullName
                }
                elseif ($relativePath -ceq 'WireSockUI.Managed.dll') {
                    $extractedManagedAssemblyPath = $file.FullName
                }
            }

            if ([string]::IsNullOrEmpty($extractedLauncherPath)) {
                throw 'MSI cabinet export does not contain the native launcher.'
            }
            $embeddedManifestRecords = @(
                Get-EmbeddedPayloadManifestRecords -Path $extractedLauncherPath
            )
            $expectedEmbeddedManifestFiles = @(
                $metadataFiles |
                    Where-Object { [string]$_.Path -cne 'WireSockUI.exe' }
            )
            if ($embeddedManifestRecords.Count -ne
                $expectedEmbeddedManifestFiles.Count) {
                throw 'The launcher payload manifest does not describe the exact MSI payload inventory.'
            }
            foreach ($manifestRecord in $embeddedManifestRecords) {
                $manifestPath = [string]$manifestRecord.Path
                if (-not $metadataByPath.ContainsKey($manifestPath)) {
                    throw "The launcher payload manifest contains unknown path '$manifestPath'."
                }
                $metadataRecord = $metadataByPath[$manifestPath]
                if ([string]$metadataRecord.Path -cne $manifestPath -or
                    [Int64]$metadataRecord.Size -ne [Int64]$manifestRecord.Size -or
                    [string]$metadataRecord.Sha256 -cne
                        [string]$manifestRecord.Sha256) {
                    throw "The launcher payload manifest differs from the cabinet at '$manifestPath'."
                }
            }
            $extractedArchitecture = Get-PortableExecutableArchitecture -Path $extractedLauncherPath
            if ($extractedArchitecture -cne $ExpectedArchitecture) {
                throw "Extracted launcher targets $extractedArchitecture, not $ExpectedArchitecture."
            }
            $expectedValidatorPlatform = if ($ExpectedArchitecture -ceq 'arm64') {
                'ARM64'
            }
            else {
                $ExpectedArchitecture
            }
            Assert-NativeBootstrap `
                -Path $extractedLauncherPath `
                -ExpectedPlatform $expectedValidatorPlatform `
                -ExpectedVersion $ExpectedVersion `
                -RequireProductionBuild |
                Out-Null
            if ([string]::IsNullOrEmpty($extractedManagedAssemblyPath)) {
                throw 'MSI cabinet export does not contain WireSockUI.Managed.dll.'
            }
            Assert-ManagedAssemblyPlatform `
                -Path $extractedManagedAssemblyPath `
                -ExpectedPlatform $expectedValidatorPlatform |
                Out-Null
            & (Join-Path $PSScriptRoot 'Test-UnsignedArtifacts.ps1') `
                -Path $extractionRoot |
                Out-Null
        }
        finally {
            if ([IO.Directory]::Exists($extractionRoot)) {
                $resolvedExtractionRoot =
                    [IO.Path]::GetFullPath($extractionRoot)
                $normalizedTempRoot = [IO.Path]::GetFullPath(
                    [IO.Path]::GetTempPath()).TrimEnd('\', '/') + '\'
                $extractionRootEntry =
                    Get-Item -LiteralPath $resolvedExtractionRoot -Force
                if (-not $resolvedExtractionRoot.StartsWith(
                        $normalizedTempRoot,
                        [StringComparison]::OrdinalIgnoreCase) -or
                    -not (Split-Path -Leaf $resolvedExtractionRoot).StartsWith(
                        'WireSockUI.Msi.Extract.',
                        [StringComparison]::Ordinal) -or
                    ($extractionRootEntry.Attributes -band
                        [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Refusing to recursively clean unsafe extraction path '$resolvedExtractionRoot'."
                }
                [IO.Directory]::Delete($resolvedExtractionRoot, $true)
            }
        }
    }

    Write-Output "Validated $resolvedMsiPath ($ExpectedArchitecture, $ExpectedFlavor, $ExpectedVersion, $($actualFiles.Count) runtime files)."
}
finally {
    if ($null -ne $database) {
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($database) | Out-Null
    }
    if ($null -ne $installer) {
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) | Out-Null
    }
}
