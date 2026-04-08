# Fixture database: seed devices & use with Dify

**Location of the SQLite fixture:** `fixtures/test_database_export/mywellwallet_phone.sqlite3`  
**Schema reference:** `fixtures/test_database_export/SQLITE_SCHEMA.md` (mirror of `docs/SQLITE_SCHEMA.md`)  
**Synthetic health seed (re-runnable):** `fixtures/test_database_export/apply_synthetic_health_seed.sql`

**Purpose:** Share one known-good database (FHIR/Medplum-style data + Apple Health–style rows + synthetic HR/BP/labs) for local QA, demos, and **external RAG tools** such as [Dify](https://dify.ai/). The file may contain **PII/PHI**—treat it like production clinical data.

---

## 1. Seed your iPhone with this database

Use this when you want the **real app** on a **physical device** to open this DB instead of an empty one.

**Requirements:** Same Apple ID / team as usual; app installed at least once; device unlocked and trusted; Xcode `devicectl` available.

1. **Quit MyWellWallet** on the phone (swipe away from app switcher).
2. From the repo root (adjust `--device` to your UDID or device name from `flutter devices` / `xcrun devicectl list devices`):

```bash
xcrun devicectl device copy to \
  --device <UDID_OR_NAME> \
  --source fixtures/test_database_export/mywellwallet_phone.sqlite3 \
  --destination Documents/mywellwallet.db \
  --domain-type appDataContainer \
  --domain-identifier com.mywellwallet.mywellwallet
```

3. Launch **MyWellWallet** again. The app expects the file at **`Documents/mywellwallet.db`** (see `DatabaseService` in `lib/services/database_service.dart`).

**Caveats**

- This **replaces** the on-device database for that install.
- If schema versions ever diverge, you may need to run migrations or reinstall the app and re-copy after upgrading the app.
- For **TestFlight / release** builds, container access may differ; `devicectl` is aimed at development workflows.

**Pulling the DB back off the phone** (export) is documented in `fixtures/test_database_export/README.md` and `scripts/export_ios_database.sh`.

---

## 2. Seed the iOS Simulator

The simulator stores app data under each app’s **data container**. Flutter uses bundle id `com.mywellwallet.mywellwallet`.

1. **Install and run the app once** on the simulator you plan to use (so the container exists).
2. **Quit the app** (stop it from Xcode/Flutter or force-quit in the simulator).
3. Resolve the **Documents** directory (macOS):

```bash
# Replace SIMULATOR_UDID if needed: xcrun simctl list devices available
CONTAINER="$(xcrun simctl get_app_container booted com.mywellwallet.mywellwallet data)"
DEST="$CONTAINER/Documents/mywellwallet.db"
cp fixtures/test_database_export/mywellwallet_phone.sqlite3 "$DEST"
```

If the simulator is not the **booted** one, pass its UDID:

```bash
CONTAINER="$(xcrun simctl get_app_container <SIMULATOR_UDID> com.mywellwallet.mywellwallet data)"
cp fixtures/test_database_export/mywellwallet_phone.sqlite3 "$CONTAINER/Documents/mywellwallet.db"
```

4. Launch **MyWellWallet** on that simulator.

**Troubleshooting**

- `get_app_container` fails → run the app once on that simulator, or verify the bundle id matches `ios/Runner` / `android/app/build.gradle.kts`.
- Wrong user shown → the fixture includes its own `users` row; you will see that profile until you replace the DB again.

---

## 3. Seed an Android emulator or device (debug)

On Android, `path_provider` places the DB under the app’s **files** directory as **`mywellwallet.db`**.

**Requirements:** **Debug** build (or otherwise `run-as` allowed), `adb` in PATH, app installed once.

1. **Force-stop** the app:

```bash
adb shell am force-stop com.mywellwallet.mywellwallet
```

2. Push the fixture to a temp path, then copy into the app sandbox:

```bash
adb push fixtures/test_database_export/mywellwallet_phone.sqlite3 /data/local/tmp/mywellwallet.db
adb shell run-as com.mywellwallet.mywellwallet cp /data/local/tmp/mywellwallet.db files/mywellwallet.db
adb shell rm /data/local/tmp/mywellwallet.db
```

If your device stores the file elsewhere (unusual for this project), locate it:

```bash
adb shell run-as com.mywellwallet.mywellwallet find . -name 'mywellwallet.db'
```

3. Start the app again.

**Note:** Release builds on production devices often **cannot** use `run-as`; use an emulator or a rooted/debuggable build for seeding.

---

## 4. Use this database as a knowledge source in Dify

Dify **does not** attach a raw SQLite file as a native “database” knowledge source. Supported uploads (via **Dify ETL**) include **TXT, Markdown, PDF, HTML, CSV, XLSX, DOCX**, and more on some deployments—see [Dify docs: upload local files](https://docs.dify.ai/en/use-dify/knowledge/create-knowledge/import-text-data/readme).

**Recommended approach:** export the fixture into **CSV** (tabular health data) plus **Markdown** (FHIR JSON per resource), then upload those files into a **Knowledge** base.

### 4.1 Generate export files from the fixture

From the repository root:

```bash
python3 scripts/export_sqlite_for_dify.py \
  fixtures/test_database_export/mywellwallet_phone.sqlite3 \
  fixtures/test_database_export/dify_export
```

This writes (by default) under `fixtures/test_database_export/dify_export/`:

| Output | Contents |
|--------|-----------|
| `knowledge_fhir_resources.md` | One section per `fhir_resources` row: type, id, patient, JSON body (good for clinical RAG) |
| `health_glucose.csv`, `health_heart_rate.csv`, … | Row-level exports for vitals / labs |
| `fetch_summaries.csv` | Fetch metadata from the server sync |

The script **does not** export the `users` table by default (PII). Add `--include-users` only for internal testing and **never** upload raw PII to a public Dify workspace.

`dify_export/` is listed in `.gitignore` so generated blobs are not committed by mistake; re-run the script when the fixture changes.

### 4.2 Create a knowledge base in Dify

1. Sign in to **Dify** (cloud or self-hosted).
2. Open **Knowledge** → **Create knowledge**.
3. Choose **Import from file** (local upload).
4. Upload the generated **`.md`** and **`.csv`** files (respect plan limits: e.g. size per file and batch size—see your Dify version).
5. Configure **chunking** (for FHIR markdown, *General* or *Parent-child* with moderate chunk size often works; tune if answers mix resources).
6. Choose **embedding** and **retrieval** settings, then wait for indexing to finish.
7. In your **App** (Chat / Agent / Workflow), add this knowledge base under **Context** / **Knowledge** so retrieval runs against it.

### 4.3 Optional: API upload

For automation, use Dify’s **Knowledge API** (e.g. create dataset, then `create-by-file`). See [Create document by file](https://docs.dify.ai/api-reference/documents/create-document-by-file) in the Dify API reference. Send the same exported `.md` / `.csv` files your script produced.

### 4.4 Privacy

- Fixture + exports can contain **PHI/PII**.
- Use a **private** Dify workspace (or self-hosted) and **access-controlled** datasets.
- For demos, consider a **redacted** copy of the SQLite file or exports with names/IDs stripped before upload.

---

## 5. Related repo files

| Path | Role |
|------|------|
| `fixtures/test_database_export/README.md` | Export **from** phone, row counts, synthetic seed |
| `scripts/export_ios_database.sh` | Pull `mywellwallet.db` from iPhone + refresh schema copy |
| `scripts/export_sqlite_for_dify.py` | Build Dify-oriented `.md` / `.csv` from any compatible SQLite |
| `docs/SQLITE_SCHEMA.md` | Authoritative table/column documentation |

For the unified EHR + Apple Health model in the app, see `docs/INTEGRATED_HEALTH_EHR_DESIGN.md`.
