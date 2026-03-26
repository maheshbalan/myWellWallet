# Gemma Integration in MyWellWallet

This document describes how the **Gemma 2 2B** on-device LLM is integrated into the MyWellWallet Flutter app: configuration, download and loading, usage in RAG and streaming responses, and UI behavior.

---

## 1. Overview

- **Model**: Gemma 2 2B IT, GGUF format (Q2_K quantization, ~1.2GB), from Hugging Face.
- **Runtime**: `llamadart` (^0.6.4) for loading GGUF and generating text on device.
- **Roles**:
  - **Query interpretation**: Turn natural language into structured FHIR query plans (with RAG context).
  - **Result formatting**: Optionally format query results as markdown.
  - **Streaming answers**: In the home chat, stream a natural-language summary of fetched health data using conversation history and RAG context.

When the model is not configured, still downloading, or fails, the app falls back to rule-based interpretation and simple markdown formatting without crashing.

---

## 2. Configuration

### 2.1 Central config

**File**: `lib/config/app_config.dart`

- `AppConfig.gemmaModelUrl`: URL of the GGUF model file (Hugging Face `MaziyarPanahi/gemma-2-2b-it-GGUF`, `gemma-2-2b-it.Q2_K.gguf`).
- `AppConfig.gemmaModelFileName`: Filename used when saving the file locally (`gemma-2-2b-it.Q2_K.gguf`).

If `gemmaModelUrl` is empty, the model is not downloaded or loaded; `GemmaModelService.isConfigured` is false and all Gemma-dependent code paths use fallbacks.

The model is **lazy-loaded on first use** (no load at app startup) so the OS does not kill the app for memory; see `docs/GEMMA_MLX_AND_MEMORY.md` for the MLX-based roadmap and memory controls.

### 2.2 Dependencies

**File**: `pubspec.yaml`

- `path_provider: ^2.1.1` – application support directory for storing the model.
- `llamadart: ^0.6.4` – GGUF load and inference (generate / generateStream).

No separate asset bundle is used for the model; it is downloaded once and stored under the app support directory.

---

## 3. Model lifecycle: download and load

### 3.1 Singleton service

**File**: `lib/services/gemma_model_service.dart`

- **Class**: `GemmaModelService` (singleton via `GemmaModelService.instance`).
- **Responsibilities**:
  - Decide if a model is configured (`isConfigured`).
  - Download the GGUF from `AppConfig.gemmaModelUrl` if not present.
  - Load the model into a `LlamaEngine` and expose `generate` and `generateStream`.
  - Expose download progress and state for the UI.

### 3.2 State flags

- `isConfigured`: `AppConfig.gemmaModelUrl.isNotEmpty`.
- `isReady`: Model is loaded and inference is available.
- `isDownloading`: A download is in progress.
- `currentProgress`: 0.0–1.0; also emitted on `downloadProgress` stream.

### 3.3 Download and storage

- **Directory**: `getApplicationSupportDirectory()/models/`.
- **File**: `AppConfig.gemmaModelFileName`.
- **Validation**: File must exist and size &gt; 1 GB (Q2_K ~1.2GB).
- **Alternate paths** (e.g. Linux Snap): A short list of alternative paths is checked; if a valid file is found, it is copied to the primary path.
- **Download**: HTTP GET with `http` package; progress is computed from `contentLength` and pushed to `downloadProgress` and `currentProgress`. On failure, the partial file is deleted and the exception is rethrown.
- Only one download runs at a time; concurrent callers wait if `_downloading` is true.

### 3.4 Engine initialization

- **Entry point**: `ensureInitialized()`.
- If not configured or already initialized/initializing, it returns (or waits for the ongoing init).
- Otherwise it:
  1. Calls `_ensureModelDownloaded()` to get a path to a valid GGUF file.
  2. Creates `LlamaBackend()` and `LlamaEngine(backend)`.
  3. Loads the model with `ModelParams`:
     - **Mobile** (Android/iOS): `gpuLayers: ModelParams.maxGpuLayers` (GPU when available).
     - **Desktop**: `gpuLayers: 0` to force CPU and avoid conflicts with Flutter.
  4. Sets `_initialized = true` on success; on exception, logs and leaves `_initialized` false.

### 3.5 Generation API

- `generate(String prompt)`: `ensureInitialized()`, then consumes `_engine!.generate(prompt)` into a single string and returns it (or null on error).
- `generateStream(String prompt)`: Same init, then yields tokens from `_engine!.generate(prompt)`.

All errors are logged via `LogService`; callers are expected to handle null or empty stream and fall back to non-Gemma behavior.

