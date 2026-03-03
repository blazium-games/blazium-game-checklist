#Requires -Version 5.1
<#
.SYNOPSIS
    Prints the SHA1 fingerprint of the Android signing keystore for comparison with Google Play.
.DESCRIPTION
    Use this to verify your keystore matches what Google Play expects. If Play Console
    reports "signed with the wrong key", compare the expected fingerprint from the
    error with the output of this script.
.EXAMPLE
    .\Get-KeystoreFingerprint.ps1
.EXAMPLE
    .\Get-KeystoreFingerprint.ps1 -ExpectedSha1 "9E:26:D0:61:8D:41:1B:08:A6:E6:7E:8C:45:4A:7A:61:7D:C1:46:B9"
#>

[CmdletBinding()]
param(
    [string]$KeystorePath,
    [string]$ExpectedSha1  # e.g. "9E:26:D0:61:8D:41:1B:08:A6:E6:7E:8C:45:4A:7A:61:7D:C1:46:B9"
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BlaziumDir = Join-Path $ProjectRoot '.blazium'
if (-not $KeystorePath) { $KeystorePath = Join-Path $BlaziumDir 'blazium.keystore' }
$CredentialsPath = Join-Path $BlaziumDir 'credentials.txt'

. (Join-Path $PSScriptRoot 'AndroidSigningHelpers.ps1')

if (-not (Test-Path $KeystorePath)) {
    Write-Error "Keystore not found at $KeystorePath"
}

$cred = Get-Content $CredentialsPath -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ANDROID_' }
$password = ($cred | Where-Object { $_ -match '^ANDROID_KEYSTORE_PASSWORD=' }) -replace '^ANDROID_KEYSTORE_PASSWORD=',''
$alias = ($cred | Where-Object { $_ -match '^ANDROID_KEY_ALIAS=' }) -replace '^ANDROID_KEY_ALIAS=',''

if (-not $password -or -not $alias) {
    Write-Error "Could not parse ANDROID_KEYSTORE_PASSWORD or ANDROID_KEY_ALIAS from $CredentialsPath"
}

$result = Test-SigningKeystore -KeystorePath $KeystorePath -Password $password -Alias $alias
if (-not $result.Valid) {
    Write-Error $result.Message
}
$actualSha1 = $result.Sha1
Write-Host "`nKeystore SHA1 fingerprint:" -ForegroundColor Cyan
Write-Host "  $actualSha1" -ForegroundColor White
if ($ExpectedSha1) {
    $expectedNorm = ($ExpectedSha1 -replace '\s','').ToUpperInvariant()
    $actualNorm = ($actualSha1 -replace '\s','').ToUpperInvariant()
    if ($expectedNorm -eq $actualNorm) {
        Write-Host "`n  MATCHES expected (Google Play will accept this keystore)." -ForegroundColor Green
    } else {
        Write-Host "`n  DOES NOT MATCH expected: $ExpectedSha1" -ForegroundColor Red
        Write-Host "  Replace .blazium/blazium.keystore with the original keystore used for the first Play upload." -ForegroundColor Yellow
    }
}
