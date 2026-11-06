$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module `
    (Join-Path $PSScriptRoot 'MsiTest.AccessControl.psm1') `
    -Force

function Get-SddlFileSystemRights {
    param([Parameter(Mandatory = $true)][string]$SddlRights)

    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetSecurityDescriptorSddlForm(
        "O:SYG:SYD:P(A;;$SddlRights;;;BU)")
    $rules = @(
        $security.GetAccessRules(
            $true,
            $false,
            [Security.Principal.SecurityIdentifier])
    )
    if ($rules.Count -ne 1) {
        throw "Expected one access rule for SDDL rights '$SddlRights'."
    }
    return $rules[0].FileSystemRights
}

function New-DirectorySecurityFromSddl {
    param([Parameter(Mandatory = $true)][string]$Sddl)

    $rawDescriptor =
        [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    $binaryDescriptor = [byte[]]::new($rawDescriptor.BinaryLength)
    $rawDescriptor.GetBinaryForm($binaryDescriptor, 0)
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetSecurityDescriptorBinaryForm($binaryDescriptor)
    return $security
}

function New-FileSecurityFromSddl {
    param([Parameter(Mandatory = $true)][string]$Sddl)

    $rawDescriptor =
        [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    $binaryDescriptor = [byte[]]::new($rawDescriptor.BinaryLength)
    $rawDescriptor.GetBinaryForm($binaryDescriptor, 0)
    $security = [Security.AccessControl.FileSecurity]::new()
    $security.SetSecurityDescriptorBinaryForm($binaryDescriptor)
    return $security
}

foreach ($rights in @(
        [Security.AccessControl.FileSystemRights]::Read,
        [Security.AccessControl.FileSystemRights]::ReadAndExecute,
        [Security.AccessControl.FileSystemRights]::ExecuteFile,
        [Security.AccessControl.FileSystemRights]::Synchronize)) {
    if (Test-MsiWriteCapableFileSystemRights -Rights $rights) {
        throw "Read-only filesystem rights '$rights' were classified as writable."
    }
}

foreach ($rights in @(
        [Security.AccessControl.FileSystemRights]::Write,
        [Security.AccessControl.FileSystemRights]::WriteData,
        [Security.AccessControl.FileSystemRights]::AppendData,
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes,
        [Security.AccessControl.FileSystemRights]::WriteAttributes,
        [Security.AccessControl.FileSystemRights]::Modify,
        [Security.AccessControl.FileSystemRights]::Delete,
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles,
        [Security.AccessControl.FileSystemRights]::ChangePermissions,
        [Security.AccessControl.FileSystemRights]::TakeOwnership,
        [Security.AccessControl.FileSystemRights]::FullControl)) {
    if (-not (Test-MsiWriteCapableFileSystemRights -Rights $rights)) {
        throw "Mutation-capable filesystem rights '$rights' were classified as read-only."
    }
}

foreach ($sddlRights in @('GR', 'GX', 'GRGX')) {
    $rights = Get-SddlFileSystemRights -SddlRights $sddlRights
    if (Test-MsiWriteCapableFileSystemRights -Rights $rights) {
        throw "Read-only SDDL rights '$sddlRights' were classified as writable."
    }
}

foreach ($sddlRights in @('GW', 'GA')) {
    $rights = Get-SddlFileSystemRights -SddlRights $sddlRights
    if (-not (Test-MsiWriteCapableFileSystemRights -Rights $rights)) {
        throw "Mutation-capable SDDL rights '$sddlRights' were classified as read-only."
    }
}

$deleteOnlyRights =
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::
        DeleteSubdirectoriesAndFiles
if (Test-MsiReplacementCapableFileSystemRights -Rights $deleteOnlyRights) {
    throw 'Delete-only filesystem rights were classified as replacement-capable.'
}
foreach ($rights in @(
        [Security.AccessControl.FileSystemRights]::Write,
        [Security.AccessControl.FileSystemRights]::ChangePermissions,
        [Security.AccessControl.FileSystemRights]::TakeOwnership,
        [Security.AccessControl.FileSystemRights]::FullControl)) {
    if (-not (Test-MsiReplacementCapableFileSystemRights -Rights $rights)) {
        throw "Mutation-capable filesystem rights '$rights' were classified as non-replacing."
    }
}

$nullDaclSecurity = New-DirectorySecurityFromSddl `
    -Sddl 'O:SYG:SYD:NO_ACCESS_CONTROL'
if (Test-MsiSecurityDescriptorHasNonNullDacl -Security $nullDaclSecurity) {
    throw 'A NULL filesystem DACL was accepted as protected.'
}
$emptyDaclSecurity = New-DirectorySecurityFromSddl -Sddl 'O:SYG:SYD:'
if (-not (Test-MsiSecurityDescriptorHasNonNullDacl `
        -Security $emptyDaclSecurity)) {
    throw 'An empty deny-all filesystem DACL was rejected.'
}

$authoredDirectorySddl =
    'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)'
$authoredFileSddl =
    'O:BAG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;BU)'
$exactDirectorySddl =
    'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)'
$exactFileSddl =
    'O:BAG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200a9;;;BU)'
$dotNetSplitDirectorySddl =
    'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;;0x1200a9;;;BU)(A;OICIIO;GRGX;;;BU)'
