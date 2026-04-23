// Reusable FHIR fixture data for unit tests. WP1-07.

/// A mixed Observation set: glucose, HbA1c, step counts, heart rate,
/// cholesterol, and a few unrelated rows whose display names contain the
/// word fragment "test" but which shouldn't match a `codeSearch: 'test'`
/// query under a word-boundary matcher.
final List<Map<String, dynamic>> mixedObservationFixture = [
  {
    'resourceType': 'Observation',
    'id': 'obs-glucose-1',
    'effectiveDateTime': '2026-01-02',
    'code': {
      'text': 'Glucose',
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '2339-0',
          'display': 'Glucose [Mass/volume] in Blood',
        },
      ],
    },
    'valueQuantity': {'value': 92, 'unit': 'mg/dL'},
  },
  {
    'resourceType': 'Observation',
    'id': 'obs-hba1c-1',
    'effectiveDateTime': '2026-01-03',
    'code': {
      'text': 'HbA1c',
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '4548-4',
          'display': 'Hemoglobin A1c/Hemoglobin.total in Blood',
        },
      ],
    },
    'valueQuantity': {'value': 5.6, 'unit': '%'},
  },
  {
    'resourceType': 'Observation',
    'id': 'obs-steps-1',
    'effectiveDateTime': '2026-01-02',
    'code': {
      'text': 'Step count',
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '55423-8',
          'display': 'Number of steps',
        },
      ],
    },
    'valueQuantity': {'value': 8423, 'unit': '{steps}/d'},
  },
  {
    'resourceType': 'Observation',
    'id': 'obs-hr-1',
    'effectiveDateTime': '2026-01-02',
    'code': {
      'text': 'Heart rate',
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '8867-4',
          'display': 'Heart rate',
        },
      ],
    },
    'valueQuantity': {'value': 72, 'unit': '/min'},
  },
  {
    'resourceType': 'Observation',
    'id': 'obs-chol-total-1',
    'effectiveDateTime': '2026-01-05',
    'code': {
      'text': 'Cholesterol, total',
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '2093-3',
          'display': 'Cholesterol [Mass/volume] in Serum or Plasma',
        },
      ],
    },
    'valueQuantity': {'value': 180, 'unit': 'mg/dL'},
  },
  {
    'resourceType': 'Observation',
    'id': 'obs-chol-ldl-1',
    'effectiveDateTime': '2026-01-05',
    'code': {
      'text': 'LDL cholesterol',
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '2089-1',
          'display': 'Cholesterol in LDL [Mass/volume] in Serum or Plasma',
        },
      ],
    },
    'valueQuantity': {'value': 110, 'unit': 'mg/dL'},
  },
  {
    // Row that would false-positive a naive substring match for "test" —
    // its display name contains the fragment "testicular" but it is not
    // a test result in the "DiagnosticReport / lab test" sense.
    'resourceType': 'Observation',
    'id': 'obs-testicular-1',
    'effectiveDateTime': '2026-01-06',
    'code': {
      'text': 'Testicular exam (history)',
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '32423-7',
          'display': 'Testicular examination',
        },
      ],
    },
  },
  {
    // Row with no display/text but a LOINC code for glucose — should be
    // picked up by the LOINC fallback even though there's nothing to
    // substring-match on.
    'resourceType': 'Observation',
    'id': 'obs-glucose-loinc-only',
    'effectiveDateTime': '2026-01-07',
    'code': {
      'coding': [
        {
          'system': 'http://loinc.org',
          'code': '2339-0',
        },
      ],
    },
    'valueQuantity': {'value': 105, 'unit': 'mg/dL'},
  },
];
