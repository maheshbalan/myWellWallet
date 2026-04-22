# Design: Fetch Health Data & Local RAG Implementation

## Overview

This document outlines the design for implementing:
1. **Fetch My Data** feature - Complete data synchronization from FHIR MCP Gateway
2. **Local RAG System** - Natural language query processing with local-first approach
3. **Vector Database** - Embedding and retrieval of FHIR data for RAG

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MyWellWallet App                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │   Home Tab   │  │ Fetch Data   │  │   Profile    │    │
│  │  (Queries)   │  │    Tab       │  │              │    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
│         │                  │                  │            │
│         └──────────────────┼──────────────────┘            │
│                            │                               │
│         ┌──────────────────▼──────────────────┐           │
│         │      Query Processing Layer         │           │
│         │  (Gemma + Local RAG + NLP)         │           │
│         └──────────────────┬──────────────────┘           │
│                            │                               │
│         ┌──────────────────▼──────────────────┐           │
│         │      Data Access Layer              │           │
│         │  ┌────────────┐  ┌────────────┐    │           │
│         │  │  SQLite    │  │  Vector DB │    │           │
│         │  │  (FHIR)    │  │  (RAG)     │    │           │
│         │  └────────────┘  └────────────┘    │           │
│         └──────────────────┬──────────────────┘           │
│                            │                               │
│         ┌──────────────────▼──────────────────┐           │
│         │   FHIR MCP Gateway Client           │           │
│         │   (mcp-fhir-server.com)             │           │
│         └──────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

## Phase 1: Fetch My Data Tab

### 1.1 UI Design

**New Tab: "Fetch Data"**
- Location: Bottom navigation or as a new screen accessible from home
- Layout:
  ```
  ┌─────────────────────────────────────┐
  │  Fetch My Health Data               │
  ├─────────────────────────────────────┤
  │                                     │
  │  [Fetch All Data] Button           │
  │                                     │
  │  Progress Section:                  │
  │  ┌─────────────────────────────┐   │
  │  │ Step 1: Fetching Patients   │   │
  │  │ ✓ Completed (1 record)       │   │
  │  └─────────────────────────────┘   │
  │  ┌─────────────────────────────┐   │
  │  │ Step 2: Fetching Encounters │   │
  │  │ ⏳ In Progress...            │   │
  │  └─────────────────────────────┘   │
  │                                     │
  │  Summary:                           │
  │  • Patients: 1                      │
  │  • Encounters: 0                    │
  │  • Observations: 0                  │
  │  • Medications: 0                   │
  │  • Conditions: 0                    │
  │  • ...                              │
  └─────────────────────────────────────┘
  ```

### 1.2 Data Fetching Strategy

**Step 1: Initialize & Clear Local Data**
- Truncate all FHIR resource tables
- Clear vector database (if exists)
- Reset fetch status

**Step 2: Fetch Patient Data**
- Use current logged-in patient ID
- Fetch patient resource
- Save to SQLite

**Step 3: Fetch Related Resources (Parallel where possible)**
For each resource type:
1. **Encounters**: `/Encounter?subject=Patient/{id}&_count=1000`
2. **Observations**: `/Observation?subject=Patient/{id}&_count=1000`
3. **Medications**: `/MedicationStatement?subject=Patient/{id}&_count=1000`
4. **Conditions**: `/Condition?subject=Patient/{id}&_count=1000`
5. **Allergies**: `/AllergyIntolerance?patient=Patient/{id}&_count=1000`
6. **Immunizations**: `/Immunization?patient=Patient/{id}&_count=1000`
7. **Diagnostic Reports**: `/DiagnosticReport?subject=Patient/{id}&_count=1000`
8. **Document References**: `/DocumentReference?subject=Patient/{id}&_count=1000`
9. **Family History**: `/FamilyMemberHistory?patient=Patient/{id}&_count=1000`

**Step 4: Handle Pagination**
- Check for `link` with `relation="next"` in Bundle responses
- Continue fetching until no more pages

**Step 5: Save to SQLite**
- Parse FHIR Bundle entries
- Extract individual resources
- Save to appropriate tables
- Track counts per resource type

**Step 6: Generate Summary**
- Count records per resource type
- Display completion status
- Show any errors encountered

### 1.3 Implementation Files

```
lib/
├── screens/
│   └── fetch_data_screen.dart          # New screen for data fetching
├── services/
│   ├── data_sync_service.dart          # Orchestrates data fetching
│   └── fhir_persistence_service.dart  # Enhanced with truncate/bulk operations
├── models/
│   └── fetch_status.dart                # Model for fetch progress
└── widgets/
    └── fetch_progress_card.dart        # Reusable progress indicator
```

## Phase 2: Local RAG System

### 2.1 Knowledge Base Documents

**Documents to Vectorize:**
1. `docs/README_MOBILE_CLIENT.md` - MCP protocol documentation
2. `docs/FHIR_MCP_SERVER_README.md` - Server capabilities (if exists)
3. `docs/SQLITE_SCHEMA.md` - SQLite database schema (to be generated)
4. `docs/GEMMA_RAG_APPROACH.md` - RAG approach documentation
5. FHIR Resource Type documentation (embedded in code)

### 2.2 SQLite Schema Documentation

Generate `docs/SQLITE_SCHEMA.md` with:
- Table structures for each FHIR resource
- Column mappings (FHIR field → SQLite column)
- Query examples for common searches
- Indexes and relationships

