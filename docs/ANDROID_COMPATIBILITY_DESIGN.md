# MyWellWallet on Android

Design only. Do not start this work until three things are finished:

1. 1up Patient Access in the dev sandbox, ready to promote after testing.
2. A test build of the iPhone app on the Apple App Store.
3. MedGemma querying SQLite from the schema in its system prompt, with the hardcoded query paths removed.

Android is the step after those three. The goal is one Flutter codebase. iPhone and Android share screens, SQLite, chat, and the 1up client. Each phone uses its own health store and its own secure storage.

## 1. What is already shared

The project is a Flutter app. `android/` is already in the tree. The application id matches the iPhone bundle id: `com.mywellwallet.mywellwallet`.

These parts do not need a second app:

| Area | Today |
|------|--------|
| UI, navigation, Profile, chat | Dart, Material |
| SQLite clinical store | `sqflite` |
| MCP client and local query | Dart |
| MedGemma | `llamadart` already has separate iOS and Android memory caps |
| Speech to text | `speech_to_text` supports both |
| Biometric sign-in | `local_auth` supports both |
| 1up HTTP calls | Plain HTTPS. The same client id and redirect string can be used on both phones |

Release builds on Android do not have the iPhone JIT crash (“Unable to flip between RX and RW memory protection”). Debug builds on Android are usable. MedGemma should still be tested on a release or profile build because of memory.

## 2. What is iPhone-only today

Health screens and Profile refuse to run unless `Platform.isIOS`.

| Piece | Why it is iPhone-only |
|-------|------------------------|
| `AppleHealthService` | HealthKit through the `health` plugin. `isAvailable` is iOS only. |
| `ClinicalLabResultsChannel` | A custom channel to HealthKit Clinical Records (`labResultRecord`). Institution labs such as Quest are not a normal `health` type. |
| Health dashboard and the glucose, heart rate, steps, blood pressure, and lab screens | They return an unsupported page on any other platform. |
| Profile “Apple Health” card | Built only when `Platform.isIOS`. |
| 1up callback | Designed as `mywellwallet://1up/callback` plus an iOS URL scheme. Android has no intent filter for that scheme yet. |
| Token storage in the 1up design | Written as the iOS Keychain. Android needs the Keystore. |
| Play signing | `android/app/build.gradle.kts` still signs release with the debug key. |

Apple Health rows already live in shared tables (`health_glucose`, `health_heart_rate`, `health_steps`, `health_blood_pressure`, `health_lab_results`) keyed by `users.id`. Android should write those same tables. Chat and the Health screens then stay one code path.

## 3. Architecture

```
                    lib/  (one codebase)
                          │
          ┌───────────────┼────────────────┐
          ▼               ▼                ▼
   Device health     Secure tokens      1up + MCP + SQLite
          │               │                │
    ┌─────┴─────┐   ┌─────┴──────┐         │
    ▼           ▼   ▼            ▼         ▼
 HealthKit   Health  iOS       Android   same Dart
 (iPhone)    Connect Keychain  Keystore  fhir_* and health_*
             (Android)
```

A small interface sits in front of the phone health store. Call it `DeviceHealthSource`.

- On iPhone the implementation is the current `AppleHealthService`, including the clinical-lab channel.
- On Android the implementation reads Health Connect through the same `health` plugin for glucose, heart rate, steps, and blood pressure, and writes the existing `health_*` tables.
- Screens ask `DeviceHealthSource`, not `Platform.isIOS`.
- The provenance tag stays `apple-health` on iPhone. Android rows use `health-connect`. Queries treat both as the on-device vital source. They are never both present on one phone.

Clinical labs from a hospital or a lab company stay an iPhone HealthKit feature. Android does not get a fake Clinical Records channel. Those labs on Android come from 1up FHIR (`Observation`, `DiagnosticReport`) after the 1up work lands. The lab screens show 1up labs on Android and keep showing HealthKit clinical labs on iPhone.

