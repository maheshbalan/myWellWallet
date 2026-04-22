# Gemma LLM Approach for FHIR Database Queries

## Overview

Instead of brute-force pattern matching, we leverage Gemma's natural language understanding capabilities to interpret complex queries and generate appropriate database search strategies. Gemma acts as an intelligent query planner that understands both natural language and FHIR database structure.

## Core Concept

**Gemma as Query Planner**: Rather than hardcoding patterns, we provide Gemma with:
1. **Database Schema Context** - Understanding of SQLite structure
2. **FHIR Resource Context** - Examples and structure of FHIR resources
3. **Medical Terminology Context** - Glossary and mappings
4. **Query Examples** - Few-shot examples of query translation

Gemma then generates a **structured query plan** that we execute against the local database.

## Architecture

```
User Query: "show me my cholesterol levels"
    ↓
1. Build Comprehensive Context for Gemma
   - Database Schema (SQLite structure)
   - FHIR Resource Examples (Observation structure)
   - Medical Glossary (cholesterol → LOINC codes)
   - Query Examples (similar queries and their plans)
    ↓
2. Generate Prompt with Context
   - Role: "You are a healthcare data query assistant"
   - Task: "Convert this query to a database query plan"
   - Context: All relevant information above
    ↓
3. Gemma Generates Query Plan (JSON)
   {
     "resourceType": "Observation",
     "filters": {
       "codeSearch": {
         "type": "loinc",
         "codes": ["2093-3", "2085-9", "2089-1", "2571-8"],
         "display": "cholesterol"
       }
     },
     "sort": "-effectiveDateTime",
     "limit": null
   }
    ↓
4. Execute Query Plan
   - Use LocalQueryService with generated plan
   - Return results formatted by Gemma
    ↓
5. Gemma Formats Response
   - Takes raw FHIR data
   - Generates human-readable markdown
   - Includes context-aware explanations
```

## Context Building Strategy

### 1. Database Schema Context

Provide Gemma with the complete SQLite schema:

```markdown
## Database Schema

### Table: fhir_resources
- id: TEXT PRIMARY KEY
- patient_id: TEXT NOT NULL
- resource_type: TEXT NOT NULL (e.g., "Observation", "Encounter")
- resource_id: TEXT NOT NULL
- resource_data: TEXT NOT NULL (JSON string of complete FHIR resource)
- created_at: TEXT
- updated_at: TEXT

### Query Patterns:
- Get all resources: SELECT resource_data FROM fhir_resources WHERE patient_id = ? AND resource_type = ?
- Filter by date: Parse JSON and filter by effectiveDateTime
- Search by code: Parse JSON and search in code.coding array
```

### 2. FHIR Resource Structure Context

Provide examples of actual FHIR resources:

```json
{
  "resourceType": "Observation",
  "id": "example-obs-1",
  "status": "final",
  "code": {
    "coding": [
      {
        "system": "http://loinc.org",
        "code": "2093-3",
        "display": "Cholesterol, Total"
      }
    ],
    "text": "Total Cholesterol"
  },
  "valueQuantity": {
    "value": 180,
    "unit": "mg/dL"
  },
  "effectiveDateTime": "2024-01-15T10:30:00Z",
  "subject": {
    "reference": "Patient/14171df9-ec64-4993-abbf-341e8f57c2a7"
  }
}
```

### 3. Medical Terminology Context

Provide the medical glossary with mappings:

```markdown
## Medical Term Mappings

- **Cholesterol** → LOINC codes: 2093-3 (Total), 2085-9 (LDL), 2089-1 (HDL), 2571-8 (Triglycerides)
- **Glucose** → LOINC codes: 2339-0 (Glucose), 4548-4 (HbA1c)
- **Blood Pressure** → LOINC codes: 85354-9 (BP), 8480-6 (Systolic), 8462-4 (Diastolic)
- **Test Results** → Resource Type: DiagnosticReport
- **Visits** → Resource Type: Encounter
```

### 4. Query Examples (Few-Shot Learning)

Provide examples of query → query plan translations:

```json
Example 1:
Query: "show me my recent visits"
Plan: {
  "resourceType": "Encounter",
  "filters": {
    "sort": "-period.start",
    "limit": 10
  }
}

Example 2:
Query: "what are my cholesterol levels"
Plan: {
  "resourceType": "Observation",
  "filters": {
    "codeSearch": {
      "type": "loinc",
      "codes": ["2093-3", "2085-9", "2089-1", "2571-8"],
      "display": "cholesterol"
    },
    "sort": "-effectiveDateTime"
  }
}

Example 3:
Query: "show me record 8 of my test results"
Plan: {
  "resourceType": "DiagnosticReport",
  "filters": {
    "sort": "-effectiveDateTime"
  },
  "recordIndex": 7  // 0-based index
}
```

## Gemma Prompt Template

