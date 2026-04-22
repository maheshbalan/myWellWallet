# Integrated Apple Health + EHR FHIR — Design

## 1. Problem

Today the app stores **two parallel silos**:

| Silo | Storage | Key | Used by MedGemma / RAG today? |
|------|---------|-----|--------------------------------|
| **MCH (or any) FHIR server** | `fhir_resources`, `fhir_patients` | `patient_id` (FHIR logical id) | Yes — `LocalQueryService.queryLocal` reads only this |
| **Apple Health (HealthKit)** | `health_glucose`, `health_heart_rate`, `health_steps`, `health_blood_pressure`, `health_lab_results`, … | `user_id` (app `users.id`) | No — never merged into query plans |

Natural-language queries (“glucose trend”, “steps this week”, “compare my watch heart rate to clinic vitals”) therefore **only see EHR FHIR**, not Apple data.

## 2. Design goals

1. **Single query model for the LLM** — MedGemma and rule-based RAG keep emitting **FHIR-shaped** plans (`resourceType`, `filters`) where possible.
2. **Explicit provenance** — Every fact is tagged **EHR**, **Apple Health**, or **merged** so answers can say “from your chart” vs “from Apple Health”.
3. **Stable patient linkage** — Map app user ↔ FHIR `patient_id` ↔ HealthKit rows (see §5).
4. **Incremental delivery** — Phase 1 can be **read-path merge** (no DB migration); Phase 2 optional **materialization** into `fhir_resources`.

## 3. Conceptual architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│  MCH FHIR (MCP)     │     │  Apple HealthKit    │
└──────────┬──────────┘     └──────────┬──────────┘
           │ sync / fetch               │ permission + sync
           ▼                            ▼
┌─────────────────────┐     ┌─────────────────────┐
│ fhir_resources      │     │ health_* tables     │
│ (native FHIR JSON)  │     │ (typed columns)     │
└──────────┬──────────┘     └──────────┬──────────┘
           │                            │
           └────────────┬───────────────┘
                        ▼
           ┌────────────────────────────┐
           │  Unified clinical layer    │
           │  (FHIR-like maps in Dart)   │
           │  + meta.source / meta.tag   │
           └────────────┬───────────────┘
                        │
                        ▼
           ┌────────────────────────────┐
           │ LocalQueryService (merge)   │
           │ GemmaRAGService / MedGemma   │
           └────────────────────────────┘
```

**Unified clinical layer** — Not a new SQL table in phase 1; it is the **in-memory representation** returned by the query executor: a `List<Map<String,dynamic>>` where each element is a **FHIR R4-shaped** resource (usually `Observation`) with:

- `resourceType`, `id`, `status`, `code`, `effectiveDateTime`, `valueQuantity` / `component`, etc.
- **`meta.extension` or `meta.tag`** (or a custom `_mywellwallet` block — avoid if possible; prefer standard `meta.source` + `meta.tag`) carrying:
  - `sourceSystem`: `urn:mywellwallet:source#ehr-fhir` | `urn:mywellwallet:source#apple-health`
  - optional `linkKey` for deduplication (e.g. same LOINC from lab + Apple)

## 4. Mapping: Apple Health → FHIR Observation (canonical)

Use **Observation** for quantities and many labs; use **DocumentReference** only if you later sync PDFs.

| Apple / app table | Suggested FHIR | `code` hint | `effective*` |
|-------------------|----------------|-------------|--------------|
| `health_glucose` | Observation | LOINC `2339-0` / `4548-4` (or SNOMED where needed) | `recorded_at` |
| `health_heart_rate` | Observation | LOINC `8867-4` | `recorded_at` |
| `health_blood_pressure` | Observation with **two components** | panel `85354-9` or components `8480-6` / `8462-4` | `recorded_at` |
| `health_steps` | Observation | LOINC `55423-8` (steps in 24h) or `41950-7` — document chosen standard in app config | interval from `start_at`/`end_at` |
| `health_lab_results` | Observation | `loinc_code` column when present; else `code.text` = `name` | `recorded_at` |

Each synthetic Observation should include:

```json
"subject": { "reference": "Patient/{fhirPatientId}" },
"meta": {
  "source": "https://apple.com/health",
  "tag": [{ "system": "urn:mywellwallet:provenance", "code": "apple-health" }]
}
```

EHR rows already in `fhir_resources` should be passed through unchanged, optionally normalizing `meta.tag` to `ehr-fhir` for consistency.

## 5. Patient and user linkage

- **`users.id`** — local profile id; used by all `health_*` tables.
- **`patient_id` in `fhir_resources`** — FHIR Patient logical id from the server (e.g. MCH).

**Bridge** (recommended explicit table in a future migration):

```sql
-- Future: patient_link (user_id TEXT, fhir_patient_id TEXT PRIMARY KEY, updated_at TEXT)
```

Until then, the app already establishes **current patient context** in `PatientProvider` / login flow; the unified query API must receive **both** `fhirPatientId` and `appUserId` (or resolve `userId` from the single `users` row when one profile exists).

**Rule:** `LocalQueryService` (or a dedicated `UnifiedClinicalQueryService`) must **never** mix two users’ Health data; always scope Apple rows by `user_id` and FHIR rows by `patient_id`.

## 6. Query execution (MedGemma / RAG)

1. **RAG + rule-based** continue to output `queryPlan.resourceType` (e.g. `Observation`, `Encounter`).
2. **Executor** (`executeQueryPlan`):
   - Load FHIR resources from `fhir_resources` as today.
   - If `resourceType == Observation` (or a new flag `includeAppleHealth: true` on the plan), **also** load matching Apple-derived Observations (converted in Dart from `health_*`).
   - **Merge** lists, **sort** by `effectiveDateTime`, apply **dedupe** optional window (same code + same day + both sources → mark or merge).
3. **Responses** — Formatter / MedGemma summarization sees one list of FHIR-like JSON; provenance tags drive wording (“Apple Health shows …”, “Your clinic record shows …”).

### Optional `queryPlan` extensions (backward compatible)

```json
{
  "resourceType": "Observation",
  "filters": { "_sort": "-date", "_count": 20 },
  "dataSources": ["ehr-fhir", "apple-health"],
  "codeSearch": "glucose"
}
```

If `dataSources` omitted, default `["ehr-fhir"]` until integration is fully rolled out; then default `["ehr-fhir", "apple-health"]` for Observation/vitals queries.

## 7. Phase 2 (optional): Materialize into `fhir_resources`

Background job inserts synthetic JSON into `fhir_resources` with `resource_id` prefixed `ah-` (Apple Health) and `resource_type` `Observation`. **Pros:** one SQL path, simpler counts. **Cons:** duplication, sync invalidation when HealthKit data changes. Prefer phase 1 merge unless performance requires it.

## 8. Security and privacy

- Apple Health data stays in app sandbox; tags must not leak to external servers unless user consents.
- Summaries sent to any cloud model should strip or minimize identifiers per policy.

## 9. Documentation for RAG

- **`SQLITE_SCHEMA.md`** — physical tables + link to this doc.
- **`FHIR_MEDICAL_GLOSSARY.md`** — human terms spanning both sources.
- This file — **architecture and query contract** for MedGemma query planning.

---

*Version: 1.0 — design only; implementation follows in app code.*
