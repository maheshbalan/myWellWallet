-- Synthetic-only rows for testing (not from HealthKit).
-- Tied to the first row in `users` (ORDER BY created_at LIMIT 1).
-- Safe to re-run: removes prior synthetic_fixture_* rows first.
-- Apply: sqlite3 mywellwallet_phone.sqlite3 < apply_synthetic_health_seed.sql

BEGIN TRANSACTION;

DELETE FROM health_heart_rate WHERE id LIKE 'synthetic_fixture_%';
DELETE FROM health_blood_pressure WHERE id LIKE 'synthetic_fixture_%';
DELETE FROM health_lab_results WHERE id LIKE 'synthetic_fixture_%';

-- Heart rate: resting and activity-like samples over ~10 days
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_001', id, 62, 'bpm', NULL, '2026-03-29T06:30:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_002', id, 58, 'bpm', NULL, '2026-03-30T06:15:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_003', id, 71, 'bpm', NULL, '2026-03-30T12:40:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_004', id, 68, 'bpm', NULL, '2026-03-31T07:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_005', id, 112, 'bpm', NULL, '2026-03-31T18:20:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_006', id, 65, 'bpm', NULL, '2026-04-01T06:45:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_007', id, 88, 'bpm', NULL, '2026-04-02T09:10:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_008', id, 74, 'bpm', NULL, '2026-04-03T14:25:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_009', id, 132, 'bpm', NULL, '2026-04-04T07:05:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_010', id, 59, 'bpm', NULL, '2026-04-05T06:50:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_011', id, 76, 'bpm', NULL, '2026-04-06T11:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_012', id, 95, 'bpm', NULL, '2026-04-07T17:30:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_013', id, 67, 'bpm', NULL, '2026-04-08T06:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_014', id, 104, 'bpm', NULL, '2026-04-08T12:15:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_heart_rate (id, user_id, value_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_hr_015', id, 72, 'bpm', NULL, '2026-04-08T20:45:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;

-- Blood pressure: morning clinic-style and home readings
INSERT INTO health_blood_pressure (id, user_id, systolic_real, diastolic_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_bp_001', id, 118, 76, 'mmHg', NULL, '2026-03-28T08:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_blood_pressure (id, user_id, systolic_real, diastolic_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_bp_002', id, 122, 78, 'mmHg', NULL, '2026-04-01T08:10:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_blood_pressure (id, user_id, systolic_real, diastolic_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_bp_003', id, 116, 74, 'mmHg', NULL, '2026-04-03T19:30:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_blood_pressure (id, user_id, systolic_real, diastolic_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_bp_004', id, 128, 80, 'mmHg', NULL, '2026-04-05T07:45:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_blood_pressure (id, user_id, systolic_real, diastolic_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_bp_005', id, 112, 72, 'mmHg', NULL, '2026-04-06T21:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_blood_pressure (id, user_id, systolic_real, diastolic_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_bp_006', id, 120, 77, 'mmHg', NULL, '2026-04-07T08:20:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_blood_pressure (id, user_id, systolic_real, diastolic_real, unit, source_bundle_id, recorded_at, created_at)
SELECT 'synthetic_fixture_bp_007', id, 124, 79, 'mmHg', NULL, '2026-04-08T08:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;

-- Lab results: fictional panel (LOINC codes are real; values are synthetic)
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_001', id, 'Hemoglobin A1c', '4548-4', 5.4, NULL, '%', 4.0, 5.6, 'Normal <5.7%', 'Synthetic Quest Demo Lab', NULL, 'Blood', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_002', id, 'Glucose (fasting)', '1558-6', 89, NULL, 'mg/dL', 70, 99, NULL, 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_003', id, 'Total Cholesterol', '2093-3', 182, NULL, 'mg/dL', NULL, NULL, '<200 mg/dL desirable', 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_004', id, 'LDL Cholesterol', '13457-7', 96, NULL, 'mg/dL', NULL, NULL, '<100 mg/dL optimal', 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_005', id, 'HDL Cholesterol', '2085-9', 54, NULL, 'mg/dL', 40, NULL, '>40 mg/dL', 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_006', id, 'Triglycerides', '2571-8', 91, NULL, 'mg/dL', NULL, NULL, '<150 mg/dL', 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_007', id, 'Creatinine', '2160-0', 0.92, NULL, 'mg/dL', 0.7, 1.3, NULL, 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_008', id, 'eGFR', '33914-3', 88, NULL, 'mL/min/1.73m2', 60, NULL, '>60', 'Synthetic Quest Demo Lab', NULL, NULL, '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_009', id, 'TSH', '3016-3', 1.9, NULL, 'mIU/L', 0.4, 4.0, NULL, 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_010', id, 'Vitamin D, 25-OH', '1989-3', 34, NULL, 'ng/mL', 30, 100, NULL, 'Synthetic Quest Demo Lab', NULL, 'Serum', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_011', id, 'COVID-19 PCR', '94500-6', NULL, 'Not detected', NULL, NULL, NULL, 'Negative', 'Synthetic Demo Hospital', NULL, 'Nasopharyngeal', '2026-02-10T14:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;
INSERT INTO health_lab_results (id, user_id, name, loinc_code, value_numeric, value_string, unit, reference_range_low, reference_range_high, reference_range_text, source_name, source_bundle_id, specimen_type, recorded_at, created_at)
SELECT 'synthetic_fixture_lab_012', id, 'Hemoglobin', '718-7', 14.2, NULL, 'g/dL', 13.5, 17.5, 'Male adult ref', 'Synthetic Quest Demo Lab', NULL, 'Blood', '2026-03-15T10:00:00.000', '2026-04-08T22:00:00.000' FROM users ORDER BY created_at LIMIT 1;

COMMIT;
