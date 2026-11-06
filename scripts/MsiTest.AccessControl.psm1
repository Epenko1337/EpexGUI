Set-StrictMode -Version Latest

# GENERIC_READ and GENERIC_EXECUTE have no FileSystemRights enum names.
[Int64]$safeFileSystemRightsMask =
    [Int64][Security.AccessControl.FileSystemRights]::ReadAndExecute -bor
    [Int64][Security.AccessControl.FileSystemRights]::Synchronize -bor
    0x80000000L -bor
    0x20000000L
[Int64]$safeNonReplacingFileSystemRightsMask =
    $safeFileSystemRightsMask -bor
    [Int64][Security.AccessControl.FileSystemRights]::Delete -bor
    [Int64][Security.AccessControl.FileSystemRights]::
        DeleteSubdirectoriesAndFiles

function Test-MsiWriteCapableFileSystemRights {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemRights]$Rights
    )

    # FileSystemRights omits names for the raw GENERIC_* access-mask bits and
    # represents GENERIC_READ as a negative enum value. Normalize to the native
    # 32-bit mask and fail closed on everything except read/execute/synchronize.
    [Int64]$normalizedRights = [Int64]$Rights -band 0xffffffffL
    return (
        ($normalizedRights -band $safeFileSystemRightsMask) -ne
        $normalizedRights)
}

function Test-MsiReplacementCapableFileSystemRights {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemRights]$Rights
    )

    # A delete-only ACE can make an entry unavailable, but cannot replace it
    # when its parent is protected against untrusted entry creation. Keep that
    # distinction separate from the stricter write-capable classifier.
    [Int64]$normalizedRights = [Int64]$Rights -band 0xffffffffL
    return (
        ($normalizedRights -band $safeNonReplacingFileSystemRightsMask) -ne
        $normalizedRights)
}

function Test-MsiSecurityDescriptorHasNonNullDacl {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemSecurity]$Security
    )

    try {
        $binaryDescriptor = $Security.GetSecurityDescriptorBinaryForm()
        $rawDescriptor =
            [Security.AccessControl.RawSecurityDescriptor]::new(
                $binaryDescriptor,
                0)
        return (
            ($rawDescriptor.ControlFlags -band
                [Security.AccessControl.ControlFlags]::
                    DiscretionaryAclPresent) -ne 0 -and
            $null -ne $rawDescriptor.DiscretionaryAcl)
    }
    catch {
        return $false
    }
}

function Test-MsiExactPayloadAccessControl {
    param(
        [Parameter(Mandatory = $true)]
        [Security.AccessControl.FileSystemSecurity]$Security,

        [switch]$Directory
    )

    try {
        if (-not (Test-MsiSecurityDescriptorHasNonNullDacl `
                -Security $Security) -or
            -not $Security.AreAccessRulesProtected -or
            $Security.GetOwner(
                [Security.Principal.SecurityIdentifier]).Value -cne
                'S-1-5-32-544' -or
            $Security.GetGroup(
                [Security.Principal.SecurityIdentifier]).Value -cne
                'S-1-5-18') {
            return $false
        }

        $directoryInheritanceFlags =
            [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                [Security.AccessControl.InheritanceFlags]::ObjectInherit
        $expectedRuleSignatures =
            New-Object 'System.Collections.Generic.HashSet[string]' (
                [StringComparer]::Ordinal)
        $expectedRules = @(
            [pscustomobject]@{
                Sid = 'S-1-5-18'
                Rights = 0x001f01ffL
                Inheritance = if ($Directory) {
                    $directoryInheritanceFlags
                }
                else {
                    [Security.AccessControl.InheritanceFlags]::None
                }
                Propagation =
                    [Security.AccessControl.PropagationFlags]::None
            },
            [pscustomobject]@{
                Sid = 'S-1-5-32-544'
                Rights = 0x001f01ffL
                Inheritance = if ($Directory) {
                    $directoryInheritanceFlags
                }
                else {
                    [Security.AccessControl.InheritanceFlags]::None
                }
                Propagation =
                    [Security.AccessControl.PropagationFlags]::None
            },
            [pscustomobject]@{
                Sid = 'S-1-5-32-545'
                # Windows Installer maps GR | GX to FILE_GENERIC_READ |
                # FILE_GENERIC_EXECUTE while retaining the authored
                # inheritance flags on directory ACEs.
                Rights = 0x001200a9L
                Inheritance = if ($Directory) {
                    $directoryInheritanceFlags
                }
                else {
                    [Security.AccessControl.InheritanceFlags]::None
                }
                Propagation =
                    [Security.AccessControl.PropagationFlags]::None
            }
        )
        foreach ($expectedRule in $expectedRules) {
            $signature = '{0}|{1:X8}|{2}|{3}' -f
                $expectedRule.Sid,
                [Int64]$expectedRule.Rights,
                [int]$expectedRule.Inheritance,
                [int]$expectedRule.Propagation
            if (-not $expectedRuleSignatures.Add($signature)) {
                return $false
            }
        }

        $rules = @(
            $Security.GetAccessRules(
                $true,
                $true,
                [Security.Principal.SecurityIdentifier])
        )
        if ($rules.Count -ne $expectedRuleSignatures.Count) {
            return $false
        }

        foreach ($rule in $rules) {
            $sid = $rule.IdentityReference.Value
            [Int64]$normalizedRights =
                [Int64]$rule.FileSystemRights -band 0xffffffffL
            $signature = '{0}|{1:X8}|{2}|{3}' -f
                $sid,
                $normalizedRights,
                [int]$rule.InheritanceFlags,
                [int]$rule.PropagationFlags
            if ($rule.IsInherited -or
                $rule.AccessControlType -ne
                    [Security.AccessControl.AccessControlType]::Allow -or
                -not $expectedRuleSignatures.Remove($signature)) {
                return $false
            }
        }
        return $expectedRuleSignatures.Count -eq 0
    }
    catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Test-MsiExactPayloadAccessControl',
    'Test-MsiReplacementCapableFileSystemRights',
    'Test-MsiSecurityDescriptorHasNonNullDacl',
    'Test-MsiWriteCapableFileSystemRights'
)
