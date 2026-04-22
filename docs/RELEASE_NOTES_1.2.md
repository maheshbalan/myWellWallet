# Release 1.2 – Release notes (since 1.1)

Use this content when creating the **v1.2.0** release in GitHub (Releases → Draft a new release → choose tag `v1.2.0` → paste below).

---

## Summary

Release 1.2 adds a dedicated **blood test / lab results** flow (schema, screen, dashboard), prepares **on-device Gemma 2B** integration (download-on-first-use), and updates the SQLite schema documentation.

---

## Lab results & blood tests

- **Schema:** New table `health_lab_results` (DB version 4) for blood test results from Apple Health (e.g. Quest, Sonora Quest) or FHIR Observation.
  - Columns: name, LOINC, value (numeric/string), unit, reference range, source, specimen, `recorded_at`.
  - Index on `(user_id, recorded_at DESC)` for chronological queries.
- **Screen:** **Blood test results** at `/health/lab-results`.
  - Lists all lab results in **decreasing chronological order** (newest first).
  - Shows name, value, unit, reference range, source, and date.
  - Pull-to-refresh and empty state.
- **Dashboard:** New **Blood test results** card (Quest, Sonora Quest, labs) linking to the lab results screen.
- **Apple Health:** Documented that lab results are stored in `health_lab_results`; actual sync from HealthKit Clinical Records (e.g. lab result type) to be added when the plugin or a platform channel supports it.

---

## Gemma 2B integration (prep)

- **GemmaModelService** (`lib/services/gemma_model_service.dart`):
  - Download-on-first-use for a **Gemma 2 2B** GGUF model (e.g. `gemma-2-2b-it` Q2_K).
  - Uses **llamadart** for on-device inference; model cached under app support directory.
  - Configurable via `_modelUrl`; when set, RAG result formatting can use the model.
- **GemmaRAGService:** Result formatting now tries **GemmaModelService.generate(prompt)** when configured; falls back to existing rule-based formatting otherwise.
- **Dependency:** `llamadart: ^0.6.4` added to `pubspec.yaml`.

---

## Documentation

- **SQLITE_SCHEMA.md** (assets/docs):
  - New section **9. health_lab_results** with full CREATE TABLE, column descriptions, index, and query example (blood test results in decreasing chronological order).
  - Data Access in Dart example for `getHealthLabResults(userId)`.
  - Note on lab results and chronological display in the Health UI.

---

## Upgrade notes

- Database version is **4**. Existing installs get `health_lab_results` and index via migration.
- To enable on-device Gemma: set the model URL in `GemmaModelService` (e.g. to a hosted `gemma-2-2b-it` GGUF), then on first use the app will download and cache the model.

---

## Files changed (high level)

- `lib/services/database_service.dart` – DB v4, `health_lab_results`, insert/get lab results.
- `lib/screens/health_lab_results_screen.dart` – New screen.
- `lib/screens/health_dashboard_screen.dart` – Blood test results card.
- `lib/main.dart` – Route `/health/lab-results`, import.
- `lib/services/gemma_model_service.dart` – New service (download + LlamaEngine).
- `lib/services/gemma_rag_service.dart` – Use Gemma for formatting when configured.
- `lib/services/apple_health_service.dart` – Doc comment for lab results.
- `pubspec.yaml` – llamadart.
- `assets/docs/SQLITE_SCHEMA.md` – Regenerated with latest schema.
