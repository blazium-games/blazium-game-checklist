#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for Android signing keystore validation.
.DESCRIPTION
    Dot-source this file to use Find-Keytool and Test-SigningKeystore.
    Used by Get-KeystoreFingerprint.ps1.
#>

function Find-Keytool {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe' }
    if ($env:ANDROID_HOME) {
        $candidates += Join-Path $env:ANDROID_HOME 'jre\bin\keytool.exe'
        $candidates += Join-Path $env:ANDROID_HOME '..\jre\bin\keytool.exe'
    }
    $studioPaths = @(
        "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe",
        "${env:ProgramFiles}\Android\Android Studio\jre\bin\keytool.exe",
        "${env:ProgramFiles(x86)}\Android\Android Studio\jbr\bin\keytool.exe"
    )
    $candidates += $studioPaths
    $openJdkDir = Join-Path ${env:ProgramFiles} 'Android\openjdk'
    if (Test-Path $openJdkDir) {
        $found = Get-ChildItem -Path $openJdkDir -Recurse -Filter 'keytool.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $candidates += $found.FullName }
    }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { return $p }
    }
    $inPath = Get-Command keytool -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    throw "keytool not found. Set JAVA_HOME or install Android Studio JDK."
}

function Test-SigningKeystore {
    param(
        [Parameter(Mandatory)]
        [string]$KeystorePath,
        [Parameter(Mandatory)]
        [string]$Password,
        [Parameter(Mandatory)]
        [string]$Alias,
        [string]$KeytoolPath
    )
    if (-not (Test-Path $KeystorePath)) {
        return @{ Valid = $false; Message = "Keystore not found at $KeystorePath" }
    }
    $kt = if ($KeytoolPath) { $KeytoolPath } else { Find-Keytool }
    $out = & $kt -list -v -keystore $KeystorePath -storepass $Password -alias $Alias 2>&1
    $exitCode = $LASTEXITCODE
    $outStr = $out | Out-String
    if ($exitCode -ne 0) {
        return @{ Valid = $false; Message = "keytool failed (exit $exitCode). Wrong password or alias? Output: $($outStr.Trim())" }
    }
    if (-not ($outStr -match 'SHA1:\s*([0-9A-Fa-f:]+)')) {
        return @{ Valid = $false; Message = "Could not parse SHA1 fingerprint from keytool output" }
    }
    $sha1 = $Matches[1].Trim()
    return @{ Valid = $true; Sha1 = $sha1; Message = "Keystore validated" }
}

function Get-SignedAabFingerprint {
    param(
        [Parameter(Mandatory)]
        [string]$AabPath,
        [string]$KeytoolPath
    )
    if (-not (Test-Path $AabPath)) {
        return @{ Valid = $false; Sha1 = $null; Message = "AAB not found at $AabPath" }
    }
    $kt = if ($KeytoolPath) { $KeytoolPath } else { Find-Keytool }
    $out = & $kt -printcert -jarfile $AabPath 2>&1
    $exitCode = $LASTEXITCODE
    $outStr = $out | Out-String
    if ($exitCode -ne 0) {
        return @{ Valid = $false; Sha1 = $null; Message = "keytool -printcert failed (exit $exitCode). AAB may be unsigned or corrupted. Output: $($outStr.Trim())" }
    }
    if (-not ($outStr -match 'SHA1:\s*([0-9A-Fa-f:]+)')) {
        return @{ Valid = $false; Sha1 = $null; Message = "Could not parse SHA1 fingerprint from signed AAB" }
    }
    $sha1 = $Matches[1].Trim()
    return @{ Valid = $true; Sha1 = $sha1; Message = "AAB signed with certificate SHA1: $sha1" }
}
