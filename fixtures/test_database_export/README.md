# Exported phone database (FHIR + Apple Health)

This folder holds a **copy of the on-device SQLite** file the app uses at runtime: **`mywellwallet_phone.sqlite3`**.

It includes:

- **FHIR / Medplum (EHR)** data in `fhir_patients`, `fhir_resources`, and `fetch_summaries`
- **Apple Health** samples in `health_glucose`, `health_steps`, `health_heart_rate`, `health_blood_pressure`, `health_lab_results`, plus `health_sync_settings`
- The app **user profile** row in `users`

The canonical schema description is kept in sync here as **`SQLITE_SCHEMA.md`** (copy of `docs/SQLITE_SCHEMA.md`).

## Privacy and sharing

This file can contain **personally identifiable information (PII)** and **protected health information (PHI)**. Only commit or share it with **explicit consent** and a **private** repository (or encrypt / redact for public use). Your colleague should treat it like production clinical data.

## Latest export snapshot (example)

| Field | Value |
|--------|--------|
| Exported | 2026-04-08 |
| `PRAGMA user_version` | 4 |
| Approx. size | ~6 MB |
| `users` | 1 |
| `fhir_patients` | 1 |
| `fhir_resources` | 175 |
| `health_glucose` | 15,491 |
| `health_steps` | 3,050 |
| Other `health_*` | 0 rows in this snapshot |

Re-run the counts after each new export:

```bash
sqlite3 mywellwallet_phone.sqlite3 "PRAGMA user_version;"
sqlite3 mywellwallet_phone.sqlite3 "SELECT 'fhir_resources', COUNT(*) FROM fhir_resources UNION ALL SELECT 'health_glucose', COUNT(*) FROM health_glucose;"
```

## How to export again from iPhone (macOS)

Requirements: iPhone **unlocked**, **trusted** Mac, **Developer Mode** on, app installed (`com.mywellwallet.mywellwallet`).

### Option A — `devicectl` (recommended)

```bash
mkdir -p fixtures/test_database_export
xcrun devicectl device copy from \
  --device <UDID_OR_DEVICE_NAME> \
  --source Documents/mywellwallet.db \
  --destination fixtures/test_database_export/mywellwallet_phone.sqlite3 \
  --domain-type appDataContainer \
  --domain-identifier com.mywellwallet.mywellwallet
```

List devices:

```bash
xcrun devicectl list devices
flutter devices
```

### Option B — Xcode

1. **Window → Devices and Simulators** → select your iPhone.  
2. Under **Installed Apps**, select **MyWellWallet**.  
3. **Download Container…** and save the `.xcappdata` bundle.  
4. Copy the database out:

```bash
cp "<path-to>/AppData/Documents/mywellwallet.db" fixtures/test_database_export/mywellwallet_phone.sqlite3
```

### After export

1. Copy the schema doc:  
   `cp docs/SQLITE_SCHEMA.md fixtures/test_database_export/SQLITE_SCHEMA.md`  
   (or run `scripts/export_ios_database.sh`, which does copy + pull in one shot when the device is connected.)

2. Commit `mywellwallet_phone.sqlite3`, `SQLITE_SCHEMA.md`, and this README together so the fixture stays self-describing.

## Using the fixture locally (desktop / tests)

Point tools at `fixtures/test_database_export/mywellwallet_phone.sqlite3`. The app on simulator/desktop normally creates its own DB under the app documents directory; to **replace** it you would copy this file to that path **with the app stopped** and name it `mywellwallet.db`.
