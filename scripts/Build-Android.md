# Android Signing Guide

A calm, step-by-step guide to getting your Android app signed and ready for Google Play. You only need a few things—this guide explains what they are and how to get them.

---

## What You Need Before Building

To build a signed release build for Google Play, you need:

| Item | Description |
|------|-------------|
| **Keystore file** | A `.jks` or `.keystore` file containing your signing key |
| **Keystore password** | The password that protects the keystore file |
| **Key alias** | The name of the key entry inside the keystore (e.g. `mykey`, `upload`) |
| **Key password** | Often the same as the keystore password; some setups use a separate key password |

That's it. Once you have these four pieces of information, you can sign your app.

---

## Where to Get or Create These

### New App (First Time)

If you've never published your app to Google Play:

1. **Generate a keystore** using one of these options:
   - **PowerShell utility:** Run `.\scripts\Generate-AndroidSigningKey.ps1` (creates keystore + credentials file). Paths and key alias are configured in `scripts/settings.json`.
   - **Manual:** Use `keytool` from the JDK:
     ```bash
     keytool -genkeypair -v -keystore my-release.keystore -alias mykey -keyalg RSA -keysize 2048 -validity 10000
     ```
   - **Android Studio:** Build → Generate Signed Bundle/APK → Create new keystore

2. **Store your credentials securely.** Write down the keystore path, password, and alias. Back them up—if you lose them, you cannot update your app on Google Play.

3. **Never commit the keystore or credentials to version control.** Add the signing directory to `.gitignore` (default: `.android-signing`; configurable in `scripts/settings.json`).

### Existing App (Already on Play)

If your app is already on Google Play:

- **Use the exact same keystore** you used for your first upload. Google Play ties your app to that key's fingerprint (SHA1).
- If you've lost the keystore, you cannot update the app. You would need to publish a new app with a new package name.
- If you have the keystore but forgot the password or alias, try to recover them from your notes or password manager.

---

## How to Verify Your Setup

Before building, it helps to confirm your keystore is valid and (if your app is already on Play) matches what Google expects.

### Check the Keystore Fingerprint (SHA1)

Google Play identifies your upload key by its SHA1 fingerprint. If you use the wrong keystore, Play will reject the upload with "Your Android App Bundle is signed with the wrong key."

**Option 1 – PowerShell utility:**
```powershell
.\scripts\Get-KeystoreFingerprint.ps1
.\scripts\Get-KeystoreFingerprint.ps1 -ExpectedSha1 "9E:26:D0:61:8D:41:1B:08:A6:E6:7E:8C:45:4A:7A:61:7D:C1:46:B9"
```
Replace the fingerprint with the one from Play Console (or from the error message).

**Option 2 – keytool:**
```bash
keytool -list -v -keystore path/to/your.keystore -alias your_alias
```
Look for the `SHA1:` line in the output.

**Compare:** The SHA1 from your keystore must match the fingerprint Google Play shows for your app's upload key (in Play Console → Your app → Setup → App signing).

---

## Before You Build – Quick Checklist

- [ ] Keystore file exists and you know its path
- [ ] You know the keystore password and key alias
- [ ] (If app is already on Play) Keystore fingerprint matches Play's expected upload key
- [ ] Keystore and credentials are backed up and not committed to git

---

## Build Command Reference

Your build tool needs the signing credentials. Here are common patterns:

### .NET / MAUI

```bash
dotnet publish YourProject.csproj -f net8.0-android -c Release \
  -p:AndroidKeyStore=true \
  -p:AndroidSigningKeyStore=/path/to/your.keystore \
  -p:AndroidSigningStorePass=YOUR_KEYSTORE_PASSWORD \
  -p:AndroidSigningKeyPass=YOUR_KEY_PASSWORD \
  -p:AndroidSigningKeyAlias=YOUR_ALIAS
```

Adjust the target framework (e.g. `net9.0-android`, `net10.0-android`) to match your project.

### Gradle (Kotlin/Java)

Configure `signingConfigs` in `android/build.gradle` or `app/build.gradle`:

```groovy
android {
    signingConfigs {
        release {
            storeFile file("path/to/your.keystore")
            storePassword System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias System.getenv("ANDROID_KEY_ALIAS")
            keyPassword System.getenv("ANDROID_KEYSTORE_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
            // ...
        }
    }
}
```

Then run:
```bash
./gradlew bundleRelease
```

Use environment variables or a local properties file for passwords—never hardcode them.

### Other Frameworks

Check your framework's docs for "Android release signing" or "sign APK/AAB". The concepts are the same: keystore path, store password, key alias, key password.

---

## Post-Build Artifacts

After a successful release build, you typically get:

| Artifact | Purpose |
|----------|---------|
| **AAB (Android App Bundle)** | Upload this to Google Play. Preferred over APK. |
| **mapping.txt** | R8/ProGuard deobfuscation mapping. Upload to Play Console so crash reports are readable. |
| **native-debug-symbols.zip** | Native debug symbols (if you use native code). Upload to Play Console for native crash symbolication. |

Play Console will prompt you to upload `mapping.txt` and native symbols when you create a release.

---

## Common Pitfalls

### "Your Android App Bundle is signed with the wrong key"

- Your keystore's SHA1 fingerprint does not match the upload key Google Play expects.
- **Fix:** Use the keystore from your first Play upload. Verify with `Get-KeystoreFingerprint.ps1` or `keytool -list -v`.

### Lost keystore or password

- Without the original keystore, you cannot update an existing app on Play.
- **Prevention:** Back up the keystore and credentials in a secure location (password manager, encrypted backup).

### CI/CD uploads fail but local builds work

- CI is likely using a different keystore or wrong credentials.
- **Fix:** Ensure your CI secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`) match your local setup. Regenerate the base64 from your keystore:
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes('path\to\your.keystore'))
  ```

### keytool not found

- `keytool` comes with the JDK. Set `JAVA_HOME` to your JDK install, or use the JDK bundled with Android Studio.

---

## Optional Utilities in This Folder

| Script | Purpose |
|--------|---------|
| `Generate-AndroidSigningKey.ps1` | Creates a new keystore and credentials file |
| `Get-KeystoreFingerprint.ps1` | Prints your keystore's SHA1 fingerprint for comparison with Play |
| `Export-PlayAppSigningKey.ps1` | Exports your key for Google Play App Signing enrollment |

All scripts read from **`scripts/settings.json`** for paths and options (signing directory, keystore filename, key alias, etc.). Edit it to match your project. Default signing directory is `.android-signing`.
