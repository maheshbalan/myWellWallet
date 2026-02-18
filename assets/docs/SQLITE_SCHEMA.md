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
```

## Notes

1. **JSON Storage**: All FHIR resources are stored as JSON strings. Use `jsonDecode()` to parse.

2. **Timestamps**: All timestamps are ISO 8601 strings for consistency.

3. **Unique Constraint**: The `UNIQUE(patient_id, resource_type, resource_id)` constraint prevents duplicate resources.

4. **Indexes**: Indexes on `patient_id` and `resource_type` optimize common queries.

5. **JSON Functions**: SQLite 3.38+ supports JSON functions. For older versions, parse JSON in Dart code.

6. **Pagination**: Use `LIMIT` and `OFFSET` for pagination when dealing with large result sets.

