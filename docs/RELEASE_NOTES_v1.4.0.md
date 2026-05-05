# MyWellWallet v1.4.0 — Release notes

**Release date:** April 8, 2026  
**Version:** 1.4.0 (build 2)  
**Git tag:** `v1.4.0` (use this tag for the GitHub Release)

> **Note:** **v1.4.0** extends **v1.3.0** with **Clinical Health Records** lab sync from Apple Health, native iOS bridging, SQLite storage for FHIR-backed lab rows, and in-app lab browsing with per-analyte history. Use **release** builds on physical iPhones when exercising HealthKit-heavy paths (see `docs/IOS_DEBUG_CRASH.md`).

## Summary

This release adds **institutional lab results** that appear in Apple Health as **Clinical Health Records** (`HKClinicalRecord` **`labResultRecord`**). A Swift plugin queries HealthKit independently of the Dart **`health`** package, parses FHIR payloads, and stores normalized rows in **`health_lab_results`**. The app surfaces **Lab results** under Health: latest values grouped by LOINC/analyte, with a detail screen showing a compact **history table** (prior draws).

A required **Info.plist** key (**`NSHealthClinicalHealthRecordsShareUsageDescription`**) fixes an iOS assertion that previously terminated the app when requesting clinical read authorization without the mandated purpose string.

---

## Highlights

### Clinical lab results from Apple Health

- **`ClinicalHealthRecordsPlugin.swift`** (iOS Runner): authorization and **`HKSampleQuery`** for **`labResultRecord`**; batched payloads over a Flutter **`MethodChannel`** (`com.mywellwallet/clinical_lab_results`).
- **Dart bridge:** `lib/services/clinical_lab_results_channel.dart`.
- **Persistence:** `DatabaseService` helpers for latest-per-test grouping and per-test history (aligned with `health_lab_results` / schema docs).
- **UI:** `health_lab_results_screen.dart` + `health_lab_detail_screen.dart`; routing from Health dashboard (`/health/lab-results`, detail route).

### Apple Health sync (Dart)

- **Single coordinated path** for clinical authorization/sync alongside existing vitals sync in `apple_health_service.dart` (avoid overlapping permission flows that could destabilize some iOS versions).
- **Spacing** between HealthKit-heavy steps after vitals persist where relevant.

### iOS configuration

- **`Runner.entitlements`:** **`health-records`** capability remains required for Clinical Health Records.
- **`Info.plist`:** **`NSHealthClinicalHealthRecordsShareUsageDescription`** added next to existing **`NSHealthShareUsageDescription`** / **`NSHealthUpdateUsageDescription`** so HealthKit’s clinical validation does not abort the process.

### Documentation and developer experience

- **README** updates: clinical labs overview, required plist key, in-place upgrade via **`flutter run --release`** and optional **`--no-resident`**.

---

## Upgrade and install notes

- **In-place upgrade** (same bundle id, no icon delete): **`flutter run --release -d <device_id>`** preserves local **SQLite**, user session, and downloaded model assets; prefer this over workflows that uninstall first.
- **Physical iPhone:** use **Release** for the native stack; **`--no-resident`** exits after install/launch without keeping the tooling attached.

---

## Known limitations / next steps

- Clinical records depend on **Apple Health Accounts** and connected providers; if no labs sync into Health, the app has nothing to import.
- Simulator support for clinical queries is limited; testing is most reliable on a **physical device** with real Health data.
- Further tuning of parsing, LOINC coverage, and UI copy may follow based on real-world lab feeds.

---

## Technical stack (reference)

- Flutter, Provider, go_router  
- sqflite, `health` (vitals), **native HealthKit** (clinical **`labResultRecord`**)  
- HealthKit **Clinical Health Records** entitlement  

---

## Thanks

Thanks to on-device testers; crash analysis and plist validation for this cycle came from real iPhone runs and system crash logs.