```markdown
You are a healthcare data query assistant. Your task is to convert natural language queries into structured query plans for a local FHIR database.

## Database Schema
[Insert SQLite schema documentation]

## FHIR Resource Examples
[Insert example Observation, Encounter, DiagnosticReport resources]

## Medical Terminology
[Insert medical glossary with LOINC code mappings]

## Query Examples
[Insert few-shot examples]

## Current Query
User asks: "{user_query}"
Patient ID: {patient_id}

## Your Task
Generate a JSON query plan with this structure:
{
  "resourceType": "Observation|Encounter|DiagnosticReport|...",
  "filters": {
    "codeSearch": {
      "type": "loinc|display|text",
      "codes": ["code1", "code2"],
      "display": "search term"
    },
    "sort": "-effectiveDateTime|period.start|...",
    "limit": 10,
    "status": "final|active|..."
  },
  "recordIndex": null or 0-based index number,
  "intent": "human-readable intent description"
}

Think step by step:
1. What resource type does this query relate to?
2. What specific filters are needed (codes, dates, status)?
3. How should results be sorted?
4. Is a specific record requested?
5. What is the user's intent?

Generate the JSON query plan:
```

## Implementation Strategy

### Phase 1: Enhanced Context Retrieval

1. **Vectorize Documentation**:
   - Create embeddings for database schema
   - Create embeddings for FHIR resource examples
   - Create embeddings for medical glossary
   - Store in a simple in-memory vector store (or use a lightweight library)

2. **Semantic Search**:
   - When user asks a query, generate query embedding
   - Find top-k relevant chunks from documentation
   - Include these in Gemma's context

### Phase 2: Gemma Integration

1. **Build Comprehensive Prompt**:
   - Start with role and task definition
   - Add retrieved context chunks
   - Add few-shot examples
   - Add current query

2. **Call Gemma** (when integrated):
   - Send prompt to Gemma 2B model
   - Parse JSON response
   - Validate query plan structure

3. **Execute Query Plan**:
   - Use LocalQueryService with generated plan
   - Apply filters, sorting, indexing as specified

### Phase 3: Response Generation

1. **Format Results with Gemma**:
   - Take raw FHIR resources
   - Provide context: "Format these Observation resources about cholesterol levels"
   - Let Gemma generate human-readable markdown
   - Include explanations, trends, normal ranges if applicable

## Advantages of This Approach

1. **Natural Language Understanding**: Gemma understands synonyms, variations, and context
   - "cholesterol" = "cholesterol levels" = "my cholesterol" = "total cholesterol"

2. **Complex Query Handling**: Can understand multi-part queries
   - "show me my cholesterol from the last 6 months"
   - "what was my highest glucose reading this year?"

3. **Extensibility**: Adding new query types doesn't require code changes
   - Just add examples to the context
   - Gemma learns from examples

4. **Context-Aware**: Understands relationships
   - "test results" → DiagnosticReport
   - "lab values" → Observation
   - "visits" → Encounter

5. **Intelligent Filtering**: Can combine multiple criteria
   - "cholesterol levels above 200"
   - "recent medications that are active"

## Current Implementation vs. Gemma Approach

### Current (Brute Force):
```dart
if (query.contains('cholesterol')) {
  return filterByCode(['2093-3', '2085-9', ...]);
}
```

### Gemma Approach:
```dart
final context = await buildGemmaContext(query);
final prompt = buildPrompt(context, query);
final queryPlan = await gemma.generate(prompt);
return executeQueryPlan(queryPlan);
```

## Migration Path

1. **Keep Current Implementation**: As fallback
2. **Add Gemma Context Builder**: Build comprehensive context
3. **Add Gemma Prompt Generator**: Create structured prompts
4. **Integrate Gemma 2B**: When available, call model
5. **Hybrid Approach**: Use Gemma for complex queries, pattern matching for simple ones
6. **Gradual Migration**: Start with complex queries, expand coverage

## Example: Complex Query Handling

**User Query**: "What was my highest cholesterol reading in the past year, and when was it?"

**Gemma's Query Plan**:
```json
{
  "resourceType": "Observation",
  "filters": {
    "codeSearch": {
      "type": "loinc",
      "codes": ["2093-3", "2085-9", "2089-1", "2571-8"]
    },
    "dateRange": {
      "field": "effectiveDateTime",
      "start": "2023-12-01",
      "end": "2024-12-01"
    }
  },
  "sort": "-valueQuantity.value",
  "limit": 1,
  "intent": "Find highest cholesterol value in past year with date"
}
```

**Gemma's Response**:
```markdown
# Your Highest Cholesterol Reading

**Value**: 220 mg/dL (Total Cholesterol)
**Date**: March 15, 2024
**Status**: Above normal range (Normal: <200 mg/dL)

This was your highest reading in the past year. Consider discussing this with your healthcare provider.
```

## Next Steps

1. **Implement Context Builder**: Create service to build comprehensive context
2. **Create Prompt Templates**: Structured prompts for different query types
3. **Add Vector Search**: For semantic retrieval of relevant context
4. **Integrate Gemma 2B**: When model is available
5. **Test with Complex Queries**: Validate approach with real user queries
6. **Iterate and Improve**: Refine prompts and examples based on results

## Benefits

- **Scalable**: No need to hardcode every query pattern
- **Intelligent**: Leverages LLM understanding of language and context
- **Maintainable**: Updates through documentation, not code
- **User-Friendly**: Handles natural language variations
- **Extensible**: Easy to add new query types and capabilities



