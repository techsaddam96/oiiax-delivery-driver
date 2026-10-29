# Maps release configuration

## Android

`android/app/src/main/AndroidManifest.xml` consumes `${MAPS_API_KEY}`. The
Gradle configuration resolves `MAPS_API_KEY` in this order:

1. `-PMAPS_API_KEY=...`
2. `MAPS_API_KEY` in the build environment
3. `android/local.properties` for a developer machine

`android/local.properties` is ignored by `android/.gitignore`. A release task
fails if no non-empty key is supplied; it never receives a fallback key.

The Android production key must be restricted in Google Cloud Console to the
Android package `com.hero.blockatie` and the SHA certificate fingerprint for
the artifact being released. Obtain the fingerprint from the release/upload
signing material with `signingReport` and, where Google Play App Signing is
used, confirm the relevant App Signing certificate fingerprint in Play
Console. Do not guess or reuse a debug SHA.

## iOS

`ios/Runner/AppDelegate.swift` reads `GOOGLE_MAPS_API_KEY` from the bundled
Info.plist value. The value is supplied by the ignored
`ios/Flutter/Maps.xcconfig`, which is optionally included by both Debug and
Release xcconfigs. Copy `ios/Flutter/Maps.xcconfig.example` to that local file
and set a real iOS Maps key there.

The app fails at startup instead of running with an empty or unresolved iOS
Maps key. If iOS is released, use a separate iOS-restricted Google Maps key;
do not reuse the Android key. Confirm the final Runner bundle identifier before
applying the iOS application restriction.

## Backend dashboard Maps

The dashboard resolves `GOOGLE_MAPS_API_KEY` from the PHP/web-server
environment first, then falls back to ignored `config/maps.php` with an
`api_key` entry. That browser-visible key should be restricted by approved
production HTTP referrers. This document does not change that existing chain.