if (-not (Test-MsiExactPayloadAccessControl `
        -Security (New-DirectorySecurityFromSddl `
            -Sddl $exactDirectorySddl) `
        -Directory)) {
    throw 'The exact protected payload-directory ACL was rejected.'
}
if (-not (Test-MsiExactPayloadAccessControl `
        -Security (New-FileSecurityFromSddl -Sddl $exactFileSddl))) {
    throw 'The exact protected payload-file ACL was rejected.'
}
if (Test-MsiExactPayloadAccessControl `
        -Security (New-DirectorySecurityFromSddl `
            -Sddl $authoredDirectorySddl) `
        -Directory) {
    throw 'A pre-filesystem payload-directory descriptor was mistaken for its NTFS-materialized ACL.'
}
if (Test-MsiExactPayloadAccessControl `
        -Security (New-FileSecurityFromSddl -Sddl $authoredFileSddl)) {
    throw 'A pre-filesystem payload-file descriptor was mistaken for its NTFS-materialized ACL.'
}
if (Test-MsiExactPayloadAccessControl `
        -Security (New-DirectorySecurityFromSddl `
            -Sddl $dotNetSplitDirectorySddl) `
        -Directory) {
    throw 'A .NET-authored split directory ACL was mistaken for the exact Windows Installer ACL.'
}

foreach ($invalidDirectorySddl in @(
        $exactDirectorySddl.Replace('O:BA', 'O:SY'),
        $exactDirectorySddl.Replace('G:SY', 'G:BA'),
        $exactDirectorySddl.Replace('D:P', 'D:'),
        $exactDirectorySddl.Replace('0x1200a9', '0x120089'),
        $exactDirectorySddl.Replace(
            '(A;OICI;0x1200a9;;;BU)',
            '(D;OICI;0x1200a9;;;BU)(A;OICI;0x1200a9;;;BU)'))) {
    if (Test-MsiExactPayloadAccessControl `
            -Security (New-DirectorySecurityFromSddl `
                -Sddl $invalidDirectorySddl) `
            -Directory) {
        throw "An inexact payload-directory ACL was accepted: $invalidDirectorySddl"
    }
}
if (Test-MsiExactPayloadAccessControl `
        -Security (New-DirectorySecurityFromSddl `
            -Sddl $exactDirectorySddl)) {
    throw 'A directory ACL was accepted as an exact payload-file ACL.'
}
if (Test-MsiExactPayloadAccessControl `
        -Security (New-FileSecurityFromSddl -Sddl $exactFileSddl) `
        -Directory) {
    throw 'A file ACL was accepted as an exact payload-directory ACL.'
}

function Assert-PersistedPayloadAclRoundTrip {
    $temporaryDirectory =
        [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $testRoot = Join-Path `
        $temporaryDirectory `
        ('WireSockUI-MsiAcl-' + [Guid]::NewGuid().ToString('N'))
    $testFile = Join-Path $testRoot 'payload.bin'
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($null -eq $currentSid -or
        $currentSid.Value -in @(
            'S-1-5-18',
            'S-1-5-32-544',
            'S-1-5-32-545')) {
        throw 'The ACL round-trip test requires an ordinary current-user SID.'
    }

    try {
        [IO.Directory]::CreateDirectory($testRoot) | Out-Null
        [IO.File]::WriteAllBytes($testFile, [byte[]]@(0))

        $fileAcl = Get-Acl -LiteralPath $testFile
        $fileAcl.SetSecurityDescriptorSddlForm(
            "D:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;BU)(A;;FA;;;$($currentSid.Value))",
            [Security.AccessControl.AccessControlSections]::Access)
        Set-Acl -LiteralPath $testFile -AclObject $fileAcl

        $directoryAcl = Get-Acl -LiteralPath $testRoot
        $directoryAcl.SetSecurityDescriptorSddlForm(
            "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)(A;OICI;FA;;;$($currentSid.Value))",
            [Security.AccessControl.AccessControlSections]::Access)
        Set-Acl -LiteralPath $testRoot -AclObject $directoryAcl

        foreach ($testCase in @(
                [pscustomobject]@{
                    Path = $testRoot
                    Directory = $true
                },
                [pscustomobject]@{
                    Path = $testFile
                    Directory = $false
                })) {
            $persistedAcl = Get-Acl -LiteralPath $testCase.Path
            $persistedAcl.PurgeAccessRules($currentSid)
            $persistedAcl.SetOwner(
                [Security.Principal.SecurityIdentifier]::new(
                    'S-1-5-32-544'))
            $persistedAcl.SetGroup(
                [Security.Principal.SecurityIdentifier]::new(
                    'S-1-5-18'))
            if (-not (Test-MsiExactPayloadAccessControl `
                    -Security $persistedAcl `
                    -Directory:$testCase.Directory)) {
                throw "The NTFS-materialized payload ACL was rejected for '$($testCase.Path)'."
            }
        }
    }
    finally {
        if ([IO.Directory]::Exists($testRoot)) {
            $normalizedTemporaryDirectory =
                $temporaryDirectory.TrimEnd('\', '/') + '\'
            $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
            $testRootEntry = Get-Item -LiteralPath $resolvedTestRoot -Force
            if (-not $resolvedTestRoot.StartsWith(
                    $normalizedTemporaryDirectory,
                    [StringComparison]::OrdinalIgnoreCase) -or
                -not (Split-Path -Leaf $resolvedTestRoot).StartsWith(
                    'WireSockUI-MsiAcl-',
                    [StringComparison]::Ordinal) -or
                ($testRootEntry.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to recursively clean unsafe ACL test path '$resolvedTestRoot'."
            }
            [IO.Directory]::Delete($resolvedTestRoot, $true)
        }
    }
}

Assert-PersistedPayloadAclRoundTrip

Write-Output 'Validated MSI filesystem-rights classification.'
