# Scripts

This folder helps developers get Android signing requirements in order. **Start with the [Build-Android guide](Build-Android.md)** if you're new—it explains what you need (keystore, password, alias, fingerprint) and how to verify your setup.

## Configuration

All scripts read from **`scripts/settings.json`** (create it if missing; defaults apply). Customize it for your project:

| Key | Description | Default |
|-----|-------------|---------|
| `signing_dir` | Directory for keystore and credentials (relative to project root) | `.android-signing` |
| `keystore_filename` | Keystore file name | `release.keystore` |
| `credentials_filename` | Credentials file name | `credentials.txt` |
| `key_alias` | Default key alias for new keystores | `release` |
| `certificate_dname` | Certificate DN (CN, OU, O, L, ST, C) for new keystores | Generic template |
| `export.*` | Export script filenames (encrypted_key_filename, etc.) | See settings.json |

**Existing projects:** If you use `.blazium/`, set `"signing_dir": ".blazium"` in settings.json. Add the signing directory to `.gitignore` and never commit it.

## Before You Build – Quick Checklist

- [ ] Keystore exists and you know its path
- [ ] You know the keystore password and key alias
- [ ] (If app is already on Play) Keystore fingerprint matches Play's expected upload key
- [ ] Keystore and credentials are backed up and never committed to git

---

## Build-Android Guide

**[Build-Android.md](Build-Android.md)** – A step-by-step guide covering:

- What you need before building (keystore, password, alias)
- Where to get or create these (new app vs existing app)
- How to verify your setup (fingerprint, keytool)
- Build command reference for .NET/MAUI and Gradle
- Post-build artifacts (AAB, mapping.txt, native-debug-symbols.zip)
- Common pitfalls and fixes

No project-specific code—use it for any Android project.

---

## Generate-AndroidSigningKey.ps1

Generates an Android release signing keystore and credentials file. Use this when starting a new app.

### Prerequisites

