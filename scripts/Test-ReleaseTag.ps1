[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z')]
    [string] $Repository,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $GitHubApiUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('\Arelease-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z')]
    [string] $ReleaseTag,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[0-9a-f]{40}\z')]
    [string] $TrustedSha,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[0-9a-f]{40}\z')]
    [string] $TrustedTagOid
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    throw 'GH_TOKEN is required to revalidate the authorized release tag.'
}
if ($Repository -cne 'wiresock/WireSockUI') {
    throw "Release trust validation may run only for canonical repository 'wiresock/WireSockUI', not '$Repository'."
}

$apiUri = $null
if (-not [Uri]::TryCreate($GitHubApiUrl, [UriKind]::Absolute, [ref]$apiUri) -or
    $apiUri.Scheme -cne 'https' -or
    $apiUri.DnsSafeHost -cne 'api.github.com' -or
    -not $apiUri.IsDefaultPort -or
    -not [string]::IsNullOrEmpty($apiUri.UserInfo) -or
    -not [string]::IsNullOrEmpty($apiUri.Query) -or
    -not [string]::IsNullOrEmpty($apiUri.Fragment) -or
    $apiUri.AbsolutePath.Trim('/') -ne '') {
    throw 'GitHubApiUrl must be an absolute HTTPS API origin without credentials, a custom port, path, query, or fragment.'
}

$headers = @{
    Accept = 'application/vnd.github+json'
    Authorization = "Bearer $env:GH_TOKEN"
    'X-GitHub-Api-Version' = '2026-03-10'
}
$apiRoot = $GitHubApiUrl.TrimEnd('/')
$encodedTag = [Uri]::EscapeDataString($ReleaseTag)

$tagRef = Invoke-RestMethod `
    -Method Get `
    -Headers $headers `
    -TimeoutSec 30 `
    -Uri "$apiRoot/repos/$Repository/git/ref/tags/$encodedTag"
if ([string]$tagRef.ref -cne "refs/tags/$ReleaseTag" -or
    [string]$tagRef.object.type -cne 'tag' -or
    [string]$tagRef.object.sha -cne $TrustedTagOid) {
    throw "Release tag '$ReleaseTag' no longer names authorized annotated-tag object '$TrustedTagOid'."
}

$tagObject = Invoke-RestMethod `
    -Method Get `
    -Headers $headers `
    -TimeoutSec 30 `
    -Uri "$apiRoot/repos/$Repository/git/tags/$TrustedTagOid"
if ([string]$tagObject.sha -cne $TrustedTagOid -or
    [string]$tagObject.tag -cne $ReleaseTag -or
    $tagObject.verification.verified -ne $true -or
    [string]$tagObject.object.type -cne 'commit' -or
    [string]$tagObject.object.sha -cne $TrustedSha) {
    throw "Release tag '$ReleaseTag' changed after authorization or is no longer a GitHub-verified tag for '$TrustedSha'."
}

$mainRef = Invoke-RestMethod `
    -Method Get `
    -Headers $headers `
    -TimeoutSec 30 `
    -Uri "$apiRoot/repos/$Repository/git/ref/heads/main"
if ([string]$mainRef.ref -cne 'refs/heads/main' -or
    [string]$mainRef.object.type -cne 'commit' -or
    [string]$mainRef.object.sha -cne $TrustedSha) {
    throw "Protected branch 'refs/heads/main' no longer names authorized release commit '$TrustedSha'."
}

Write-Output "Revalidated release tag '$ReleaseTag', annotated object '$TrustedTagOid', and current main commit '$TrustedSha'."