## 4. Health Connect

Health Connect is the Android system store. The `health` plugin already maps the four vitals we sync today.

Profile on Android shows **Health Connect** instead of **Apple Health**, with the same actions: connect, sync interval, sync now, and view health. The copy says Health Connect. The buttons and the dashboard layout stay the same.

Android setup when this is implemented:

- Raise `minSdk` to the level the `health` plugin requires for Health Connect (confirm at build time; plan on 26).
- Add the Health Connect permissions for blood glucose, heart rate, steps, and blood pressure in `AndroidManifest.xml`.
- Show the Health Connect permission screen from the connect button.
- If Health Connect is missing, the card explains that it must be installed or updated. Do not crash.

Background sync stays the same rule as iPhone: the interval is checked when the app opens or when the member taps sync. Neither platform promises an overnight pull.

## 5. 1up on Android

The 1up design does not change. Add a provider, one token per connection, FHIR into `fhir_resources`, MCP as the other clinical source.

The callback URL stays `mywellwallet://1up/callback`. Register that same redirect on the 1up client. Android adds an intent filter on the main activity for scheme `mywellwallet` and host/path `1up` / `callback`. The member still signs in inside the system browser (Chrome Custom Tabs), not in a WebView the app can read.

Token storage uses one Dart API, `flutter_secure_storage`: Keychain on iPhone, Keystore on Android. The 1up client must not call the Keychain APIs directly.

This wiring is part of the Android step, after the iPhone sandbox flow exists. The iPhone 1up work should keep the redirect string and the token calls in Dart so Android can reuse them.

## 6. Sign-in, speech, and MedGemma

Biometric login already goes through `local_auth`. Android uses fingerprint or face unlock from the same button. PIN stays the fallback.

Speech already initializes on both phones. The microphone permission is already in the Android manifest.

MedGemma already loads with Android caps (larger context than iPhone, still bounded). The model file stays a download, not an asset inside the store package. Android devices with too little RAM show the same “not ready” state the iPhone shows. The later prompt work (schema in the system prompt, no hardcoded SQL) is shared Dart. It does not need an Android-specific query path.

## 7. Store order

The Apple App Store test build comes first, as its own task, before this Android work.

The Play listing comes after Android health, the 1up callback, and a release keystore exist. Today release builds are signed with the debug key. That is fine for a local install and wrong for Play. The Play task creates an upload key, turns on Play App Signing, and ships an internal testing track. It does not start in the Android implementation until the iPhone test listing is out.

Package name for Play: `com.mywellwallet.mywellwallet`. Do not change it after the first upload.

## 8. What the Android implementation changes

When this design is built, the code changes are:

1. `DeviceHealthSource` with HealthKit and Health Connect implementations, both writing `health_*`.
2. Health screens and Profile use that source. Remove the blanket `Platform.isIOS` blocks.
3. Android label is Health Connect. iPhone label stays Apple Health.
4. Clinical-lab channel remains iPhone-only. Android lab screens read 1up FHIR labs.
5. Intent filter for `mywellwallet://1up/callback`.
6. Tokens through `flutter_secure_storage`.
7. Health Connect permissions and a confirmed `minSdk`.
8. A release keystore, kept out of git, only when the Play track is opened.

No second UI kit. No second database. No MedGemma fork.

## 9. How to know it works

On an Android phone, after the earlier three tasks are done:

- The app installs from this repo with `flutter run`.
- PIN and biometric sign-in work.
- Health Connect connect and sync fill glucose, heart rate, steps, and blood pressure. The Health tab shows them.
- Chat can answer from those rows and from SQLite.
- Add a provider opens the system browser and returns to the app on `mywellwallet://1up/callback`.
- A 1up connection downloaded on Android is visible in chat, with Apple Health rows absent and Health Connect rows present.
- MCP mode still shows Fetch Data. 1up mode hides it. The toggle default remains MCP until the production lock.
