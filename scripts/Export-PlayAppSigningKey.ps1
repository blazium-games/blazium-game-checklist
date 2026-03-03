#Requires -Version 5.1
<#
.SYNOPSIS
    Exports and encrypts the Android signing key for Google Play App Signing enrollment.
.DESCRIPTION
    Downloads the PEPK tool, runs it to export the private key from the keystore,
    encrypts it with the Play Console encryption public key, and saves the output
    zip to .blazium/. Reads password and alias from .blazium/credentials.txt by
    default; prompts interactively only if credentials are missing.
.PARAMETER KeystorePath
    Path to the keystore file. Default: from scripts/settings.json
.PARAMETER OutputPath
    Path for the output zip file. Default: from scripts/settings.json
.PARAMETER EncryptionKeyPath
    Path to the encryption public key PEM file. Default: from scripts/settings.json
.PARAMETER PromptForPassword
    Ignore credentials.txt and prompt for keystore/key passwords interactively.
.EXAMPLE
    .\Export-PlayAppSigningKey.ps1
.EXAMPLE
    .\Export-PlayAppSigningKey.ps1 -PromptForPassword
#>

[CmdletBinding()]
param(
    [string]$KeystorePath,
    [string]$OutputPath,
    [string]$EncryptionKeyPath,
    [switch]$PromptForPassword
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'AndroidSigningSettings.ps1')
$settings = Get-AndroidSigningSettings

$SigningDir = $settings.SigningDirPath
if (-not $KeystorePath) { $KeystorePath = $settings.KeystorePath }
if (-not $OutputPath) { $OutputPath = Join-Path $SigningDir $settings.EncryptedKeyFilename }
if (-not $EncryptionKeyPath) { $EncryptionKeyPath = Join-Path $SigningDir $settings.EncryptionKeyFilename }

$PepkUrl = 'https://www.gstatic.com/play-apps-publisher-rapid/signing-tool/prod/pepk.jar'
$PepkPath = Join-Path $SigningDir $settings.PepkFilename
$CredentialsPath = $settings.CredentialsPath

function Find-Java {
    $candidates = @()
    if ($env:JAVA_HOME) {
        $candidates += Join-Path $env:JAVA_HOME 'bin\java.exe'
    }
    if ($env:ANDROID_HOME) {
        $candidates += Join-Path $env:ANDROID_HOME 'jre\bin\java.exe'
        $candidates += Join-Path $env:ANDROID_HOME '..\jre\bin\java.exe'
    }
    $studioPaths = @(
        "${env:ProgramFiles}\Android\Android Studio\jbr\bin\java.exe",
        "${env:ProgramFiles}\Android\Android Studio\jre\bin\java.exe",
        "${env:ProgramFiles(x86)}\Android\Android Studio\jbr\bin\java.exe"
    )
    $candidates += $studioPaths
    $openJdkDir = Join-Path ${env:ProgramFiles} 'Android\openjdk'
    if (Test-Path $openJdkDir) {
        $found = Get-ChildItem -Path $openJdkDir -Recurse -Filter 'java.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $candidates += $found.FullName }
    }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) {
            return $p
        }
    }
    $inPath = Get-Command java -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    throw "java not found. Set JAVA_HOME or install Android Studio JDK."
}

function Get-CredentialsFromFile {
    if ($PromptForPassword -or -not (Test-Path $CredentialsPath)) {
        return @{ Alias = $settings.KeyAlias; Password = $null }
    }
    $content = Get-Content $CredentialsPath -Raw
    $alias = $settings.KeyAlias
    $password = $null
    if ($content -match 'ANDROID_KEY_ALIAS=([^\r\n]+)') {
        $alias = $Matches[1].Trim()
    }
    if ($content -match 'ANDROID_KEYSTORE_PASSWORD=([^\r\n]+)') {
        $password = $Matches[1].Trim()
    }
    return @{ Alias = $alias; Password = $password }
}

function Test-EncryptionPublicKeyPem {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return $false }
    return ($content -match '-----BEGIN PUBLIC KEY-----' -and $content -match '-----END PUBLIC KEY-----')
}

