# Gemma 2B Integration with RAG for MCP Protocol Understanding

## Overview

This document explains how to integrate Gemma 2B (or similar local LLM) with Retrieval-Augmented Generation (RAG) to enable natural language query interpretation and conversion to FHIR MCP Gateway queries.

## Current Implementation

Currently, the app uses **rule-based pattern matching** in `NLPService` to interpret queries. This works for common queries but is limited and doesn't scale well.

## Why RAG is Needed

Gemma 2B is a general-purpose LLM that doesn't inherently understand:
1. **MCP Protocol**: The Model Context Protocol structure and available tools
2. **FHIR Resources**: Healthcare data structures and search parameters
3. **Query Mapping**: How natural language maps to specific FHIR queries

RAG solves this by providing relevant context at query time without requiring fine-tuning.

## RAG Architecture

### 1. Knowledge Base Components

Create a vector database (e.g., using Pinecone, Chroma, or local embeddings) with:

#### A. MCP Tool Documentation
```json
{
  "tool": "request_patient_resource",
  "description": "Retrieve patient information from FHIR server",
  "parameters": {
    "request": {
      "method": "GET|POST|PUT|DELETE",
      "path": "FHIR resource path with search parameters",
      "body": "Optional request body for POST/PUT"
    }
  },
  "examples": [
    {
      "query": "show me my patient information",
      "params": {
        "request": {
          "method": "GET",
          "path": "/Patient/{patientId}"
        }
      }
    }
  ]
}
```

#### B. FHIR Resource Documentation
```json
{
  "resource": "Encounter",
  "description": "Represents a patient visit or interaction with healthcare system",
  "search_parameters": {
    "subject": "Filter by patient ID (e.g., subject=Patient/{id})",
    "date": "Filter by date (e.g., date=ge2024-01-01)",
    "_sort": "Sort results (e.g., _sort=-date for most recent first)",
    "_count": "Limit results (e.g., _count=10)"
  },
  "common_queries": [
    "show me my recent visits",
    "what are my appointments",
    "timeline of my healthcare"
  ]
}
```

#### C. Query Examples
```json
{
  "natural_language": "show me the most recent timeline",
  "intent": "recent_timeline",
  "tool": "request_encounter_resource",
  "params": {
    "request": {
      "method": "GET",
      "path": "/Encounter?subject=Patient/{patientId}&_sort=-date&_count=20"
    }
  }
}
```

### 2. Embedding Strategy

1. **Chunk Documents**: Break documentation into semantic chunks (200-500 tokens)
2. **Generate Embeddings**: Use a local embedding model (e.g., `all-MiniLM-L6-v2` or `sentence-transformers`)
3. **Store in Vector DB**: Index chunks with metadata (tool name, resource type, etc.)

### 3. Query Processing Flow

```
User Query: "show me my medications"
    ↓
1. Generate query embedding
    ↓
2. Retrieve top-k relevant chunks from vector DB
    ↓
3. Build prompt with:
   - Retrieved context (MCP tools, FHIR resources, examples)
   - User query
   - Current patient context
    ↓
4. Send to Gemma 2B for interpretation
    ↓
5. Parse Gemma response → Extract tool name and params
    ↓
6. Execute MCP tool call
```

## Implementation Steps

### Step 1: Set Up Local Embeddings

```dart
// Add to pubspec.yaml
dependencies:
  # For local embeddings (if available)
  # Or use HTTP API to embedding service
  http: ^1.1.0
```

### Step 2: Create RAG Service

```dart
class RAGService {
  // Load knowledge base embeddings
  Future<void> initialize() async {
    // Load pre-computed embeddings for:
    // - MCP tool documentation
    // - FHIR resource docs
    // - Query examples
  }
  
  // Retrieve relevant context for query
  Future<List<String>> retrieveContext(String query) async {
    // 1. Generate query embedding
    // 2. Find similar chunks in vector DB
    // 3. Return top-k relevant chunks
  }
  
  // Build prompt with RAG context
  String buildPrompt(String query, List<String> context, String? patientId) {
    return '''
Context: You are a healthcare assistant that converts natural language queries to FHIR MCP Gateway queries.

Available MCP Tools:
${context.join('\n')}

Current Patient ID: ${patientId ?? 'Not set'}

User Query: "$query"

Convert this query to a JSON object with:
- tool: MCP tool name
- params: Tool parameters (request object with method, path, body)
- intent: User intent

Example:
Query: "show me my medications"
Response: {
  "tool": "request_medication_resource",
  "params": {
    "request": {
      "method": "GET",
      "path": "/MedicationStatement?subject=Patient/$patientId&_sort=-date&_count=10",
      "body": null
    }
  },
  "intent": "list_medications"
}
''';
  }
}
```

### Step 3: Integrate with Gemma 2B

```dart
class GemmaService {
  final RAGService _ragService = RAGService();
  
  Future<Map<String, dynamic>> interpretQueryWithContext(
    String query,
    String? patientId,
  ) async {
    // 1. Retrieve relevant context
    final context = await _ragService.retrieveContext(query);
    
    // 2. Build prompt with RAG context
    final prompt = _ragService.buildPrompt(query, context, patientId);
    
    // 3. Call Gemma 2B (via platform channel or HTTP)
    final response = await _callGemma2B(prompt);
    
    // 4. Parse JSON response
    return jsonDecode(response);
  }
  
  Future<String> _callGemma2B(String prompt) async {
    // Option 1: Use platform channels to call native Gemma 2B
    // Option 2: Use HTTP API if Gemma is running as a service
    // Option 3: Use onnxruntime or similar for on-device inference
  }
}
```

## Alternative: Few-Shot Prompting (No RAG)

If RAG setup is complex, use **few-shot prompting** with hardcoded examples:

```dart
String buildPrompt(String query, String? patientId) {
  return '''
You are a healthcare assistant. Convert natural language to FHIR MCP queries.

Examples:
1. Query: "show me my medications"
   Response: {"tool": "request_medication_resource", "params": {"request": {"method": "GET", "path": "/MedicationStatement?subject=Patient/$patientId&_sort=-date&_count=10", "body": null}}, "intent": "list_medications"}

2. Query: "most recent timeline"
   Response: {"tool": "request_encounter_resource", "params": {"request": {"method": "GET", "path": "/Encounter?subject=Patient/$patientId&_sort=-date&_count=20", "body": null}}, "intent": "recent_timeline"}

3. Query: "recent tests"
   Response: {"tool": "request_observation_resource", "params": {"request": {"method": "GET", "path": "/Observation?subject=Patient/$patientId&_sort=-date&_count=10", "body": null}}, "intent": "list_observations"}

Current Patient ID: ${patientId ?? 'Not set'}

Query: "$query"
Response (JSON only):
''';
}
```

## Recommendation

**Start with Few-Shot Prompting** (simpler, faster to implement):
- Add 10-20 example query→tool mappings to Gemma prompts
- Test with real queries
- Iterate based on results

**Upgrade to RAG later** if:
- You need to support many more query types
- Tool documentation changes frequently
- You want to add new FHIR resources dynamically

## Current Status

The app currently uses rule-based matching as a fallback. To enable Gemma 2B:

1. **Short-term**: Implement few-shot prompting in `GemmaService.interpretQueryWithContext()`
2. **Long-term**: Set up RAG with vector database for scalable query interpretation

## Next Steps

1. ✅ Add patient context to FHIR queries (DONE)
2. ⏳ Implement few-shot prompting in GemmaService
3. ⏳ Test with real queries
4. ⏳ Set up RAG infrastructure (if needed)
5. ⏳ Fine-tune based on user feedback

