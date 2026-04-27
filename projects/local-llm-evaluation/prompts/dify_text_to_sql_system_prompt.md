# Text-to-SQL for Dify **Database Query** tool (gpt-4o-mini / similar)

Copy the block inside **`text_to_sql_for_dify_COPY_PASTE.txt`** into Dify—this file adds context only.

---

## What Dify expects

The built-in **Database Query** step runs **one SQL string** against your configured datasource. It does **not** chain multiple batches for you.

So the LLM must output:

- **Exactly one** `SELECT` statement (the whole answer in **one query**).
- **Explicit `JOIN`s** whenever the English question pulls together **more than one table** (e.g. patient name + Apple Health glucose → `users` **JOIN** `health_glucose` **ON** `users.id = health_glucose.user_id`; FHIR observations for a named patient → `fhir_patients` **JOIN** `fhir_resources` **ON** `fhir_patients.patient_id = fhir_resources.patient_id`).

Avoid “run this, then run that”; fold logic into joins, **subqueries**, or a single **`WITH … AS`** only if your Dify/database layer allows **one** composed statement—otherwise stick to **JOIN** + scalar subqueries.

## Join keys (SQLite schema)

| From | To | Join condition |
|------|-----|----------------|
| `fhir_resources` | `fhir_patients` | `fhir_resources.patient_id = fhir_patients.patient_id` |
| `fetch_summaries` | `fhir_patients` | `fetch_summaries.patient_id = fhir_patients.patient_id` |
| `health_*` | `users` | `health_*.user_id = users.id` |

There is **no** automatic link between **`users.id`** and **`patient_id`** in the DDL. Join them only when the prompt supplies both identifiers, or answer EHR-only / user-only halves with the **single SELECT** best effort.

## Output format

- Single **```sql** code block **only**.
- Prefer **omit** trailing **semicolon** if your datasource rejects it.
- Read-only: **SELECT** / **WITH … SELECT** only.

Full table list and column details: **`docs/SQLITE_SCHEMA.md`** in the repo root.

## Security

Validate and run under a **read-only** DB user; never execute arbitrary SQL on PHI without checks.