function Test-PlayAppSigningZip {
    param([string]$ZipPath)
    if (-not (Test-Path $ZipPath)) { return @{ Valid = $false; Message = "Zip file not found: $ZipPath" } }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    } catch {
        return @{ Valid = $false; Message = "Could not load ZipFile: $_" }
    }
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
            $hasCert = @($entryNames | Where-Object { $_ -match 'certificate\.pem$' }).Count -gt 0
            $hasEncryptedKey = @($entryNames | Where-Object { $_ -match 'encryptedPrivateKey$' -or $_ -match 'private_key\.pepk$' }).Count -gt 0
            if (-not $hasCert) {
                return @{ Valid = $false; Message = "Zip missing certificate.pem. Found: $($entryNames -join ', ')" }
            }
            if (-not $hasEncryptedKey) {
                return @{ Valid = $false; Message = "Zip missing encryptedPrivateKey or private_key.pepk. Found: $($entryNames -join ', ')" }
            }
            $certEntry = $zip.Entries | Where-Object { $_.FullName -match 'certificate\.pem$' } | Select-Object -First 1
            if ($certEntry) {
                try {
                    $reader = New-Object System.IO.StreamReader($certEntry.Open())
                    try {
                        $certContent = $reader.ReadToEnd()
                        if (-not ($certContent -match '-----BEGIN CERTIFICATE-----')) {
                            return @{ Valid = $false; Message = "certificate.pem does not contain valid PEM certificate" }
                        }
                    } finally {
                        $reader.Dispose()
                    }
                } catch {
                    return @{ Valid = $false; Message = "Could not read certificate.pem: $_" }
                }
            }
            return @{ Valid = $true; Message = "Zip validated successfully" }
        } finally {
            $zip.Dispose()
        }
    } catch {
        return @{ Valid = $false; Message = "Invalid or corrupted zip: $_" }
    }
}

try {
    Write-Host "Export-PlayAppSigningKey: Preparing encrypted key for Google Play App Signing" -ForegroundColor Cyan
    Write-Host ""

    # Prerequisite checks
    if (-not (Test-Path $KeystorePath)) {
        Write-Error "Keystore not found at $KeystorePath. Run .\scripts\Generate-AndroidSigningKey.ps1 first."
    }

    if (-not (Test-Path $EncryptionKeyPath)) {
        Write-Error "Encryption public key not found at $EncryptionKeyPath. Download it from Google Play Console during App Signing enrollment and save it there."
    }

    if (-not (Test-EncryptionPublicKeyPem -Path $EncryptionKeyPath)) {
        Write-Error "Encryption public key at $EncryptionKeyPath is not valid PEM (missing BEGIN/END PUBLIC KEY). Download the correct key from Google Play Console."
    }
    Write-Host "Encryption public key PEM validated." -ForegroundColor Green

    [void](New-Item -ItemType Directory -Path $SigningDir -Force)

    # Remove existing output so PEPK does not fail with FileAlreadyExistsException
    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force
    }

    # Download PEPK tool
    if (-not (Test-Path $PepkPath)) {
        Write-Host "Downloading PEPK tool..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $PepkUrl -OutFile $PepkPath -UseBasicParsing
        } catch {
            Write-Error "Failed to download PEPK tool from $PepkUrl : $_"
        }
        Write-Host "  Saved to $PepkPath" -ForegroundColor Green
    } else {
        Write-Host "PEPK tool already present at $PepkPath" -ForegroundColor Green
    }

    # Find Java
    Write-Host "Resolving Java..." -ForegroundColor Cyan
    $java = Find-Java
    Write-Host "  Found: $java" -ForegroundColor Green

    # Load credentials from .blazium/credentials.txt
    $creds = Get-CredentialsFromFile
    $keyAlias = $creds.Alias
    $password = $creds.Password

    # Build PEPK arguments (use space-separated format for all value args to avoid parsing issues)
    $pepkArgs = @(
        '-jar', $PepkPath,
        '--keystore', $KeystorePath,
        '--alias', $keyAlias,
        '--output', $OutputPath,
        '--include-cert',
        '--rsa-aes-encryption',
        '--encryption-key-path', $EncryptionKeyPath
    )

    if ($password) {
        # Google PEPK expects password directly (no pass: prefix)
        $pepkArgs += '--keystore-pass'
        $pepkArgs += $password
        $pepkArgs += '--key-pass'
        $pepkArgs += $password
        Write-Host "Using credentials from $CredentialsPath (alias: $keyAlias)" -ForegroundColor Yellow
    } else {
        Write-Host "You will be prompted for keystore and key passwords." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Running PEPK..." -ForegroundColor Cyan
    & $java $pepkArgs
    if ($LASTEXITCODE -ne 0) {
        throw "PEPK exited with code $LASTEXITCODE"
    }

    if (-not (Test-Path $OutputPath)) {
        throw "Output zip was not created at $OutputPath"
    }

    $zipValidation = Test-PlayAppSigningZip -ZipPath $OutputPath
    if (-not $zipValidation.Valid) {
        Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        throw "PEPK output validation failed: $($zipValidation.Message)"
    }
    Write-Host "Output zip validated (certificate.pem + encrypted key present)." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== Success ===" -ForegroundColor Green
    Write-Host "Encrypted key saved to: $OutputPath"
    Write-Host ""
    Write-Host "Next step: Upload this zip file to Google Play Console during App Signing enrollment."
    Write-Host "  (Play Console > Your app > Setup > App signing > Upload a key exported from a Java keystore)"
    Write-Host ""
    Write-Host "Keep $SigningDir secure and never commit it." -ForegroundColor Green
} catch {
    Write-Error $_
    exit 1
}
