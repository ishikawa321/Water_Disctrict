# Android APK release

The downloadable app is the existing Flutter application, not a wrapper around the website. It uses the same Supabase project, identities, account links, permissions and saved records. Current mobile sign-in supports Consumer and Admin profiles; Staff use the office web/desktop workspace. The APK does not create accounts, seed data, host a database or fix an unhosted office API.

Public version: **1.0.1**, build **2**. Application ID: `ph.maramag.waterdistrictconnect`. Android 7.0 / API 24 or later. The universal APK includes ARM32, ARM64 and x86-64. App name and launcher use Water District Connect and the existing district logo.

Published: [download and installation page](https://maramag-waterdistrict-web.vercel.app/download), [GitHub release](https://github.com/ishikawa321/Water_Disctrict/releases/tag/android-v1.0.1). GitHub verified both uploaded asset digests before publication. A fresh public, unauthenticated download of the full 57,785,128-byte APK matched SHA-256 `637244eb7ee2871d78722025179c6c47193e81f4cbd2072bdba4d9110ab46303`; the public checksum sidecar matched too.

## Build and signing

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-android-release.ps1 -FlutterExecutable C:/src/flutter/bin/flutter.bat
```

The Windows script creates the release key once under `%USERPROFILE%\.waterdistrict\android-release`, restricts that directory to the current Windows user, and reuses the same certificate for every future build. **Back up that entire directory privately**, including the encrypted keystore and its `key.properties` credentials. Losing it prevents signing compatible updates. These files must never be uploaded to GitHub releases, Vercel, chat or source control. The script refuses to silently replace a keystore whose credentials are missing.

Gradle reads the external credentials path from `WATERDISTRICT_ANDROID_SIGNING_PROPERTIES`, or an ignored `android/key.properties`. CI can instead supply `WATERDISTRICT_ANDROID_KEYSTORE`, `WATERDISTRICT_ANDROID_STORE_PASSWORD`, `WATERDISTRICT_ANDROID_KEY_ALIAS` and `WATERDISTRICT_ANDROID_KEY_PASSWORD` from its secret store. Release builds no longer fall back to Android's debug key. Debug development remains available without release credentials.

The APK is written to `artifacts/android/WaterDistrictConnect-1.0.1.apk`, with a SHA-256 sidecar. Dart split symbols stay under ignored build/artifact directories. The old `com.example.water_district_connect` app uses another ID/key, so this public release installs separately; sign in again using the existing account. Future public releases must keep the new ID/key and increment the version/build number.

## Publish and website handoff

After checking the APK signature/package/version and updating `web/src/lib/android-release.json` from the actual artifact, commit the Android source and run:

```powershell
python scripts/publish-android-release.py --publish
```

The publisher reuses the existing GitHub login through Git Credential Manager without printing credentials. It validates the APK hash/size and clean committed Android source, creates a draft release, uploads only the signed APK and checksum, verifies GitHub's returned asset digests, then publishes. It never overwrites existing public assets. Without `--publish`, it only validates locally. Use a new version for a changed binary.

The expected release is [android-v1.0.1](https://github.com/ishikawa321/Water_Disctrict/releases/tag/android-v1.0.1). The landing's **Download for Android** actions open `/download`, with version, actual size, installation instructions, minimum Android version and a checksum. **Explore Demo** continues to open `/app` and then the appropriate signed-in workspace or clean login. Both the adjacent original landing and its integrated snapshot are updated through `web/scripts/sync-landing.mjs`.

The APK is hosted as a GitHub Release asset. APK binaries, private signing files and Flutter build outputs are excluded from Vercel uploads; Vercel serves the download page and existing web application.

## Verification and limits

The 1.0.1 APK release build succeeded. Android Build Tools verified its APK Signature Scheme v2 signature, 3072-bit RSA project release certificate, non-debuggable manifest, package ID, build/version, API 24 minimum and universal architecture list. The actual digest/size and certificate fingerprint are recorded in `web/src/lib/android-release.json`. No Android device was connected, so physical installation and real-user sign-in were not claimed. Existing isolated Flutter tests cover the mobile flows; browser checks cover the landing/download links and responsive instructions.

The app requires internet and an existing authorized account. Password recovery uses the existing `waterdistrictconnect://reset-password/` deep link and still depends on the project's Auth redirect/email configuration. For the separate Admin/Staff server connection, see [office-api-hosting.md](office-api-hosting.md).

References: [Flutter Android releases](https://docs.flutter.dev/deployment/android), [Android app signing](https://developer.android.com/studio/publish/app-signing), [website APK distribution](https://developer.android.com/distribute/marketing-tools/alternative-distribution).
