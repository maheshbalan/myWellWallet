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

// Get blood test / lab results (decreasing chronological order)
final labResults = await db.getHealthLabResults(userId);
```

## Apple Health Tables (Diabetes & Heart-Centric)

Used when Apple Health is connected (iOS). All tables are keyed by `user_id` (app user, not FHIR patient).

### 4. `health_glucose`

CGM / blood glucose readings (mg/dL).

```sql
CREATE TABLE health_glucose (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  value_real REAL NOT NULL,
  unit TEXT NOT NULL DEFAULT 'mg/dL',
  source_bundle_id TEXT,
  recorded_at TEXT NOT NULL,
  created_at TEXT NOT NULL
)
```

- `recorded_at`: When the reading was taken (ISO 8601).
- Index: `idx_health_glucose_user_recorded ON health_glucose(user_id, recorded_at DESC)`.

### 5. `health_heart_rate`

Heart rate in beats per minute.

```sql
CREATE TABLE health_heart_rate (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  value_real REAL NOT NULL,
  unit TEXT NOT NULL DEFAULT 'bpm',
  source_bundle_id TEXT,
  recorded_at TEXT NOT NULL,
  created_at TEXT NOT NULL
)
```

### 6. `health_steps`

Step count (and optional distance) for a time interval.

```sql
CREATE TABLE health_steps (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  count INTEGER NOT NULL,
  distance_meters REAL,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  source_bundle_id TEXT,
  created_at TEXT NOT NULL
)
```

### 7. `health_blood_pressure`

Systolic and diastolic (mmHg).

```sql
CREATE TABLE health_blood_pressure (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  systolic_real REAL NOT NULL,
  diastolic_real REAL NOT NULL,
  unit TEXT NOT NULL DEFAULT 'mmHg',
  source_bundle_id TEXT,
  recorded_at TEXT NOT NULL,
  created_at TEXT NOT NULL
)
```

### 8. `health_sync_settings`

Per-user Apple Health connection and sync interval.

```sql
CREATE TABLE health_sync_settings (
  user_id TEXT PRIMARY KEY,
  sync_interval_hours INTEGER NOT NULL DEFAULT 24,
  last_synced_at TEXT,
  connected_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

- `sync_interval_hours`: 6, 24, 168 (weekly), etc.
- `last_synced_at`: Last successful sync (ISO 8601).
- `connected_at`: When the user connected Apple Health.

### 9. `health_lab_results`

Blood test / lab results (e.g. from Apple Health Clinical Records, Quest, Sonora Quest, or imported from FHIR Observation).

```sql
CREATE TABLE health_lab_results (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  loinc_code TEXT,
  value_numeric REAL,
  value_string TEXT,
  unit TEXT,
  reference_range_low REAL,
  reference_range_high REAL,
  reference_range_text TEXT,
  source_name TEXT,
  source_bundle_id TEXT,
  specimen_type TEXT,
  recorded_at TEXT NOT NULL,
  created_at TEXT NOT NULL
)
```

**Columns:**
- `id`: Unique row identifier (e.g. source + timestamp).
- `user_id`: App user (same as other health_* tables).
- `name`: Test name (e.g. "Total Cholesterol", "Glucose").
- `loinc_code`: Optional LOINC code.
- `value_numeric` / `value_string`: Result value (use one).
- `unit`: Unit of measure (e.g. mg/dL, mmol/L).
- `reference_range_*`: Normal range (numeric low/high or text).
- `source_name`: Lab or app name (e.g. "Quest", "Sonora Quest").
- `source_bundle_id`: HealthKit source identifier when from Apple Health.
- `specimen_type`: Optional (e.g. blood, serum).
- `recorded_at`: When the sample was taken (ISO 8601).
- `created_at`: When the row was inserted.

**Index:**
- `idx_health_lab_results_user_recorded` on `(user_id, recorded_at DESC)` for chronological queries.

**Query example – blood test results in decreasing chronological order:**
```sql
SELECT * FROM health_lab_results
WHERE user_id = ?
ORDER BY recorded_at DESC
LIMIT 200;
```

## Notes

1. **JSON Storage**: All FHIR resources are stored as JSON strings. Use `jsonDecode()` to parse.

2. **Timestamps**: All timestamps are ISO 8601 strings for consistency.

3. **Unique Constraint**: The `UNIQUE(patient_id, resource_type, resource_id)` constraint prevents duplicate resources.

4. **Indexes**: Indexes on `patient_id` and `resource_type` optimize common queries.

5. **JSON Functions**: SQLite 3.38+ supports JSON functions. For older versions, parse JSON in Dart code.

6. **Pagination**: Use `LIMIT` and `OFFSET` for pagination when dealing with large result sets.

7. **Lab results**: The `health_lab_results` table stores blood test results (e.g. from Apple Health Clinical Records or Quest/Sonora Quest). The Health UI shows them in **decreasing chronological order** (newest first). Populate via `DatabaseService.insertHealthLabResults` when the HealthKit lab result type is available or when importing from FHIR Observation (category laboratory).

