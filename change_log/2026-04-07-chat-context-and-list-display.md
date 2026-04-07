# Changelog — 2026-04-07

## Chat Conversation Context & List Display Fixes

### Problems Fixed

**1. Chat had no memory of previous messages**
Each new message was treated as a standalone query. The AI had no awareness of what was said earlier in the session, so follow-up questions like "tell me more" or "what about that?" always failed or triggered a clarification prompt.

**2. Follow-up questions always triggered a generic clarification prompt**
The rule-based query interpreter (`_interpretWithRules`) only matched medical keywords (vitals, vaccines, medications, etc.). Any follow-up phrasing that lacked those keywords returned `needsClarification: true`, surfacing "I'm not sure what you're looking for. Are you asking about:..." regardless of prior context.

**3. AI returned prose summary instead of a structured list**
When the user asked "Show me my immunization record", the AI responded with a narrative sentence ("You have completed one influenza vaccination on August 17, 2016...") instead of a formatted list. The `_buildResponsePrompt` instruction "Summarize ONLY the records... Be concise" caused MedGemma to collapse all records into prose.

**4. "Show me full list" repeated the same narrative answer**
A follow-up like "Show me full list" re-queried the same resource with the same count and the same summarize prompt, producing an identical prose response.

---

### Changes

#### `lib/screens/home_screen.dart`
- In the markdown-response path (pre-formatted results, clarifications, no-data messages), the exchange was never recorded in either service's conversation history. Added explicit `addToHistory` calls after `_addAssistantMessage` so both `GemmaService` and `GemmaRAGService` stay in sync with every turn.

#### `lib/services/gemma_rag_service.dart`
- Added `_lastSuccessfulResourceType` field. Set whenever `processQuery` resolves to a valid query plan; cleared on `clearHistory()`.
- In `_interpretQueryWithRAG`, before the generic clarification fallback: if conversation history exists and a prior resource type is known, treat the query as a follow-up and return a query plan reusing that resource type.
- Follow-up resolver detects "full / all / complete / more / every" keywords and bumps `_count` to 50 to fetch the complete record set.

#### `lib/services/gemma_service.dart`
- Added `_isListIntent(String query)` — detects list-oriented queries containing "list", "show", "all", "full", "display", "record(s)", or queries starting with "get".
- `_buildResponsePrompt` now switches between two instruction sets based on intent:
  - **List intent**: instructs MedGemma to format each record as an individual bullet point (`- **Name** — Date — Status/Value`), never collapsing records into a single sentence.
  - **Summary intent**: retains the previous "Summarize... Be concise" behaviour for analytical/conversational queries.
