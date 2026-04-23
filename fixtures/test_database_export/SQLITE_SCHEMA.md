# SQLite Database Schema Documentation

## Overview

The MyWellWallet app uses SQLite to store user profiles and FHIR resources locally. This document describes the database schema and provides query examples.

## Tables

### 1. `users`

Stores user profile information (authentication and basic demographics).

**Schema:**
```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  date_of_birth TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

**Columns:**
- `id`: Unique user identifier
- `name`: Full name of the user
- `email`: Email address
- `date_of_birth`: ISO 8601 date string (YYYY-MM-DD)
- `created_at`: ISO 8601 timestamp
- `updated_at`: ISO 8601 timestamp

**Query Examples:**
```sql
-- Get current user
SELECT * FROM users ORDER BY created_at DESC LIMIT 1;

-- Check if user exists
SELECT COUNT(*) FROM users;

-- Update user
UPDATE users SET name = ?, email = ?, updated_at = ? WHERE id = ?;
```

### 2. `fhir_patients`

Stores complete FHIR Patient bundles for each patient.

**Schema:**
```sql
CREATE TABLE fhir_patients (
  id TEXT PRIMARY KEY,
  patient_id TEXT NOT NULL,
  patient_name TEXT NOT NULL,
  fhir_bundle TEXT NOT NULL,
  last_synced TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

**Columns:**
- `id`: Primary key (same as patient_id)
- `patient_id`: FHIR Patient resource ID
- `patient_name`: Display name of the patient
- `fhir_bundle`: JSON string of complete FHIR Bundle
- `last_synced`: ISO 8601 timestamp of last sync with server
- `created_at`: ISO 8601 timestamp
- `updated_at`: ISO 8601 timestamp

**Indexes:**
- `idx_fhir_patients_patient_id` on `patient_id`

**Query Examples:**
```sql
-- Get patient bundle by ID
SELECT fhir_bundle FROM fhir_patients WHERE patient_id = ?;

-- Get all patients
SELECT * FROM fhir_patients;

-- Update sync time
UPDATE fhir_patients SET last_synced = ?, updated_at = ? WHERE patient_id = ?;
```

### 3. `fhir_resources`

Stores individual FHIR resources extracted from bundles. This table enables efficient querying of specific resource types.

**Schema:**
```sql
CREATE TABLE fhir_resources (
  id TEXT PRIMARY KEY,
  patient_id TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT NOT NULL,
  resource_data TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(patient_id, resource_type, resource_id)
)
```

**Columns:**
- `id`: Composite key `${patient_id}_${resource_type}_${resource_id}`
- `patient_id`: Reference to patient
- `resource_type`: FHIR resource type (e.g., "Patient", "Encounter", "Observation")
- `resource_id`: FHIR resource ID
- `resource_data`: JSON string of complete FHIR resource
- `created_at`: ISO 8601 timestamp
- `updated_at`: ISO 8601 timestamp

**Indexes:**
- `idx_fhir_resources_patient_id` on `patient_id`
- `idx_fhir_resources_type` on `resource_type`

**Query Examples:**
```sql
-- Get all resources for a patient
SELECT * FROM fhir_resources WHERE patient_id = ? ORDER BY resource_type, updated_at DESC;

-- Get specific resource type for a patient
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = ? 
ORDER BY updated_at DESC;

-- Get recent encounters
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'Encounter' 
ORDER BY updated_at DESC LIMIT 10;

-- Get all observations
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'Observation' 
ORDER BY updated_at DESC;

-- Get medications
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'MedicationStatement' 
ORDER BY updated_at DESC;

-- Get conditions
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'Condition' 
ORDER BY updated_at DESC;

-- Count resources by type
SELECT resource_type, COUNT(*) as count 
FROM fhir_resources 
WHERE patient_id = ? 
GROUP BY resource_type;

-- Search resources by content (requires JSON parsing)
-- Note: SQLite JSON functions available in newer versions
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? 
AND json_extract(resource_data, '$.status') = 'active';
```

### 4. `fetch_summaries`

Stores a summary row each time patient FHIR data is fetched from the server (e.g. Medplum) and persisted.

**Schema:**
```sql
CREATE TABLE fetch_summaries (
  id TEXT PRIMARY KEY,
  patient_id TEXT NOT NULL,
  total_resources INTEGER NOT NULL,
  resource_counts TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  errors TEXT,
  stored_in_database INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)
```

**Columns:**
- `id`: Unique id for this fetch run
- `patient_id`: FHIR Patient id
- `total_resources`: Total resources processed
- `resource_counts`: JSON map of resource type → count
- `completed_at`: ISO 8601 when fetch finished
- `errors`: Optional error text
- `stored_in_database`: Whether rows were written to `fhir_*` tables
- `created_at`: ISO 8601

**Indexes:**
- `idx_fetch_summaries_patient_id` on `patient_id`

**Query Examples:**
```sql
SELECT * FROM fetch_summaries WHERE patient_id = ? ORDER BY completed_at DESC LIMIT 5;
```

## Common Query Patterns

### Get Patient Information
```sql
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'Patient' 
LIMIT 1;
```

### Get Recent Encounters (Timeline)
```sql
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'Encounter' 
ORDER BY json_extract(resource_data, '$.period.start') DESC 
LIMIT 20;
```

### Get Active Medications
```sql
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? 
AND resource_type = 'MedicationStatement' 
AND json_extract(resource_data, '$.status') = 'active';
```

### Get Recent Lab Results
```sql
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? 
AND resource_type = 'Observation' 
AND json_extract(resource_data, '$.category[0].coding[0].code') = 'laboratory'
ORDER BY json_extract(resource_data, '$.effectiveDateTime') DESC 
LIMIT 10;
```

### Get Allergies
```sql
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'AllergyIntolerance';
```

### Get Conditions
```sql
SELECT resource_data FROM fhir_resources 
WHERE patient_id = ? AND resource_type = 'Condition' 
ORDER BY json_extract(resource_data, '$.onsetDateTime') DESC;
```

## Resource Type Mappings

Common FHIR resource types stored in `resource_type`:

- `Patient` - Patient demographics
- `Encounter` - Visits, appointments, hospital stays
- `Observation` - Lab results, vitals, measurements
- `MedicationStatement` - Current and past medications
- `Medication` - Medication definitions
- `Condition` - Diagnoses, problems
- `AllergyIntolerance` - Allergies
- `Immunization` - Vaccinations
- `DiagnosticReport` - Diagnostic reports
- `DocumentReference` - Clinical documents
- `FamilyMemberHistory` - Family health history
- `Procedure` - Procedures performed

## Data Access in Dart

### Using DatabaseService

```dart
final db = DatabaseService();

// Get patient resources
final encounters = await db.getPatientResources(patientId, 'Encounter');
final observations = await db.getPatientResources(patientId, 'Observation');

// Get all resources
final allResources = await db.getAllPatientResources(patientId);

// Get patient bundle
final bundle = await db.getPatientBundle(patientId);
```

## Apple Health tables (device / HealthKit)

These tables store **Apple Health** (and similar) metrics keyed by **`user_id`** = `users.id`. They are **not** FHIR JSON blobs; they are **not** read by legacy `getPatientResources` unless the app merges them (see **Integrated clinical data model** below).

### `health_glucose`

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PK | Stable row id (often HealthKit uuid) |
| `user_id` | TEXT | FK to `users.id` |
| `value_real` | REAL | Numeric value |
| `unit` | TEXT | e.g. `mg/dL` |
| `source_bundle_id` | TEXT | Optional provenance |
| `recorded_at` | TEXT | ISO 8601 |
| `created_at` | TEXT | ISO 8601 |

### `health_heart_rate`

| Column | Type | Description |
|--------|------|-------------|
| `id`, `user_id`, `value_real`, `unit`, `source_bundle_id`, `recorded_at`, `created_at` | | Same pattern as glucose |

### `health_steps`

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PK | |
| `user_id` | TEXT | |
| `count` | INTEGER | Step count |
| `distance_meters` | REAL | Optional |
| `start_at`, `end_at` | TEXT | Interval |
| `source_bundle_id`, `created_at` | TEXT | |

### `health_blood_pressure`

| Column | Type | Description |
|--------|------|-------------|
| `id`, `user_id` | TEXT | |
| `systolic_real`, `diastolic_real` | REAL | mmHg |
| `unit`, `source_bundle_id`, `recorded_at`, `created_at` | TEXT | |

### `health_lab_results`

| Column | Type | Description |
|--------|------|-------------|
| `id`, `user_id` | TEXT | |
| `name` | TEXT | Display name |
| `loinc_code` | TEXT | Optional LOINC |
| `value_numeric`, `value_string`, `unit` | | Value |
| `reference_range_*`, `source_name`, `specimen_type` | | Optional clinical context |
| `recorded_at`, `created_at` | TEXT | |

### `health_sync_settings`

Per-user Health sync preferences and last sync timestamps.

---

## Integrated clinical data model (EHR FHIR + Apple Health)

**Full architecture:** see **`INTEGRATED_HEALTH_EHR_DESIGN.md`** (bundled for RAG).

### Two physical stores, one logical model

| Store | Table(s) | Foreign key scope | Content shape |
|-------|----------|-------------------|---------------|
| EHR (MCH, etc.) | `fhir_resources`, `fhir_patients` | `patient_id` = FHIR Patient id | Native FHIR JSON in `resource_data` |
| Apple Health | `health_*` | `user_id` = `users.id` | Typed relational rows |

### Unified query semantics (for MedGemma / RAG)

- The **LLM query plan** should stay **FHIR-oriented** (`resourceType`, `filters`, optional `dataSources`).
- The **executor** merges:
  - rows from `fhir_resources` for the current **`patient_id`**, and
  - when enabled, **synthetic FHIR Observation** maps built from `health_*` for the current **`user_id`** linked to that patient context.
- Every merged item carries **provenance** (`meta.source` / `meta.tag`) so answers can distinguish **clinic record** vs **Apple Health**.

### SQL examples (Apple tables only)

```sql
-- Recent glucose from Apple Health for a user
SELECT * FROM health_glucose
WHERE user_id = ?
ORDER BY recorded_at DESC
LIMIT 50;

-- Steps aggregates
SELECT * FROM health_steps
WHERE user_id = ?
ORDER BY start_at DESC
LIMIT 30;
```

Cross-store questions (“compare my watch HR to clinic vitals”) require **application code** to run both-style queries (or merged Observation list), not a single SQL join, unless Phase 2 materializes Apple data into `fhir_resources`.

---

## Notes

1. **JSON Storage**: All FHIR resources are stored as JSON strings. Use `jsonDecode()` to parse.

2. **Timestamps**: All timestamps are ISO 8601 strings for consistency.

3. **Unique Constraint**: The `UNIQUE(patient_id, resource_type, resource_id)` constraint prevents duplicate resources.

4. **Indexes**: Indexes on `patient_id` and `resource_type` optimize common queries.

5. **JSON Functions**: SQLite 3.38+ supports JSON functions. For older versions, parse JSON in Dart code.

6. **Pagination**: Use `LIMIT` and `OFFSET` for pagination when dealing with large result sets.