### 2.3 Local RAG Components

**2.3.1 Embedding Model**
- Use lightweight local embedding model
- Options:
  - `all-MiniLM-L6-v2` (via HTTP API or local)
  - `sentence-transformers` (if available)
  - Flutter-compatible embedding library

**2.3.2 Vector Storage**
- Store embeddings in SQLite with vector extension
- Or use simple cosine similarity with stored embeddings
- Table: `document_embeddings`
  - `id`, `document_type`, `content`, `embedding` (JSON array)

**2.3.3 RAG Service**
```dart
class LocalRAGService {
  // Initialize: Load and embed all docs
  Future<void> initialize() async;
  
  // Retrieve relevant context for query
  Future<List<String>> retrieveContext(String query) async;
  
  // Build prompt with RAG context
  String buildPrompt(String query, List<String> context, String? patientId);
}
```

### 2.4 Query Processing Flow

```
User Query: "show me my medications"
    ↓
1. Generate query embedding
    ↓
2. Retrieve top-k relevant chunks from vector DB
    ↓
3. Build prompt with:
   - Retrieved context (SQLite schema, MCP protocol, FHIR resources)
   - User query
   - Current patient context
    ↓
4. Send to Gemma 2B for interpretation
    ↓
5. Parse Gemma response → Extract:
   - Query type (local SQLite vs MCP Gateway)
   - Resource type
   - Search parameters
    ↓
6a. If local: Query SQLite database
6b. If not found or MCP needed: Query MCP Gateway
    ↓
7. Format results as markdown
    ↓
8. Display in conversational UI
```

## Phase 3: Vectorization of FHIR Data

### 3.1 Embedding Strategy

**For each FHIR resource:**
- Extract text fields (name, description, value, etc.)
- Generate embedding
- Store in `fhir_resource_embeddings` table
- Link to original resource via `resource_id` and `resource_type`

**3.2 Chunking Strategy**
- Patient: Full resource (small)
- Encounters: Per encounter with date context
- Observations: Per observation with value and date
- Medications: Per medication statement
- Conditions: Per condition with onset date
- Diagnostic Reports: Per report with findings

### 3.3 Retrieval Process

When user asks natural language query:
1. Generate query embedding
2. Search `fhir_resource_embeddings` for similar resources
3. Retrieve top-k matching resources
4. Use Gemma to format as natural language response
5. Display in markdown format

## Implementation Steps

### Step 1: Update MCP Server URL
- [x] Replace `mcp-fhir-server-maheshbalan1.replit.app` with `mcp-fhir-server.com`
- [x] Test connection

### Step 2: Generate SQLite Schema Documentation
- [x] Analyze database_service.dart
- [x] Document all tables and columns
- [x] Create `docs/SQLITE_SCHEMA.md`

### Step 3: Create Fetch Data Screen
- [x] Create `fetch_data_screen.dart`
- [x] Add navigation to new screen
- [x] Implement UI with progress indicators
- [x] Add step indicators (Cleaning Database, Fetching from FHIR MCP Gateway, Storing in Local Database)
- [x] Show database storage confirmation
- [x] Persist fetch summaries to database
- [x] Load and display last fetch summary

### Step 4: Implement Data Sync Service
- [x] Create `data_sync_service.dart`
- [x] Implement truncate functionality
- [x] Implement resource fetching (one type at a time)
- [x] Add progress callbacks
- [x] Add step status callbacks
- [x] Handle pagination (via _count=1000)
- [x] Note: Uses name and DOB for patient matching when fetching data

### Step 5: Enhance FHIR Persistence
- [x] Add truncate methods
- [x] Add bulk insert methods
- [x] Optimize for large datasets
- [x] Add fetch summary persistence

### Step 6: Implement Local RAG (Basic)
- [x] Create `local_rag_service.dart`
- [x] Implement document embedding (simple approach first - keyword-based retrieval)
- [x] Implement retrieval
- [x] Integrate with GemmaService

### Step 7: Update Query Processing
- [x] Modify QueryProvider to use local RAG
- [x] Add SQLite query generation (via LocalQueryService)
- [x] Implement local-first, MCP-fallback logic

### Step 8: Vectorize FHIR Data
- [ ] Create embedding service for FHIR resources
- [ ] Implement batch embedding during fetch
- [ ] Store embeddings in database

### Step 9: Markdown Response Formatting
- [x] Create markdown formatter (in LocalQueryService)
- [x] Format FHIR data as human-readable text
- [ ] Add copy-to-clipboard functionality

## UI/UX Improvements Completed

- [x] Redesign home screen for older users (larger text, better spacing, prominent search bar)
- [x] Improve Test and Download icon styling with colored backgrounds
- [x] Add Date of Birth editing to profile screen
- [x] Display DOB in profile view
- [x] Clean up MCP SSE test screen with step indicators

## Testing Strategy

1. **Unit Tests**: Each service independently
2. **Integration Tests**: Full fetch flow
3. **Manual Testing**: Step-by-step with user feedback
4. **Performance Tests**: Large dataset handling

## Future Enhancements

1. **Incremental Fetching**: Only fetch new/updated resources
2. **Background Sync**: Periodic automatic updates
3. **Conflict Resolution**: Handle data conflicts
4. **Offline Mode**: Full functionality without network
5. **Advanced RAG**: Multi-hop reasoning, citation support

