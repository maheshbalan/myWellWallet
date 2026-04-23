# Update Summary — April 23, 2026

This update delivers **WP1: Chatbot Pipeline Hardening**, a twelve-subphase work package that fixes a set of silent-data-loss bugs in the FHIR sync path, tightens the prompt-construction pipeline against both truncation corruption and user-input injection, and removes a stack of UI footguns around concurrent submission, the typing indicator, and mid-stream timeouts.

Every fix ships with unit coverage; one fix also ships with a live MCP smoke test that runs against production infrastructure with a known Synthea-generated patient.

## Highlights

### 1. FHIR retrieval correctness (HIGH)
- **MedicationStatement and Condition now use `patient=`** per FHIR spec. The previous `subject=` filter silently returned empty bundles from compliant servers — users saw no medications or conditions even when their chart had data.
- **DiagnosticReport routes to `request_generic_resource`** instead of the DocumentReference tool. The MCP server has no dedicated DiagnosticReport tool (see `docs/FHIR_MCP_SERVER_README.md`), so lab reports never synced under the old mapping.
- **One source of truth for resource-type routing**: `DataSyncService` now exposes static `searchParamFor`, `pathFor`, and `toolFor` helpers. Both the sync path and `QueryProvider._fallbackToMCP` use these, so the FHIR-spec mappings can't drift between the two paths.
- **Live verification**: `test/integration/data_sync_live_smoke_test.dart` (opt-in via `SMOKE_LIVE=1`) hits `mcp-fhir-server.com` with Ruben688 Waters156 and asserts every resource type returns a valid searchset Bundle with the correct `patient=` / `subject=` filter echoed in the server response.

### 2. Prompt construction hardening (HIGH / MEDIUM)
- **Budget-aware prompt builders**: `GemmaModelService.capPromptToBudget` preserves the trailing `<start_of_turn>model` marker at all costs. The response builders fit within the platform char budget by dropping oldest history turn pairs first, then tail records — never mid-JSON clipping. Truncation emits explicit log lines with byte counts.
- **Prompt-injection sanitization**: `sanitizeForPrompt` strips Gemma control markers (`<start_of_turn>`, `<end_of_turn>`, `<bos>`, `<eos>`, `<|im_start|>`, `<|im_end|>`, plus case-insensitive / whitespace-tolerant variants) and collapses whitespace runs so a user query can no longer escape the user turn or pad-attack the prompt budget. Applied to query + history content at every prompt-building site.

### 3. Conversation state (HIGH / MEDIUM)
- **Single `GemmaService` instance**: `QueryProvider` is now the canonical owner; `HomeScreen` reads it via `context.read<QueryProvider>().gemmaService`. The old dual-instance pattern (HomeScreen constructed its own, QueryProvider constructed another) caused conversation history to diverge silently. A regression test scans `lib/` and asserts exactly one `GemmaService(` construction site remains.
- **Resource-type repetition fixed (pre-WP1)**: removed the silent `_lastSuccessfulResourceType` reuse in `GemmaRAGService` that caused distinct questions to return the same data with different wording. Added explicit rules for `MedicationStatement`, `AllergyIntolerance`, and `Condition` so those resource types route correctly without relying on the fallback.

### 4. RAG / retrieval tightening (MEDIUM)
- **`LocalQueryService.filterByCodeSearch`** now matches display / text with a word-boundary regex instead of substring, so a search for `"test"` no longer pulls in "testicular examination" rows. LOINC code lookup still handles resources with sparse metadata. Added `ldl`, `hdl`, `triglycerides`, and `heart rate` to the medical-term → LOINC map.
- **`LocalRAGService.translateHumanTerm`** replaces bidirectional substring matching with forward-only word-boundary regex. Drops the reverse direction that used to let tokens like `"med"` win against the `"medication"` key or false-match `"meditation"` / `"drugstore"`.
- **Dead RAG plumbing removed**: `retrieveContext` chunks were being fetched on every streaming response and threaded through the three builders but never inserted into the prompt. Plumbing deleted; the intent phase still uses RAG chunks where they belong.

### 5. Chat UI robustness (HIGH / LOW)
- **Identity-based typing indicator**: `removeTypingIndicator` strips tagged entries regardless of position, so an interleaving `_messages` mutation between add and remove no longer deletes the wrong message.
- **Concurrent-submit guard**: pure `shouldAcceptNewQuery` / `isInputLocked` helpers in `lib/providers/query_concurrency.dart` back both `QueryProvider.processQuery` (early-returns if already processing) and `HomeScreen._processQuery` (tracks `_isStreaming`, disables the send button / text field / mic / follow-up chips while locked).
- **Follow-up prompt chips** now cover medication, allergy, and condition queries with cross-category suggestions (after meds → conditions + allergies + visits, etc.), matching the resource types supported by the rule engine.
- **Stream-timeout signalling**: when MedGemma's 90-second timeout fires after some tokens have already streamed, the user now sees a trailing `_(response truncated — the model took too long; try rephrasing)_` notice. The notice is NOT recorded in conversation history; follow-up turns stay clean. Zero-token timeout still falls through to the structured summary fallback, but production logs distinguish the two cases.

## Developer tooling

- **Shared test helpers** under `test/_fixtures/` and `test/_helpers/`:
  - `fhir_bundles.dart` — mixed-observation fixture for RAG / codeSearch tests
  - `prompt_matchers.dart` — `endsWithModelMarker`, `hasExactlyOneModelMarker`, `hasNoExtraTurnMarkers`
  - `fake_gemma_model.dart` — `StreamController`-backed scripted streams for timeout scenarios without touching the real model
- **New unit suites** (120 tests across Phase 1–3):
  - `data_sync_service_paths_test.dart` (22)
  - `gemma_service_prompt_test.dart` (17) + `prompt_sanitize_test.dart` (14) + `gemma_service_timeout_test.dart` (5)
  - `typing_indicator_helpers_test.dart` (7) + `follow_up_prompts_test.dart` (9)
  - `query_concurrency_test.dart` (10) + `gemma_service_singleton_test.dart` (1)
  - `local_query_service_codesearch_test.dart` (10) + `local_rag_translate_test.dart` (24)
- **Opt-in live smoke**: `test/integration/data_sync_live_smoke_test.dart` (gated on `SMOKE_LIVE=1`) — 8 cases against production MCP.

## Gate state at merge

- `flutter analyze lib/` — 116 issues (baseline 117 → net reduction of 1; all pre-existing)
- `flutter test` — 120/120 green
- Live MCP smoke — 8/8 green
- Manual device integration pass — outstanding; all logic is covered by automated tests, the device check is confirmatory

Full breakdown and per-subphase checklists live in [claude_docs/WP1.md](../claude_docs/WP1.md).
