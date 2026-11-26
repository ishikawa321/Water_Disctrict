# Android APK release

## Current release: 1.0.4 build 5

Fixes the Android release-only startup error reported as `Bda` on a first installation. The 1.0.3 APK was reproduced on an isolated Android 15 emulator, and logcat identified a missing `SharedPreferencesApiRegistrar.getAll` JNI method during Supabase initialization. The Android preferences dependency is now constrained to 2.5.5 or newer, with compatible JNI versions locked. Startup errors offer Retry instead of an obfuscated class name.

The actual signed 1.0.4 APK reaches the sign-in form after updating over the failing 1.0.3 installation and after clearing the isolated emulator's app data for a fresh-start test. Android UIAutomator confirmed the ready sign-in state and corrected-release logcat contains no native preferences exception. No physical-device test or real-user login is claimed. See [startup and billing refresh details](android-startup-and-bill-sync.md).

Artifact: `WaterDistrictConnect-1.0.4.apk`, 63,192,212 bytes, SHA-256 `01e731284c5464d2e48bd63ab920700bedf90fb9b099f7f945af0f4c23b19422`. Android Build Tools verified version/code 1.0.4/5, the v2 signature, non-debuggable manifest, API 24 minimum and ARM32/ARM64/x86-64 Flutter libraries. The application ID and release certificate remain unchanged, allowing installation as an update. Private signing files and versioned split symbols remain local.

The main-branch Flutter app and website refresh issued Consumer bills and balances automatically, including bills with future due dates. All bills is the default Flutter list. Monthly plans still issue on the 28th; saving a plan never creates an early charge. No new SQL migration is required.

Verification: Flutter analysis passed; all 49 Flutter tests, all 23 web Chrome workflows, 80 web unit checks, TypeScript, ESLint and the optimized production build passed. The final 1.0.4 website download metadata also passed its browser workflow.

Published [Android 1.0.4](https://github.com/ishikawa321/Water_Disctrict/releases/tag/android-v1.0.4) from `11b76dd` on `main`. Both uploaded asset digests were verified, and a fresh public download matched all 63,192,212 bytes and the exact SHA-256 above. The old 1.0.3 release notes now direct users to 1.0.4 without changing its historical assets. Ready Vercel deployment `dpl_ApFNRvMcj6eZ853cv7BHAKvWgMur` was promoted to https://maramag-waterdistrict-web.vercel.app after the APK became public. Production Chrome confirmed the current download/version/checksum, narrow layout, clean sign-in and protected billing PDF route. The main-branch Flutter app was also served and browser-checked at http://127.0.0.1:3000.

## Superseded release: 1.0.3 build 4

This historical APK has a confirmed Android first-install startup failure. Install 1.0.4 or later instead. The details below record its original release checks, which did not catch the native storage-plugin failure.

Built from the merged main/web and `UI-Redesign` sources on 2026-11-27. This release adds the updated #00479D application design, guided navigation, announcement indicators and Client/Admin billing-history PDF sharing. Existing invited Staff sign-in, payment confirmation, assigned repairs and Admin-only final repair confirmation are retained. Admin repair shortcuts use the reviewed Staff workspace rather than the older repair editor.

The signed universal artifact is `WaterDistrictConnect-1.0.3.apk`, 63,356,052 bytes, SHA-256 `cc1d9a4f48a1e8a0b46007c4b0b3bac6873ad0b770ac21f19d0a8aa9d11c0deb`. Package ID remains `ph.maramag.waterdistrictconnect`, Android 7/API 24 minimum, with ARM32/ARM64/x86-64 Flutter libraries. Android Build Tools verified the v2 signature, version 1.0.3/code 4, non-debuggable manifest and unchanged certificate SHA-256 `db12f986c9cccb39734b5d2f15f1f43e5aa9d80bae008e0c9e86a5cd2aea0650`. Both icon fonts are bundled. It can update earlier public releases without uninstalling the app. Release symbols are archived locally under `artifacts/android/symbols/1.0.3` and are not public assets.

Flutter analysis passed without issues and all 46 tests passed, including Staff permissions, Admin confirmation, Client/Admin PDF export, large amounts, multi-account PDF sections and narrow/large-text layouts. The PDF samples were extracted and visually reviewed. The visual audit was repeated after correcting the incoming low-contrast billing filters and loading icon fonts from the actual test asset bundle. Tests use isolated HTTP fixtures; no operational records were created. A physical-device install is not claimed.

The website keeps its existing Admin/Staff individual and filtered-list PDF exports, and `/download` now identifies this APK using its verified size and checksum. No new Supabase migration is needed for these UI/PDF changes; the existing Staff/billing setup remains required.

Web verification passed: landing JavaScript checks, route type generation, TypeScript, ESLint with zero warnings, all 80 unit checks, all 22 Chrome workflows and the optimized production build. The download test reads the current release metadata and verifies the link, checksum, installation page and browser download filename.

Published [Android 1.0.3](https://github.com/ishikawa321/Water_Disctrict/releases/tag/android-v1.0.3) from source `ffcf9b1`, now on both `main` (the Flutter app source) and `feature/web-platform-parity`. GitHub verified both uploaded asset digests. A fresh anonymous download of the full APK matched the exact size/hash above; the checksum sidecar matched too. The [website download page](https://maramag-waterdistrict-web.vercel.app/download) is live in Ready Vercel deployment `dpl_9RawzoZ7Uqn3vvi5WFMcwnYmVeEf` with Singapore functions. Production Chrome verified the landing download action, current version/link/checksum, 320-pixel layout and clean `/app` sign-in. Anonymous office PDF GET/POST remain 401 and private/no-store. The website stays under `web/`; Flutter remains at the repository root.

## Previous release: 1.0.2 build 3

The new universal APK adds Staff sign-in and the concerns/assigned-repairs/bills/payment workspace, plus mobile Admin review of Completed repairs. It keeps application ID `ph.maramag.waterdistrictconnect`, minimum Android 7/API 24 and the same private release signing certificate as 1.0.1, so it installs as an update. Follow [Staff role setup](staff-role.md) once in the shared Supabase project before inviting personnel or using Staff financial permissions.

Verified signed artifact: `WaterDistrictConnect-1.0.2.apk`, 58,080,588 bytes, SHA-256 `f6e63e492c24a1385a206d247447e93ef6e26667abc5613d3aaa5c7d56d733a5`. Android Build Tools verified APK v2 signature, version/build, non-debuggable manifest and ARM32/ARM64/x86-64. Certificate SHA-256 stays `db12f986c9cccb39734b5d2f15f1f43e5aa9d80bae008e0c9e86a5cd2aea0650`. Physical installation is not claimed; no Android device is connected.

The website download metadata now points to [android-v1.0.2](https://github.com/ishikawa321/Water_Disctrict/releases/tag/android-v1.0.2). The earlier release details below are historical; never replace an existing public APK asset.

**Current web connection:** the website now uses the same Supabase project directly and needs no desktop/API host. Follow [one-time office workflow setup](web-supabase-office.md) for web Staff access and atomic repair saves. API hosting requirements mentioned in the original release notes below are historical; the published APK binary is unchanged.

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