- **keytool** from JDK (via `JAVA_HOME`, `ANDROID_HOME`, or Android Studio's bundled JDK)
- PowerShell 5.1 or later

### Usage

From the project root:

```powershell
.\scripts\Generate-AndroidSigningKey.ps1
```

Or from the `scripts` folder:

```powershell
.\Generate-AndroidSigningKey.ps1
```

Use `-Force` to overwrite existing keystore and credentials without prompting:

```powershell
.\scripts\Generate-AndroidSigningKey.ps1 -Force
```

### Output

All artifacts are written to the signing directory (from `settings.json`, default `.android-signing/`):

- `release.keystore` – the signing keystore (or `keystore_filename` from settings)
- `credentials.txt` – password and alias (restrict with file permissions)

### GitHub Secrets (for CI/CD)

After running the script, add these repository secrets:

| Secret | Source |
|--------|--------|
| `ANDROID_KEY_ALIAS` | From credentials.txt |
| `ANDROID_KEYSTORE_PASSWORD` | From credentials.txt |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the keystore file |

To get the base64 value (replace path with your keystore from settings):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('.android-signing\release.keystore'))
```

### Security

- Never commit the signing directory or its contents (add it to `.gitignore`)
- Back up the keystore and password securely; loss prevents app updates on Google Play
- The script uses cryptographically secure random password generation

---

## Get-KeystoreFingerprint.ps1

Prints the SHA1 fingerprint of your Android signing keystore. Use this to verify your keystore matches what Google Play expects before building or uploading.

```powershell
.\scripts\Get-KeystoreFingerprint.ps1
.\scripts\Get-KeystoreFingerprint.ps1 -ExpectedSha1 "9E:26:D0:61:8D:41:1B:08:A6:E6:7E:8C:45:4A:7A:61:7D:C1:46:B9"
```

Replace the fingerprint with the one from Play Console or the error message.

---

## Export-PlayAppSigningKey.ps1

Exports and encrypts the Android signing key for Google Play App Signing enrollment. Downloads the PEPK tool, runs it to export the private key from the keystore, encrypts it with the Play Console encryption public key, and saves the output zip.

### Prerequisites

- Keystore (path from `settings.json`, or override with `-KeystorePath`)
- `credentials.txt` from `Generate-AndroidSigningKey.ps1` (for password and alias)
- `encryption_public_key.pem` from Google Play Console (during App Signing enrollment)
- **Java** (JDK 8+) via `JAVA_HOME`, `ANDROID_HOME`, or Android Studio's bundled JDK
- PowerShell 5.1 or later

### Usage

From the project root:

```powershell
.\scripts\Export-PlayAppSigningKey.ps1
```

By default, the script reads `ANDROID_KEY_ALIAS` and `ANDROID_KEYSTORE_PASSWORD` from the credentials file (path from `settings.json`). Use `-PromptForPassword` to ignore credentials and prompt interactively instead.

### Output

- `encrypted_private_key.zip` – upload this to Google Play Console during App Signing enrollment
- `pepk.jar` – the PEPK tool (downloaded once, cached in the signing directory)

### Optional Parameters

| Parameter | Description |
|-----------|-------------|
| `-KeystorePath` | Override keystore path |
| `-OutputPath` | Override output zip path |
| `-EncryptionKeyPath` | Override encryption public key path |
| `-PromptForPassword` | Ignore credentials.txt and prompt for passwords |

---

## Google Play Deploy (CI/CD)

If you use GitHub Actions or similar to upload to Google Play:

### Prerequisites

1. **Create the app in Google Play Console**
   - Go to [Google Play Console](https://play.google.com/console)
   - Create app → Use a package name that matches your project's `ApplicationId`
   - Complete required store listing (app name, short description, etc.)

2. **Create a Google Cloud service account**
   - [Google Cloud Console](https://console.cloud.google.com) → IAM & Admin → Service accounts → Create
   - Enable [Google Play Android Developer API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com)
   - Create a JSON key for the service account and store it in GitHub secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

3. **Add service account to Play Console**
   - Play Console → Users and permissions → Invite new user
   - Add the service account email (e.g. `xxx@project.iam.gserviceaccount.com`)
   - Grant **Release to production, exclude devices, and use Play App Signing** (or equivalent release permissions)
   - Under **App permissions**, grant access to your app

4. **Initial manual upload (required)**
   - The Play API cannot create a new package; it can only update an existing one
   - Build an AAB locally or via CI, then upload it manually in Play Console:
     - Release → Testing → Internal testing → Create new release
     - Upload the AAB, add release notes, and save
   - After this first upload, automated deploy workflows can upload subsequent releases

### GitHub Secrets

| Secret | Description |
|--------|-------------|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Full JSON content of the service account key file |
| `EXPECTED_PLAY_UPLOAD_FINGERPRINT` | (Optional) SHA1 fingerprint Google Play expects. If set, CI can verify the keystore before building. Example: `9E:26:D0:61:8D:41:1B:08:A6:E6:7E:8C:45:4A:7A:61:7D:C1:46:B9` |

### Wrong signing key error

If Google Play rejects the upload with **"Your Android App Bundle is signed with the wrong key"**:

1. **Verify your keystore locally:**
   ```powershell
   .\scripts\Get-KeystoreFingerprint.ps1 -ExpectedSha1 "FINGERPRINT_FROM_PLAY_CONSOLE"
   ```
   Replace the fingerprint with the one from the Play Console error.

2. **If local keystore matches but CI uploads fail** – The GitHub secret `ANDROID_KEYSTORE_BASE64` likely has a different keystore. Update it with the base64 of your local keystore:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes('path\to\your.keystore'))
   ```
   Copy the output and update the `ANDROID_KEYSTORE_BASE64` secret in GitHub (Settings → Secrets and variables → Actions).

3. **If local keystore does not match** – Replace your keystore with the original used for the first Play upload, update credentials, and sync GitHub secrets.

4. **Optional: add expected fingerprint to CI** – Add `EXPECTED_PLAY_UPLOAD_FINGERPRINT` (the SHA1 from Play Console) as a GitHub secret so CI fails early if the wrong keystore is used.
