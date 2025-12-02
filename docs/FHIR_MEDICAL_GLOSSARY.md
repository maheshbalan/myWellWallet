# FHIR Medical Glossary for RAG System

This document provides a mapping between common human-readable medical terms and FHIR resource types. This glossary is used by the Local RAG system to help Gemma understand natural language queries and map them to appropriate FHIR resources.

## Purpose

When users ask questions in natural language (e.g., "Show me my recent visits"), the RAG system needs to translate these terms to FHIR resource types (e.g., "Encounters") to query the database or MCP Gateway.

## Common Term to FHIR Resource Mappings

### Visits / Appointments / Encounters
- **Human Terms**: visits, appointments, doctor visits, hospital visits, clinic visits, medical visits, encounters, recent visits
- **FHIR Resource**: `Encounter`
- **Description**: A record of a patient's interaction with the healthcare system, including office visits, hospitalizations, emergency room visits, etc.
- **Query Pattern**: `/Encounter?subject=Patient/{id}&_sort=-date&_count=10`

### Test Results / Lab Results / Diagnostic Tests
- **Human Terms**: test results, lab results, diagnostic tests, lab tests, test reports, diagnostic reports, lab reports, pathology reports, imaging reports, Test Results
- **FHIR Resource**: `DiagnosticReport`
- **Description**: Reports of diagnostic tests, lab results, imaging studies, and other diagnostic procedures.
- **Query Pattern**: `/DiagnosticReport?subject=Patient/{id}&_sort=-date`

### Immunizations / Vaccinations / Shots
- **Human Terms**: immunizations, vaccinations, vaccines, shots, immunizations record, vaccination record, vaccine history, immunization record
- **FHIR Resource**: `Immunization`
- **Description**: Records of vaccines administered to the patient.
- **Query Pattern**: `/Immunization?patient=Patient/{id}`

### Medications / Prescriptions / Drugs
- **Human Terms**: medications, medicines, prescriptions, drugs, pills, meds, current medications, medication list
- **FHIR Resource**: `MedicationStatement`
- **Description**: Records of medications that a patient is taking or has taken.
- **Query Pattern**: `/MedicationStatement?subject=Patient/{id}&status=active`

### Conditions / Diagnoses / Medical Conditions
- **Human Terms**: conditions, diagnoses, medical conditions, health conditions, diseases, illnesses, diagnosis, health problems
- **FHIR Resource**: `Condition`
- **Description**: Records of diagnoses, health conditions, or problems that the patient has or has had.
- **Query Pattern**: `/Condition?subject=Patient/{id}`

### Allergies / Allergic Reactions
- **Human Terms**: allergies, allergic reactions, drug allergies, food allergies, allergy list, allergic to
- **FHIR Resource**: `AllergyIntolerance`
- **Description**: Records of allergies and intolerances to substances.
- **Query Pattern**: `/AllergyIntolerance?patient=Patient/{id}`

### Observations / Vital Signs / Measurements
- **Human Terms**: vital signs, blood pressure, heart rate, temperature, weight, height, measurements, observations, lab values, test values
- **FHIR Resource**: `Observation`
- **Description**: Measurements, vital signs, lab values, and other clinical observations.
- **Query Pattern**: `/Observation?subject=Patient/{id}&_sort=-date`

### Documents / Medical Records / Notes
- **Human Terms**: documents, medical records, notes, clinical notes, doctor notes, medical documents, reports
- **FHIR Resource**: `DocumentReference`
- **Description**: References to clinical documents, notes, and other medical records.
- **Query Pattern**: `/DocumentReference?subject=Patient/{id}`

### Family History / Family Medical History
- **Human Terms**: family history, family medical history, family health history, genetic history
- **FHIR Resource**: `FamilyMemberHistory`
- **Description**: Information about medical conditions and health history of family members.
- **Query Pattern**: `/FamilyMemberHistory?patient=Patient/{id}`

### Procedures / Surgeries / Operations
- **Human Terms**: procedures, surgeries, operations, surgical procedures, medical procedures
- **FHIR Resource**: `Procedure`
- **Description**: Records of procedures, surgeries, and other medical interventions performed on the patient.
- **Query Pattern**: `/Procedure?subject=Patient/{id}`

### Timeline / History / Medical History
- **Human Terms**: timeline, medical history, health history, history, chronological history, timeline of events
- **FHIR Resources**: Multiple (Encounter, Observation, Condition, Procedure, etc.)
- **Description**: A chronological view of all medical events, typically combining multiple resource types sorted by date.
- **Query Pattern**: Multiple queries to get Encounters, Observations, Conditions, Procedures, sorted by date

## Temporal Qualifiers

