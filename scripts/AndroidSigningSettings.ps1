#Requires -Version 5.1
<#
.SYNOPSIS
    Loads Android signing configuration from settings.json with defaults.
.DESCRIPTION
    Dot-source this file, then call Get-AndroidSigningSettings to get a merged
    config. Used by Generate-AndroidSigningKey, Get-KeystoreFingerprint, Export-PlayAppSigningKey.
#>

function Get-AndroidSigningSettings {
    $ScriptsDir = $PSScriptRoot
    $ProjectRoot = Split-Path -Parent $ScriptsDir
    $SettingsPath = Join-Path $ScriptsDir 'settings.json'

    $defaults = @{
        signing_dir             = '.android-signing'
        keystore_filename       = 'release.keystore'
        credentials_filename    = 'credentials.txt'
        key_alias               = 'release'
        key_algorithm           = 'RSA'
        key_size                = 2048
        validity_days           = 10000
        password_length         = 40
        certificate_dname       = @{ CN = 'My App'; OU = 'Development'; O = 'My Company'; L = 'City'; ST = 'State'; C = 'US' }
        encrypted_key_filename  = 'encrypted_private_key.zip'
        encryption_key_filename = 'encryption_public_key.pem'
        pepk_filename           = 'pepk.jar'
    }

    $result = @{
        ProjectRoot             = $ProjectRoot
        SigningDir              = $null
        SigningDirPath          = $null
        KeystorePath            = $null
        CredentialsPath         = $null
        KeyAlias                = $defaults.key_alias
        KeyAlgorithm           = $defaults.key_algorithm
        KeySize                 = $defaults.key_size
        ValidityDays            = $defaults.validity_days
        PasswordLength          = $defaults.password_length
        CertificateDname       = $null
        EncryptedKeyFilename    = $defaults.encrypted_key_filename
        EncryptionKeyFilename   = $defaults.encryption_key_filename
        PepkFilename            = $defaults.pepk_filename
    }

    if (Test-Path $SettingsPath) {
        try {
            $json = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warning "Could not parse settings.json: $_"
        }
        if ($json) {
            if ($json.PSObject.Properties['signing_dir']) { $result.SigningDir = $json.signing_dir }
            if ($json.PSObject.Properties['keystore_filename']) { $result.KeystoreFilename = $json.keystore_filename }
            if ($json.PSObject.Properties['credentials_filename']) { $result.CredentialsFilename = $json.credentials_filename }
            if ($json.PSObject.Properties['key_alias']) { $result.KeyAlias = $json.key_alias }
            if ($json.PSObject.Properties['key_algorithm']) { $result.KeyAlgorithm = $json.key_algorithm }
            if ($json.PSObject.Properties['key_size']) { $result.KeySize = [int]$json.key_size }
            if ($json.PSObject.Properties['validity_days']) { $result.ValidityDays = [int]$json.validity_days }
            if ($json.PSObject.Properties['password_length']) { $result.PasswordLength = [int]$json.password_length }
            if ($json.PSObject.Properties['certificate_dname']) {
                $dn = $json.certificate_dname
                $result.CertificateDname = @{
                    CN = if ($dn.PSObject.Properties['CN']) { $dn.CN } else { $defaults.certificate_dname.CN }
                    OU = if ($dn.PSObject.Properties['OU']) { $dn.OU } else { $defaults.certificate_dname.OU }
                    O  = if ($dn.PSObject.Properties['O']) { $dn.O } else { $defaults.certificate_dname.O }
                    L  = if ($dn.PSObject.Properties['L']) { $dn.L } else { $defaults.certificate_dname.L }
                    ST = if ($dn.PSObject.Properties['ST']) { $dn.ST } else { $defaults.certificate_dname.ST }
                    C  = if ($dn.PSObject.Properties['C']) { $dn.C } else { $defaults.certificate_dname.C }
                }
            }
            if ($json.PSObject.Properties['export']) {
                $exp = $json.export
                if ($exp.PSObject.Properties['encrypted_key_filename']) { $result.EncryptedKeyFilename = $exp.encrypted_key_filename }
                if ($exp.PSObject.Properties['encryption_key_filename']) { $result.EncryptionKeyFilename = $exp.encryption_key_filename }
                if ($exp.PSObject.Properties['pepk_filename']) { $result.PepkFilename = $exp.pepk_filename }
            }
        }
    }

    if (-not $result.SigningDir) { $result.SigningDir = $defaults.signing_dir }
    if (-not $result.KeystoreFilename) { $result.KeystoreFilename = $defaults.keystore_filename }
    if (-not $result.CredentialsFilename) { $result.CredentialsFilename = $defaults.credentials_filename }
    if (-not $result.CertificateDname) { $result.CertificateDname = $defaults.certificate_dname }
    if (-not $result.EncryptedKeyFilename) { $result.EncryptedKeyFilename = $defaults.encrypted_key_filename }
    if (-not $result.EncryptionKeyFilename) { $result.EncryptionKeyFilename = $defaults.encryption_key_filename }
    if (-not $result.PepkFilename) { $result.PepkFilename = $defaults.pepk_filename }

    $result.SigningDirPath = Join-Path $ProjectRoot $result.SigningDir
    $result.KeystorePath = Join-Path $result.SigningDirPath $result.KeystoreFilename
    $result.CredentialsPath = Join-Path $result.SigningDirPath $result.CredentialsFilename

    return $result
}

function Get-CertificateDnameString {
    param([hashtable]$Dname)
    $parts = @()
    if ($Dname.CN) { $parts += "CN=$($Dname.CN)" }
    if ($Dname.OU) { $parts += "OU=$($Dname.OU)" }
    if ($Dname.O) { $parts += "O=$($Dname.O)" }
    if ($Dname.L) { $parts += "L=$($Dname.L)" }
    if ($Dname.ST) { $parts += "ST=$($Dname.ST)" }
    if ($Dname.C) { $parts += "C=$($Dname.C)" }
    return $parts -join ', '
}
