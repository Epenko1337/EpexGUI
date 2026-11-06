[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('x86', 'x64', 'ARM64', 'arm64')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [ValidateSet('uwp', 'no-uwp')]
    [string]$Flavor,

    [Parameter(Mandatory = $true)]
    [string]$PayloadDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [switch]$NoRestore,
    [switch]$PreserveFailedArtifactsForDiagnostics
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $repositoryRoot 'WireSockUI.Installer\WireSockUI.Installer.wixproj'
$validationScriptPath = Join-Path $PSScriptRoot 'Test-MsiPackage.ps1'
$maximumPayloadEntries = 4096
$maximumPayloadFileBytes = 512MB
$maximumPayloadBytes = 2GB
$excludedExtensions = @(
    '.pdb',
    '.wixpdb',
    '.msi',
    '.msix',
    '.msp',
    '.cab',
    '.zip',
    '.nupkg',
    '.snupkg',
    '.sha256',
    '.obj',
    '.res',
    '.exp',
    '.lib',
    '.ilk',
    '.map'
)
$excludedSuffixes = @(
    '.spdx.json',
    '.sbom.json',
    '.intoto.jsonl'
)

function Get-NormalizedArchitecture {
    param([string]$Value)

    switch ($Value.ToLowerInvariant()) {
        'x86' { return 'x86' }
        'x64' { return 'x64' }
        'arm64' { return 'arm64' }
        default { throw "Unsupported installer platform '$Value'." }
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

    # Mark the generated value as an RFC 4122 variant/version-5 UUID. The name
    # hash is SHA-256 rather than SHA-1, but only stable GUID identity is needed.
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

function ConvertTo-WixAttributeValue {
    param([string]$Value)

    return [Security.SecurityElement]::Escape($Value)
}

function Get-PayloadAuthoring {
    param(
        [object[]]$RuntimeFiles,
        [string]$Architecture
    )

    $runtimeFileByPath =
        New-Object 'System.Collections.Generic.Dictionary[string,object]' (
            [StringComparer]::OrdinalIgnoreCase)
    foreach ($runtimeFile in $RuntimeFiles) {
        $manifestPath = [string]$runtimeFile.ManifestPath
        if ([string]::IsNullOrEmpty($manifestPath) -or
            $runtimeFileByPath.ContainsKey($manifestPath)) {
            throw "The MSI payload authoring contains an empty or case-insensitively duplicated path '$manifestPath'."
        }
        $runtimeFileByPath.Add($manifestPath, $runtimeFile)
    }
    [string[]]$sortedManifestPaths = @($runtimeFileByPath.Keys)
    [Array]::Sort($sortedManifestPaths, [StringComparer]::Ordinal)
    $sortedRuntimeFiles = @(
        $sortedManifestPaths |
            ForEach-Object { $runtimeFileByPath[$_] }
    )
    $payloadFiles = @(
        $sortedRuntimeFiles |
            Where-Object {
                $_.ManifestPath -cnotin @(
                    'WireSockUI.exe',
                    'WireSockUI.exe.config')
            }
    )
    if ($payloadFiles.Count -lt 1) {
        throw 'The MSI payload authoring has no files outside the native-host component.'
    }

    $directoryPathByInsensitivePath =
        New-Object 'System.Collections.Generic.Dictionary[string,string]' (
            [StringComparer]::OrdinalIgnoreCase)
    foreach ($runtimeFile in $sortedRuntimeFiles) {
        $segments = $runtimeFile.ManifestPath.Split('/')
        for ($segmentCount = 1;
            $segmentCount -lt $segments.Count;
            $segmentCount++) {
            $directoryPath = [string]::Join(
                '/',
                $segments[0..($segmentCount - 1)])
            $knownDirectoryPath = $null
            if ($directoryPathByInsensitivePath.TryGetValue(
                    $directoryPath,
                    [ref]$knownDirectoryPath)) {
                if ($knownDirectoryPath -cne $directoryPath) {
                    throw "Payload paths use inconsistent casing for directory '$knownDirectoryPath' and '$directoryPath'."
                }
                continue
            }
            $directoryPathByInsensitivePath.Add(
                $directoryPath,
                $directoryPath)
        }
    }
    $directoryPathsByDepth =
        New-Object (
            'System.Collections.Generic.SortedDictionary[' +
            'int,System.Collections.Generic.List[string]]')
    foreach ($directoryPath in
        $directoryPathByInsensitivePath.Values) {
        $depth = $directoryPath.Split('/').Count
        $pathsAtDepth = $null
        if (-not $directoryPathsByDepth.TryGetValue(
                $depth,
                [ref]$pathsAtDepth)) {
            $pathsAtDepth =
                New-Object 'System.Collections.Generic.List[string]'
            $directoryPathsByDepth.Add($depth, $pathsAtDepth)
        }
        $pathsAtDepth.Add($directoryPath)
    }
    $sortedDirectoryPaths =
        New-Object 'System.Collections.Generic.List[string]'
    foreach ($depth in $directoryPathsByDepth.Keys) {
        [string[]]$sortedPathsAtDepth =
            $directoryPathsByDepth[$depth].ToArray()
        [Array]::Sort(
            $sortedPathsAtDepth,
            [StringComparer]::Ordinal)
        foreach ($directoryPath in $sortedPathsAtDepth) {
            $sortedDirectoryPaths.Add($directoryPath)
        }
    }

    $directorySddl =
        'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)'
    $fileSddl =
        'O:BAG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;BU)'
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Include xmlns="http://wixtoolset.org/schemas/v4/wxs">')

    foreach ($directoryPath in $sortedDirectoryPaths) {
        $componentId = Get-DeterministicMsiIdentifier `
            -Prefix 'PayloadDirectorySecurity_' `
            -Identity "PayloadDirectorySecurity|$directoryPath"
        $permissionId = Get-DeterministicMsiIdentifier `
            -Prefix 'PayloadDirectoryPermission_' `
            -Identity "PayloadDirectoryPermission|$directoryPath"
        $componentGuid = Get-DeterministicGuid `
            -Identity "Component|PayloadDirectorySecurity|$Architecture|$directoryPath"
        $subdirectory = ConvertTo-WixAttributeValue `
            -Value $directoryPath.Replace('/', '\')
        $lines.Add('  <Component')
        $lines.Add("      Id=`"$componentId`"")
        $lines.Add("      Guid=`"$componentGuid`"")
        $lines.Add('      Feature="CoreFeature"')
        $lines.Add('      Directory="WireSockInstallFolder"')
        $lines.Add("      Subdirectory=`"$subdirectory`">")
        $lines.Add('    <CreateFolder>')
        $lines.Add('      <PermissionEx')
        $lines.Add("          Id=`"$permissionId`"")
        $lines.Add("          Sddl=`"$directorySddl`" />")
        $lines.Add('    </CreateFolder>')
        $lines.Add('  </Component>')
    }

    foreach ($runtimeFile in $payloadFiles) {
        $componentId = Get-DeterministicMsiIdentifier `
            -Prefix 'PayloadFile_' `
            -Identity "PayloadFile|$($runtimeFile.ManifestPath)"
        $permissionId = Get-DeterministicMsiIdentifier `
            -Prefix 'PayloadFilePermission_' `
            -Identity "PayloadFilePermission|$($runtimeFile.ManifestPath)"
        $relativeWindowsPath = $runtimeFile.ManifestPath.Replace('/', '\')
        $relativeSource = ConvertTo-WixAttributeValue `
            -Value "!(bindpath.Payload)\$relativeWindowsPath"
        $directoryPath = [IO.Path]::GetDirectoryName($relativeWindowsPath)
        $lines.Add('  <Component')
        $lines.Add("      Id=`"$componentId`"")
        $lines.Add('      Guid="*"')
        $lines.Add('      Feature="CoreFeature"')
        if (-not [string]::IsNullOrEmpty($directoryPath)) {
            $lines.Add('      Directory="WireSockInstallFolder"')
            $subdirectory = ConvertTo-WixAttributeValue -Value $directoryPath
            $lines.Add("      Subdirectory=`"$subdirectory`">")
        }
        else {
            $lines.Add('      Directory="WireSockInstallFolder">')
        }
        $lines.Add('    <File')
        $lines.Add("        Id=`"$componentId`"")
        $lines.Add("        Source=`"$relativeSource`"")
        $lines.Add('        KeyPath="yes">')
        $lines.Add('      <PermissionEx')
        $lines.Add("          Id=`"$permissionId`"")
        $lines.Add("          Sddl=`"$fileSddl`" />")
        $lines.Add('    </File>')
        $lines.Add('  </Component>')
    }

    $lines.Add('</Include>')
    return [string]::Join("`r`n", $lines) + "`r`n"
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

function Test-IsPackagingMetadata {
    param(
        [string]$RelativePath,
        [System.IO.FileInfo]$File
    )

    $segments = $RelativePath -split '[\\/]'
    if ($segments | Where-Object { $_ -ieq '_manifest' }) {
        return $true
    }
    if ($segments.Count -gt 1 -and $segments[0] -ieq 'publish') {
        return $true
    }

    if ($excludedExtensions -icontains $File.Extension) {
        return $true
    }

    foreach ($suffix in $excludedSuffixes) {
        if ($File.Name.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-IsPathContainedBy {
    param(
        [string]$CandidatePath,
        [string]$ParentPath
    )

    $normalizedParent = $ParentPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $CandidatePath.StartsWith($normalizedParent, [StringComparison]::OrdinalIgnoreCase)
}

function Test-IsReservedDeviceSegment {
    param([string]$Segment)

    $dotIndex = $Segment.IndexOf('.')
    $name = if ($dotIndex -ge 0) {
        $Segment.Substring(0, $dotIndex)
    }
    else {
        $Segment
    }
    if ($name -imatch '^(CON|PRN|AUX|NUL)$') {
        return $true
    }
    return $name -imatch '^(COM|LPT)[1-9]$'
}

function Test-IsCanonicalManifestPath {
    param([string]$Path)

    if ([string]::IsNullOrEmpty($Path) -or
        $Path.Length -ge 32700 -or
        $Path.StartsWith('/', [StringComparison]::Ordinal) -or
        $Path.StartsWith('\', [StringComparison]::Ordinal) -or
        $Path.Contains('\') -or
        $Path.Contains(':')) {
        return $false
    }

    foreach ($segment in $Path.Split('/')) {
        if ([string]::IsNullOrEmpty($segment) -or
            $segment -eq '.' -or
            $segment -eq '..' -or
            $segment.EndsWith(' ', [StringComparison]::Ordinal) -or
            $segment.EndsWith('.', [StringComparison]::Ordinal) -or
            (Test-IsReservedDeviceSegment -Segment $segment)) {
            return $false
        }
        foreach ($character in $segment.ToCharArray()) {
            if ([int]$character -lt 32 -or '"<>|*?'.Contains($character)) {
                return $false
            }
        }
    }
    return $true
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

function ConvertFrom-PayloadManifestText {
    param([string]$ManifestText)

    if (-not $ManifestText.EndsWith("`n", [StringComparison]::Ordinal)) {
        throw 'The embedded payload manifest is not LF-terminated.'
    }
    $lines = $ManifestText -split "`n"
    if ($lines.Count -lt 2 -or $lines[0] -cne 'WireSockUI-Payload-v1') {
        throw 'WireSockUI.exe does not contain a supported embedded payload manifest.'
    }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $pathComparer = [StringComparer]::OrdinalIgnoreCase
    $previousPath = $null
    for ($lineIndex = 1; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ([string]::IsNullOrEmpty($line)) {
            if ($lineIndex -ne $lines.Count - 1) {
                throw 'The embedded payload manifest contains an unexpected blank line.'
            }
            continue
        }

        $fields = $line.Split("`t")
        if ($fields.Count -ne 3 -or $fields[0] -cnotmatch '^[0-9a-f]{64}$') {
            throw "The embedded payload manifest line $($lineIndex + 1) is invalid."
        }
        if ($fields[1] -cnotmatch '^(0|[1-9][0-9]*)$') {
            throw "The embedded payload manifest size on line $($lineIndex + 1) is not canonical."
        }
        [Int64]$size = 0
        if (-not [Int64]::TryParse(
                $fields[1],
                [Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$size) -or
            $size -lt 0 -or
            $size -gt $maximumPayloadFileBytes) {
            throw "The embedded payload manifest size on line $($lineIndex + 1) is invalid."
        }

        $relativePath = $fields[2]
        if (-not (Test-IsCanonicalManifestPath -Path $relativePath)) {
            throw "The embedded payload path '$relativePath' is not canonical."
        }
        if (-not $seenPaths.Add($relativePath) -or
            ($null -ne $previousPath -and
                $pathComparer.Compare($previousPath, $relativePath) -ge 0)) {
            throw "The embedded payload manifest is not uniquely and canonically ordered at '$relativePath'."
        }
        $previousPath = $relativePath

        $entries.Add([pscustomobject]@{
            RelativePath = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
            ManifestPath = $relativePath
            Size = $size
            Sha256 = $fields[0]
        })
    }

    if ($entries.Count -lt 2 -or $entries.Count -gt $maximumPayloadEntries) {
        throw "The embedded payload manifest contains an invalid number of entries: $($entries.Count)."
    }
    return $entries.ToArray()
}

function Get-EmbeddedPayloadManifest {
    param([string]$LauncherPath)

    if ($null -eq ('WireSockUI.Installer.NativeResourceReader' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

namespace WireSockUI.Installer
{
    public static class NativeResourceReader
    {
        private const uint LoadLibraryAsDataFile = 0x00000002;
        private const uint LoadLibraryAsImageResource = 0x00000020;
        private const int PayloadManifestResourceId = 201;
        private const int RtRcData = 10;
        private const uint MaximumPayloadManifestBytes = 2U * 1024U * 1024U;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(
            string fileName,
            IntPtr file,
            uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
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

        public static byte[] ReadPayloadManifest(string path)
        {
            var module = LoadLibraryEx(
                path,
                IntPtr.Zero,
                LoadLibraryAsDataFile | LoadLibraryAsImageResource);
            if (module == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error());

            try
            {
                var resource = FindResource(
                    module,
                    new IntPtr(PayloadManifestResourceId),
                    new IntPtr(RtRcData));
                if (resource == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                var size = SizeofResource(module, resource);
                if (size == 0)
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if (size > MaximumPayloadManifestBytes)
                    throw new InvalidDataException(
                        "The embedded payload manifest exceeds the 2 MiB packaging limit.");

                var loaded = LoadResource(module, resource);
                if (loaded == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                var data = LockResource(loaded);
                if (data == IntPtr.Zero)
                    throw new InvalidOperationException("The embedded payload manifest could not be locked.");

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

    $manifestBytes = [WireSockUI.Installer.NativeResourceReader]::ReadPayloadManifest($LauncherPath)
    if ($manifestBytes.Length -gt 2MB) {
        throw 'The embedded payload manifest exceeds the 2 MiB packaging limit.'
    }

    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    $manifestText = $strictUtf8.GetString($manifestBytes)
    return ConvertFrom-PayloadManifestText -ManifestText $manifestText
}

function Test-PayloadManifestParserContract {
    $hash = '0' * 64
    $valid = "WireSockUI-Payload-v1`n$hash`t1`ta.dll`n$hash`t2`tb.config`n"
    if (@(ConvertFrom-PayloadManifestText -ManifestText $valid).Count -ne 2) {
        throw 'Payload-manifest parser self-test rejected a canonical manifest.'
    }

    $invalidManifests = @(
        $valid.TrimEnd("`n"),
        $valid.Replace("`n", "`r`n"),
        "WireSockUI-Payload-v1`n$hash`t01`ta.dll`n$hash`t2`tb.config`n",
        "WireSockUI-Payload-v1`n$hash`t2`tb.config`n$hash`t1`ta.dll`n",
        "WireSockUI-Payload-v1`n$hash`t1`tCON.dll`n$hash`t2`tb.config`n",
        "WireSockUI-Payload-v1`n$hash`t1`ta?.dll`n$hash`t2`tb.config`n",
        "WireSockUI-Payload-v1`n$hash`t1`tA.dll`n$hash`t2`ta.dll`n",
        "WireSockUI-Payload-v1`n$hash`t1`t$('a' * 32700)`n$hash`t2`tb.config`n"
    )
    foreach ($invalidManifest in $invalidManifests) {
        $rejected = $false
        try {
            ConvertFrom-PayloadManifestText -ManifestText $invalidManifest |
                Out-Null
        }
        catch {
            $rejected = $true
        }
        if (-not $rejected) {
            throw 'Payload-manifest parser self-test accepted a noncanonical manifest.'
        }
    }
}

function Test-PayloadAuthoringContract {
    [object[]]$runtimeFiles = @(
        [pscustomobject]@{ ManifestPath = 'WireSockUI.exe' },
        [pscustomobject]@{ ManifestPath = 'WireSockUI.exe.config' },
        [pscustomobject]@{ ManifestPath = 'I/a&ampersand.dll' },
        [pscustomobject]@{ ManifestPath = ([string][char]0x0131) + '/b.dll' }
    )
    $forwardAuthoring = Get-PayloadAuthoring `
        -RuntimeFiles $runtimeFiles `
        -Architecture 'x64'
    [Array]::Reverse($runtimeFiles)
    $reverseAuthoring = Get-PayloadAuthoring `
        -RuntimeFiles $runtimeFiles `
        -Architecture 'x64'
    $dotlessIDirectory = 'Subdirectory="' + [char]0x0131 + '"'
    if ($forwardAuthoring -cne $reverseAuthoring -or
        $forwardAuthoring.IndexOf(
            'Subdirectory="I"',
            [StringComparison]::Ordinal) -lt 0 -or
        $forwardAuthoring.IndexOf(
            'Subdirectory="I"',
            [StringComparison]::Ordinal) -gt
            $forwardAuthoring.IndexOf(
                $dotlessIDirectory,
                [StringComparison]::Ordinal) -or
        -not $forwardAuthoring.Contains(
            'I\a&amp;ampersand.dll')) {
        throw 'Payload authoring is not input-order independent, ordinally ordered, and XML escaped.'
    }

    $inconsistentCaseFiles = @(
        [pscustomobject]@{ ManifestPath = 'WireSockUI.exe' },
        [pscustomobject]@{ ManifestPath = 'WireSockUI.exe.config' },
        [pscustomobject]@{ ManifestPath = 'Locale/a.dll' },
        [pscustomobject]@{ ManifestPath = 'locale/b.dll' }
    )
    $rejected = $false
    try {
        Get-PayloadAuthoring `
            -RuntimeFiles $inconsistentCaseFiles `
            -Architecture 'x64' |
            Out-Null
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw 'Payload authoring accepted inconsistent directory-prefix casing.'
    }
}

Test-PayloadManifestParserContract
Test-PayloadAuthoringContract

$normalizedArchitecture = Get-NormalizedArchitecture -Value $Platform
$Flavor = $Flavor.ToLowerInvariant()

$versionMatch = [regex]::Match($Version, '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
if (-not $versionMatch.Success) {
    throw "Version '$Version' is not a canonical three-part Windows Installer version (MAJOR.MINOR.PATCH)."
}

$major = [int]$versionMatch.Groups[1].Value
$minor = [int]$versionMatch.Groups[2].Value
$patch = [int]$versionMatch.Groups[3].Value
if ($major -gt 255 -or $minor -gt 255 -or $patch -gt 65535) {
    throw "Version '$Version' exceeds Windows Installer limits (255.255.65535)."
}

$payloadPath = [IO.Path]::GetFullPath($PayloadDirectory)
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
if (-not [IO.Directory]::Exists($payloadPath)) {
    throw "Payload directory '$payloadPath' does not exist."
}

$payloadRoot = Get-Item -LiteralPath $payloadPath -Force
if (($payloadRoot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Payload directory '$payloadPath' is a reparse point."
}

if ((Test-IsPathContainedBy -CandidatePath $outputPath -ParentPath $payloadPath) -or
    (Test-IsPathContainedBy -CandidatePath $payloadPath -ParentPath $outputPath) -or
    [string]::Equals($payloadPath, $outputPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'PayloadDirectory and OutputDirectory must be separate, non-nested directories.'
}

$requiredFiles = @(
    'WireSockUI.exe',
    'WireSockUI.exe.config',
    'WireSockUI.Managed.dll'
)
foreach ($requiredFile in $requiredFiles) {
    $requiredPath = Join-Path $payloadPath $requiredFile
    if (-not [IO.File]::Exists($requiredPath)) {
        throw "Required runtime file '$requiredFile' is missing from '$payloadPath'."
    }
}

$payloadEntries = @(Get-ChildItem -LiteralPath $payloadPath -Recurse -Force)
if ($payloadEntries.Count -gt $maximumPayloadEntries) {
    throw "Payload contains $($payloadEntries.Count) entries; the limit is $maximumPayloadEntries."
}
foreach ($entry in $payloadEntries) {
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Payload entry '$($entry.FullName)' is a reparse point."
    }
}

$launcherPath = Join-Path $payloadPath 'WireSockUI.exe'
$launcherArchitecture = Get-PortableExecutableArchitecture -Path $launcherPath
if ($launcherArchitecture -cne $normalizedArchitecture) {
    throw "WireSockUI.exe targets $launcherArchitecture, not requested architecture $normalizedArchitecture."
}
& (Join-Path $PSScriptRoot 'Test-UnsignedArtifacts.ps1') -Path $payloadPath |
    Out-Null

$manifestEntries = @(Get-EmbeddedPayloadManifest -LauncherPath $launcherPath)
$launcherLength = [Int64](Get-Item -LiteralPath $launcherPath).Length
if ($launcherLength -gt $maximumPayloadFileBytes) {
    throw "WireSockUI.exe exceeds the $maximumPayloadFileBytes-byte per-file limit."
}
[Int64]$totalRuntimeBytes = $launcherLength
foreach ($manifestEntry in $manifestEntries) {
    $sourcePath = Join-Path $payloadPath $manifestEntry.RelativePath
    if (-not [IO.File]::Exists($sourcePath)) {
        throw "Embedded payload file '$($manifestEntry.ManifestPath)' is missing."
    }
    $sourceFile = Get-Item -LiteralPath $sourcePath -Force
    if ($sourceFile.Length -ne $manifestEntry.Size) {
        throw "Embedded payload file '$($manifestEntry.ManifestPath)' has an unexpected size."
    }
    $actualHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $manifestEntry.Sha256) {
        throw "Embedded payload file '$($manifestEntry.ManifestPath)' has an unexpected SHA-256 hash."
    }
    if ($totalRuntimeBytes -gt $maximumPayloadBytes - $sourceFile.Length) {
        throw "The runtime payload exceeds the $maximumPayloadBytes-byte limit."
    }
    $totalRuntimeBytes += $sourceFile.Length
}

$runtimeFiles = New-Object 'System.Collections.Generic.List[object]'
$launcherHash = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash.ToLowerInvariant()
$runtimeFiles.Add([pscustomobject]@{
    Source = $launcherPath
    RelativePath = 'WireSockUI.exe'
    ManifestPath = 'WireSockUI.exe'
    Size = $launcherLength
    Sha256 = $launcherHash
})
foreach ($manifestEntry in $manifestEntries) {
    $runtimeFiles.Add([pscustomobject]@{
        Source = Join-Path $payloadPath $manifestEntry.RelativePath
        RelativePath = $manifestEntry.RelativePath
        ManifestPath = $manifestEntry.ManifestPath
        Size = $manifestEntry.Size
        Sha256 = $manifestEntry.Sha256
    })
}

$allowedRuntimePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($runtimeFile in $runtimeFiles) {
    if (-not $allowedRuntimePaths.Add($runtimeFile.ManifestPath)) {
        throw "The runtime payload contains a case-insensitive collision at '$($runtimeFile.ManifestPath)'."
    }
}

foreach ($file in $payloadEntries | Where-Object { -not $_.PSIsContainer }) {
    $relativePath = $file.FullName.Substring($payloadPath.TrimEnd('\', '/').Length).TrimStart('\', '/')
    $manifestPath = $relativePath.Replace('\', '/')
    if (-not (Test-IsPackagingMetadata -RelativePath $relativePath -File $file) -and
        -not $allowedRuntimePaths.Contains($manifestPath)) {
        throw "Published payload contains unknown non-runtime file '$manifestPath'."
    }
}

foreach ($requiredFile in $requiredFiles) {
    if (-not ($runtimeFiles.RelativePath -icontains $requiredFile)) {
        throw "Required runtime file '$requiredFile' was excluded from the MSI payload."
    }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('WireSockUI.Msi.' + [Guid]::NewGuid().ToString('N'))
$stagedPayloadPath = Join-Path $temporaryRoot 'payload'
$intermediatePath = Join-Path $temporaryRoot 'obj'
$expectedFilesPath = Join-Path $temporaryRoot 'expected-files.txt'
$payloadAuthoringPath = Join-Path $temporaryRoot 'payload-authoring.wxi'
$productCode = Get-DeterministicProductCode `
    -Architecture $normalizedArchitecture `
    -ProductVersion $Version `
    -ProductFlavor $Flavor
$securityComponentGuid = Get-DeterministicGuid `
    -Identity "Component|ApplicationDirectorySecurity|$normalizedArchitecture"
$shortcutComponentGuid = Get-DeterministicGuid `
    -Identity "Component|StartMenuShortcut|$normalizedArchitecture"
$desktopShortcutComponentGuid = Get-DeterministicGuid `
    -Identity "Component|DesktopShortcut|$normalizedArchitecture"
$runtimeHostComponentGuid = Get-DeterministicGuid `
    -Identity "Component|RuntimeHost|$normalizedArchitecture"
$fileComponentGuidSeed = Get-DeterministicGuid `
    -Identity "ComponentSeed|RuntimeFiles|$normalizedArchitecture"
$outputFileName = "WireSockUI-$Version-win-$normalizedArchitecture-$Flavor.msi"
$msiPath = Join-Path $outputPath $outputFileName
$validationMetadataPath = $msiPath + '.validation.json'
if ([IO.File]::Exists($msiPath) -or [IO.File]::Exists($validationMetadataPath)) {
    throw "Output '$msiPath' or its validation metadata already exists. Use an empty output directory."
}

try {
    [IO.Directory]::CreateDirectory($stagedPayloadPath) | Out-Null
    [IO.Directory]::CreateDirectory($intermediatePath) | Out-Null
    [IO.Directory]::CreateDirectory($outputPath) | Out-Null

    foreach ($runtimeFile in $runtimeFiles) {
        $stagedFilePath = Join-Path $stagedPayloadPath $runtimeFile.RelativePath
        $stagedParent = Split-Path -Parent $stagedFilePath
        [IO.Directory]::CreateDirectory($stagedParent) | Out-Null
        [IO.File]::Copy($runtimeFile.Source, $stagedFilePath, $false)
    }

    $runtimeFiles.RelativePath |
        Sort-Object -Unique |
        Set-Content -LiteralPath $expectedFilesPath -Encoding UTF8

    $payloadAuthoring = Get-PayloadAuthoring `
        -RuntimeFiles $runtimeFiles.ToArray() `
        -Architecture $normalizedArchitecture
    [IO.File]::WriteAllText(
        $payloadAuthoringPath,
        $payloadAuthoring,
        [Text.UTF8Encoding]::new($false))

    $dotnetArguments = @(
        'build',
        $projectPath,
        '--configuration',
        'Release',
        "--property:InstallerPlatform=$normalizedArchitecture",
        "--property:Platform=$normalizedArchitecture",
        "--property:ProductVersion=$Version",
        "--property:ProductCode=$productCode",
        "--property:ProductFlavor=$Flavor",
        "--property:ProductArchitecture=$normalizedArchitecture",
        "--property:SecurityComponentGuid=$securityComponentGuid",
        "--property:ShortcutComponentGuid=$shortcutComponentGuid",
        "--property:DesktopShortcutComponentGuid=$desktopShortcutComponentGuid",
        "--property:RuntimeHostComponentGuid=$runtimeHostComponentGuid",
        "--property:FileComponentGuidSeed=$fileComponentGuidSeed",
        '--property:RuntimePayloadValidated=true',
        "--property:PayloadDirectory=$stagedPayloadPath",
        "--property:PayloadAuthoringPath=$payloadAuthoringPath",
        "--property:OutputPath=$($outputPath.TrimEnd('\', '/'))\",
        "--property:IntermediateOutputPath=$($intermediatePath.TrimEnd('\', '/'))\",
        "--property:OutputName=WireSockUI-$Version-win-$normalizedArchitecture-$Flavor",
        '--property:CreateHardLinksForCopyFilesToOutputDirectoryIfPossible=false',
        '--property:ContinuousIntegrationBuild=true'
    )
    if ($NoRestore) {
        $dotnetArguments += '--no-restore'
    }

    & dotnet @dotnetArguments
    if ($LASTEXITCODE -ne 0) {
        throw "WiX build failed with exit code $LASTEXITCODE."
    }

    if (-not [IO.File]::Exists($msiPath)) {
        throw "WiX did not produce expected MSI '$msiPath'."
    }

    $validationMetadata = [ordered]@{
        Schema = 'WireSockUI-Msi-Validation-v1'
        ProductName = 'WireSock UI'
        ProductVersion = $Version
        ProductCode = $productCode
        UpgradeCode = '{5C1DDAE5-6681-41BF-B153-AB2952AA6DF1}'
        SecurityComponentGuid = $securityComponentGuid
        ShortcutComponentGuid = $shortcutComponentGuid
        DesktopShortcutComponentGuid = $desktopShortcutComponentGuid
        RuntimeHostComponentGuid = $runtimeHostComponentGuid
        FileComponentGuidSeed = $fileComponentGuidSeed
        Architecture = $normalizedArchitecture
        Flavor = $Flavor
        Files = @(
            $runtimeFiles |
                Sort-Object -Property @{ Expression = { $_.ManifestPath.ToUpperInvariant() } } |
                ForEach-Object {
                    [ordered]@{
                        Path = $_.ManifestPath
                        Size = [Int64]$_.Size
                        Sha256 = $_.Sha256
                    }
                }
        )
    }
    [IO.File]::WriteAllText(
        $validationMetadataPath,
        ($validationMetadata | ConvertTo-Json -Depth 6),
        [Text.UTF8Encoding]::new($false))

    $validationParameters = @{
        MsiPath = $msiPath
        ExpectedArchitecture = $normalizedArchitecture
        ExpectedVersion = $Version
        ExpectedFlavor = $Flavor
        ExpectedProductCode = $productCode
        ExpectedFilesPath = $expectedFilesPath
        ValidationMetadataPath = $validationMetadataPath
    }
    & $validationScriptPath @validationParameters
    if ($LASTEXITCODE -ne 0) {
        throw "MSI validation failed with exit code $LASTEXITCODE."
    }

    Write-Output $msiPath
    Write-Output $validationMetadataPath
}
catch {
    # This invocation refused pre-existing output files, so these paths can only
    # be partial artifacts from the failed build/validation attempt.
    if (-not $PreserveFailedArtifactsForDiagnostics) {
        foreach ($partialArtifact in @($msiPath, $validationMetadataPath)) {
            if ([IO.File]::Exists($partialArtifact)) {
                Remove-Item -LiteralPath $partialArtifact -Force
            }
        }
    }
    throw
}
finally {
    if ([IO.Directory]::Exists($temporaryRoot)) {
        $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
        $normalizedTempRoot = [IO.Path]::GetFullPath(
            [IO.Path]::GetTempPath()).TrimEnd('\', '/') + '\'
        $temporaryRootEntry =
            Get-Item -LiteralPath $resolvedTemporaryRoot -Force
        if (-not $resolvedTemporaryRoot.StartsWith(
                $normalizedTempRoot,
                [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith(
                'WireSockUI.Msi.',
                [StringComparison]::Ordinal) -or
            ($temporaryRootEntry.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to recursively clean unsafe staging path '$resolvedTemporaryRoot'."
        }
        [IO.Directory]::Delete($resolvedTemporaryRoot, $true)
    }
}