### Recent / Latest / Most Recent
- **Human Terms**: recent, latest, most recent, newest, last, current
- **FHIR Query Pattern**: `_sort=-date&_count=10` (sort by date descending, limit to 10 most recent)
- **Description**: Temporal qualifiers that should be applied to queries to get the most recent records.

### All / Everything / Complete
- **Human Terms**: all, everything, complete, full, entire
- **FHIR Query Pattern**: Fetch all resources without date filters
- **Description**: Scope qualifiers indicating the user wants comprehensive data.

## Status Qualifiers

- **Active**: Currently active (medications, conditions) - `status=active`
- **Completed**: Finished (procedures, encounters) - `status=completed`
- **Final**: Finalized results (diagnostic reports) - `status=final`

## Query Pattern Examples

### "Show me my recent visits"
- **Intent**: Get recent encounters
- **FHIR Resource**: `Encounter`
- **FHIR Query**: `/Encounter?subject=Patient/{id}&_sort=-date&_count=10`
- **MCP Tool**: `request_encounter_resource`

### "Show me my immunization record"
- **Intent**: Get all immunizations
- **FHIR Resource**: `Immunization`
- **FHIR Query**: `/Immunization?patient=Patient/{id}`
- **MCP Tool**: `request_immunization_resource`

### "Show me my Test Results"
- **Intent**: Get diagnostic reports
- **FHIR Resource**: `DiagnosticReport`
- **FHIR Query**: `/DiagnosticReport?subject=Patient/{id}&_sort=-date`
- **MCP Tool**: `request_document_reference_resource`

### "Show me my medications"
- **Intent**: Get current medications
- **FHIR Resource**: `MedicationStatement`
- **FHIR Query**: `/MedicationStatement?subject=Patient/{id}&status=active`
- **MCP Tool**: `request_medication_resource`

### "Show me my allergies"
- **Intent**: Get allergies
- **FHIR Resource**: `AllergyIntolerance`
- **FHIR Query**: `/AllergyIntolerance?patient=Patient/{id}`
- **MCP Tool**: `request_allergy_intolerance_resource`

### "Show me my conditions"
- **Intent**: Get health conditions
- **FHIR Resource**: `Condition`
- **FHIR Query**: `/Condition?subject=Patient/{id}`
- **MCP Tool**: `request_condition_resource`

### "Show me my recent timeline"
- **Intent**: Get chronological view of all events
- **FHIR Resources**: Multiple (Encounter, Observation, Condition, Procedure)
- **FHIR Query**: Multiple queries, then combine and sort by date
- **MCP Tools**: Multiple tools

## FHIR Resource Type Reference

### Core Resources Used in MyWellWallet

1. **Patient** - The patient's basic demographic information (always 1 per fetch)
2. **Encounter** - Healthcare visits and interactions
3. **Observation** - Vital signs, lab values, measurements
4. **MedicationStatement** - Medications the patient is taking
5. **Condition** - Diagnoses and health conditions
6. **AllergyIntolerance** - Allergies and intolerances
7. **Immunization** - Vaccination records
8. **DiagnosticReport** - Test results and diagnostic reports
9. **DocumentReference** - Clinical documents and notes
10. **FamilyMemberHistory** - Family medical history
11. **Procedure** - Medical procedures and surgeries

## Search Parameter Patterns

### Common Search Parameters
- `subject=Patient/{id}` - For resources about a specific patient (most resources)
- `patient=Patient/{id}` - Alternative patient reference (used by Immunization, AllergyIntolerance, FamilyMemberHistory)
- `_sort=-date` - Sort by date descending (most recent first)
- `_sort=date` - Sort by date ascending (oldest first)
- `_count={n}` - Limit number of results
- `status=active` - Filter by active status (for medications, conditions)
- `date=ge{date}` - Filter by date greater than or equal
- `date=le{date}` - Filter by date less than or equal

## Notes for RAG Implementation

1. **Synonym Handling**: The RAG system should recognize synonyms (e.g., "visits" = "encounters")
2. **Plural/Singular**: Handle both forms (e.g., "visit" and "visits")
3. **Case Insensitivity**: Queries should be case-insensitive
4. **Context Awareness**: Use conversation context to refine queries
5. **Temporal Understanding**: Recognize time-based qualifiers (recent, latest, etc.)
6. **Combined Queries**: Some queries may need multiple resource types (e.g., "timeline")
7. **Patient Context**: Always include patient ID in queries when available

## Additional Resources

- HL7 FHIR Specification: https://www.hl7.org/fhir/
- FHIR Resource Definitions: https://www.hl7.org/fhir/resourcelist.html
- US Core Implementation Guide: https://www.hl7.org/fhir/us/core/
- FHIR Search Parameters: https://www.hl7.org/fhir/search.html