---

## 4. Where Gemma is used in the app

### 4.1 Startup

**File**: `lib/main.dart`

- `GemmaRAGService` is constructed with `LocalQueryService` and `DatabaseService`.
- In `_safeInit()`:
  1. `_gemmaRAGService.initialize()` is awaited (RAG docs load; Gemma model init is *not* awaited there).
  2. `GemmaModelService.instance.ensureInitialized()` is awaited so that by the time the shell is built, the model is either ready or failed (and download may have run).
- When building providers, `QueryProvider` receives `_gemmaRAGService` via `setGemmaRAGService(_gemmaRAGService)`.

So: RAG initializes first; then the app explicitly waits for Gemma model download/load before continuing. The home screen and query path can assume “init has been attempted” and then check `isReady` / `isDownloading` for UI and fallbacks.

### 4.2 Query path (RAG + optional Gemma)

**File**: `lib/providers/query_provider.dart`

- If `_gemmaRAGService != null`, the main path is:
  1. `_gemmaRAGService!.processQuery(query, _currentPatientId)`.
  2. If result type is `clarification`, show clarification question/options.
  3. If result type is `queryPlan`, call `executeQueryPlan`; on success, result contains `resources` (and type/count) for the UI; on `fallbackToMCP`, MCP is used; otherwise no-results/error message.
- If RAG is not used or does not apply, fallback is `gemmaService.interpretQueryWithContext(...)` and then local/MCP logic as before.

So the “advanced” path is RAG + query plan execution; the simpler path still uses `GemmaService` for intent and then local/MCP.

### 4.3 GemmaRAGService (interpretation and formatting)

**File**: `lib/services/gemma_rag_service.dart`

- **Constructor**: Takes `LocalQueryService` and `DatabaseService`.
- **initialize()**: Initializes `LocalRAGService`, then starts `GemmaModelService.instance.ensureInitialized()` in the background (unawaited).
- **processQuery(query, patientId)**:
  1. Adds the user message to internal conversation history.
  2. Gets RAG context: `_ragService.retrieveContext(query)`.
  3. **Interpretation**:
     - If `GemmaModelService.instance.isReady`, builds a prompt with `_buildQueryGenerationPrompt(query, patientId, contextChunks)` and calls `gemma.generate(prompt)`. The response is parsed as JSON via `_parseGemmaJsonResponse` (finds first `{` and last `}` to strip extra text).
     - If Gemma is not ready or returns invalid JSON, falls back to `_interpretQueryWithRAG` (rule-based) using the same RAG chunks.
  4. If the interpretation says `needsClarification`, returns a clarification payload.
  5. Otherwise builds a result with `queryPlan` (and optional `interpretation`) for the provider.
- **executeQueryPlan**: Uses `LocalQueryService.queryLocal` with the plan’s `resourceType`, `filters`, `recordIndex`; returns success with `resources` (and type/count) or no-results/fallback/error. It does *not* call Gemma again here; the UI layer uses those resources with `GemmaService` for streaming (see below).
- **Result formatting (optional)**:
  - `_formatResultsWithGemma` builds a formatting prompt and, if `GemmaModelService.instance.isConfigured`, calls `gemma.generate(prompt)`; on failure or if not configured, uses `_queryService.formatAsMarkdown(...)`. So formatting can be Gemma or rule-based markdown.

Prompts for query generation include: role (MyWellWallet, healthcare data assistant), list of FHIR resource types and when to use them, optional RAG “Medical Reference Context”, the user query, and instructions to respond only with JSON (query plan or clarification). This is how Gemma is guided to output structured plans.

### 4.4 GemmaService (streaming chat on home screen)

**File**: `lib/services/gemma_service.dart`

- Holds conversation history and uses `LocalRAGService` for context.
- **generateStreamingResponse(query, fhirData)**:
  - If `fhirData` is null/empty, yields a “no matching records” message.
  - Builds a summary list from `fhirData` (e.g. observations, encounters, medications) via `_getSummaryList`.
  - Adds the user message to history.
  - If `GemmaModelService.instance.isReady`:
    - Initializes RAG if needed, gets `retrieveContext(query)`, builds prompt with `_buildResponsePrompt(query, summary, contextChunks)` (includes recent conversation and “NEW RECORDS”).
    - Streams tokens from `gemma.generateStream(prompt)` and yields them; appends full response to history as the model reply.
  - If not ready or on error: yields a markdown summary from `_formatSummaryAsMarkdown(summary)` and adds that as the model reply.

