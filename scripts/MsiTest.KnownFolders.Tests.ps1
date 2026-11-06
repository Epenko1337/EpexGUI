$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module `
    (Join-Path $PSScriptRoot 'MsiTest.AccessControl.psm1') `
    -Force
$knownFoldersModule = Import-Module `
    (Join-Path $PSScriptRoot 'MsiTest.KnownFolders.psm1') `
    -Force `
    -PassThru
foreach ($commandName in @(
        'Test-MsiReplacementCapableFileSystemRights',
        'Test-MsiSecurityDescriptorHasNonNullDacl',
        'Test-MsiWriteCapableFileSystemRights')) {
    if ($null -eq (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "The known-folder module hid shared export '$commandName'."
    }
}

function Test-AncestorFileSystemRightsSafe {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemRights]$Rights
    )

    return & $knownFoldersModule {
        param($CandidateRights)

        Test-MsiAncestorFileSystemRightsSafe -Rights $CandidateRights
    } $Rights
}

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

function Get-DirectoryAccessRuleFromSddl {
    param([Parameter(Mandatory = $true)][string]$Sddl)

    $security = New-DirectorySecurityFromSddl -Sddl $Sddl
    $rules = @(
        $security.GetAccessRules(
            $true,
            $false,
            [Security.Principal.SecurityIdentifier])
    )
    if ($rules.Count -ne 1) {
        throw "Expected exactly one access rule in SDDL '$Sddl'."
    }
    return $rules[0]
}

function Test-LeafAccessRuleSafe {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemAccessRule]$Rule
    )

    return & $knownFoldersModule {
        param($CandidateRule)

        Test-MsiDirectoryAccessRuleSafe `
            -Rule $CandidateRule `
            -IsLeaf $true `
            -TrustedWriterSids @(
                'S-1-5-18',
                'S-1-5-32-544',
                'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    } $Rule
}

$commonProgramsFolderId = Get-MsiCommonProgramsFolderId
if ($commonProgramsFolderId -ne
    [Guid]'0139D44E-6AFE-49F2-8690-3DAFCAE6FFB8') {
    throw 'The MSI common Programs known-folder identifier has drifted.'
}
$commonDesktopFolderId = Get-MsiCommonDesktopFolderId
if ($commonDesktopFolderId -ne
    [Guid]'C4AA340D-F20F-4863-AFEF-F87EF2E6BA25') {
    throw 'The MSI common Desktop known-folder identifier has drifted.'
}

$resolvedCommonPrograms = Get-MsiKnownFolderPath `
    -FolderId $commonProgramsFolderId
$frameworkCommonPrograms = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::CommonPrograms)
if ([string]::IsNullOrWhiteSpace($frameworkCommonPrograms) -or
    -not [string]::Equals(
        [IO.Path]::GetFullPath($resolvedCommonPrograms).TrimEnd('\'),
        [IO.Path]::GetFullPath($frameworkCommonPrograms).TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The native and framework Common Programs resolvers disagree.'
}
$resolvedCommonDesktop = Get-MsiKnownFolderPath `
    -FolderId $commonDesktopFolderId
$frameworkCommonDesktop = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::CommonDesktopDirectory)
if ([string]::IsNullOrWhiteSpace($frameworkCommonDesktop) -or
    -not [string]::Equals(
        [IO.Path]::GetFullPath($resolvedCommonDesktop).TrimEnd('\'),
        [IO.Path]::GetFullPath($frameworkCommonDesktop).TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The native and framework Common Desktop resolvers disagree.'
}

foreach ($rights in @(
        [Security.AccessControl.FileSystemRights]::ReadAndExecute,
        [Security.AccessControl.FileSystemRights]::Write)) {
    if (-not (Test-AncestorFileSystemRightsSafe -Rights $rights)) {
        throw "Non-replacing ancestor rights '$rights' were rejected."
    }
}
foreach ($rights in @(
        [Security.AccessControl.FileSystemRights]::Modify,
        [Security.AccessControl.FileSystemRights]::Delete,
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles,
        [Security.AccessControl.FileSystemRights]::ChangePermissions,
        [Security.AccessControl.FileSystemRights]::TakeOwnership,
        [Security.AccessControl.FileSystemRights]::FullControl)) {
    if (Test-AncestorFileSystemRightsSafe -Rights $rights) {
        throw "Replace-capable ancestor rights '$rights' were accepted."
    }
}
foreach ($sddlRights in @('GR', 'GX', 'GW', 'GRGWGX')) {
    $rights = Get-SddlFileSystemRights -SddlRights $sddlRights
    if (-not (Test-AncestorFileSystemRightsSafe -Rights $rights)) {
        throw "Non-replacing generic ancestor rights '$sddlRights' were rejected."
    }
}
$genericAllRights = Get-SddlFileSystemRights -SddlRights 'GA'
if (Test-AncestorFileSystemRightsSafe -Rights $genericAllRights) {
    throw 'Replace-capable GENERIC_ALL ancestor rights were accepted.'
}

foreach ($sddl in @(
        'O:SYG:SYD:(A;OICIIO;FA;;;CO)',
        'O:SYG:SYD:(A;OICIIO;GRGX;;;BU)',
        'O:SYG:SYD:(A;;DTSD;;;WD)')) {
    $rule = Get-DirectoryAccessRuleFromSddl -Sddl $sddl
    if (-not (Test-LeafAccessRuleSafe -Rule $rule)) {
        throw "Safe leaf inheritance/access rule '$sddl' was rejected."
    }
}
foreach ($sddl in @(
        'O:SYG:SYD:(A;OICIIO;FA;;;WD)',
        'O:SYG:SYD:(A;;GW;;;WD)')) {
    $rule = Get-DirectoryAccessRuleFromSddl -Sddl $sddl
    if (Test-LeafAccessRuleSafe -Rule $rule) {
        throw "Replace-capable leaf inheritance/access rule '$sddl' was accepted."
    }
}

foreach ($invalidPath in @(
        'C:relative',
        '\rooted',
        '\\server\share',
        'relative')) {
    try {
        Assert-MsiTrustedDirectoryPath `
            -Path $invalidPath `
            -Description 'invalid test path'
        throw "Malformed path '$invalidPath' was accepted."
    }
    catch {
        if ($_.Exception.Message -notmatch
            'fully qualified local-drive') {
            throw
        }
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # This is a safety prerequisite for destructive ephemeral-runner smoke
        # tests, not a claim that enterprise known-folder redirection is invalid.
        $trustedCommonPrograms = Get-MsiTrustedKnownFolderPath `
            -FolderId $commonProgramsFolderId `
            -Description 'test Common Programs'
        if (-not [string]::Equals(
                [IO.Path]::GetFullPath($trustedCommonPrograms).TrimEnd('\'),
                [IO.Path]::GetFullPath($resolvedCommonPrograms).TrimEnd('\'),
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Trusted Common Programs validation changed the resolved path.'
        }
        $trustedCommonDesktop = Get-MsiTrustedKnownFolderPath `
            -FolderId $commonDesktopFolderId `
            -Description 'test Common Desktop'
        if (-not [string]::Equals(
                [IO.Path]::GetFullPath($trustedCommonDesktop).TrimEnd('\'),
                [IO.Path]::GetFullPath($resolvedCommonDesktop).TrimEnd('\'),
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Trusted Common Desktop validation changed the resolved path.'
        }
    }
}
finally {
    $identity.Dispose()
}

Write-Output 'Validated the machine-wide MSI Programs and Desktop known-folder contracts.'