So the home screen’s “AI answer” is either streamed from Gemma (with RAG and conversation context) or a simple markdown summary when Gemma is unavailable.

### 4.5 LocalRAGService (context for Gemma)

**File**: `lib/services/local_rag_service.dart`

- Loads docs from assets: `FHIR_MEDICAL_GLOSSARY.md`, `SQLITE_SCHEMA.md`, `README_MOBILE_CLIENT.md`, `FHIR_MCP_SERVER_README.md`.
- `retrieveContext(query)`: Returns relevant text chunks for the query (e.g. glossary, schema, client/server docs). Used by both `GemmaRAGService` and `GemmaService` to inject context into prompts so Gemma understands FHIR resources, local DB, and medical terms.

---

## 5. UI behavior

### 5.1 Home screen

**File**: `lib/screens/home_screen.dart`

- **Gemma status**:
  - A chip/button shows “Gemma” (or “Offline”) and a bolt icon; amber when `_gemmaReady`, grey when not.
  - `_gemmaReady` is updated from `GemmaModelService.instance.isReady` on a 2-second timer until ready.
- **Download progress**:
  - Listens to `GemmaModelService.instance.downloadProgress`. If progress is between 0 and 1, shows a non-dismissible dialog: “Downloading AI Model”, linear progress bar, and percentage. When progress reaches 1, dialog is closed and a “Gemma model downloaded and ready!” snackbar is shown.
- **Tap on status**:
  - If ready: snackbar “Gemma local AI is active and ready.”
  - If downloading: open the same progress dialog.
  - If not ready and not downloading: show “Starting Gemma initialization…”, call `ensureInitialized()`, then show success or failure (or error) snackbar.

So the user can see when the model is offline vs ready and when it’s downloading, and can trigger init from the home screen.

### 5.2 Profile screen

In the current codebase after pull, the profile screen does **not** contain a dedicated “AI model” or Gemma section; all Gemma status and download UI lives on the home screen.

### 5.3 Logging

**File**: `lib/services/log_service.dart`

- `LogService.log(...)` is used in `GemmaModelService`, `GemmaRAGService`, and `GemmaService` for init, download progress, interpretation/streaming, and errors. Useful for debugging and for the in-app log viewer if present.

---

## 6. Data flow summary

1. **App start**: RAG initializes; then `GemmaModelService.ensureInitialized()` runs (download if needed, then load into LlamaEngine).
2. **User asks a question on home**:
   - `QueryProvider.processQuery` uses `GemmaRAGService.processQuery` when available.
   - RAG retrieves context; if Gemma is ready, it interprets the query to a JSON query plan (or clarification); else rule-based interpretation.
   - If there’s a query plan, `executeQueryPlan` runs against the local DB and returns resources.
   - Home screen receives the result; if it has `resources`, it calls `_gemmaService.generateStreamingResponse(query, fhirData)` to produce the visible reply: either streamed from Gemma (with RAG + history) or markdown summary.
3. **Model config**: Single source in `AppConfig`; no separate asset config file. Disabling Gemma is done by clearing `gemmaModelUrl` (or not setting it).

---

## 7. Tests (reference)

- `test/gemma_standalone_test.dart`: Standalone Flutter target that loads Gemma and runs a simple generate (useful for “run Gemma only”).
- `test/gemma_console_test.dart`: Console script that checks model path and init (e.g. for desktop/Linux).
- `test/gemma_terminal_test.dart`: Uses `llamadart` directly with a hardcoded path (e.g. for quick terminal checks).

These are for development and CI; they do not change the integration design described above.

---

## 8. Summary table

| Component              | Role |
|------------------------|------|
| `AppConfig`            | Model URL and filename (single source of truth). |
| `GemmaModelService`    | Singleton: download GGUF, load with llamadart, expose `generate` / `generateStream` and progress. |
| `GemmaRAGService`      | RAG + Gemma (or rule-based) for query → query plan/clarification; execute plan; optional Gemma formatting. |
| `GemmaService`         | Conversation history + RAG; streaming answer on home screen from Gemma or markdown fallback. |
| `LocalRAGService`      | Load docs, `retrieveContext(query)` for prompts. |
| `QueryProvider`        | Orchestrates RAG path and fallback; passes `GemmaRAGService` from main. |
| Home screen            | Gemma status chip, download dialog, and streaming response via `GemmaService`. |
| Main                   | Builds RAG and waits for Gemma init; injects `_gemmaRAGService` into `QueryProvider`. |

This is how Gemma is integrated end-to-end in the current MyWellWallet codebase.
