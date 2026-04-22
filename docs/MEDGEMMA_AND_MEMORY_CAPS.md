# MedGemma 4B Integration and Memory Caps

This document summarizes the **MedGemma 4B** work merged from the main branch and the **explicit memory caps** added in `GemmaModelService` to reduce iOS jetsam risk and keep peak RAM predictable.

---

## 1. MedGemma 4B (latest product changes)

### 1.1 Model and configuration

| Item | Value |
|------|--------|
| **Model** | MedGemma 4B IT (instruction-tuned), medical domain |
| **Format** | GGUF, **Q4_K_M** quantization (~2.5 GB on disk) |
| **Source** | [unsloth/medgemma-4b-it-GGUF](https://huggingface.co/unsloth/medgemma-4b-it-GGUF) |
| **Runtime** | `llamadart` (llama.cpp-backed), `LlamaEngine` + `LlamaBackend` |

**Code:** `lib/config/app_config.dart`

- `gemmaModelUrl` → `medgemma-4b-it-Q4_K_M.gguf` resolve URL on Hugging Face  
- `gemmaModelFileName` → `medgemma-4b-it-Q4_K_M.gguf`  
- Cached under `getApplicationSupportDirectory()/models/`

**Validation:** `GemmaModelService` treats a local file as valid if size **> 1.5 GB** (so partial downloads are rejected).

### 1.2 RAG and when MedGemma runs

**File:** `lib/services/gemma_rag_service.dart`

1. **Rule-based interpretation first** — fast, deterministic mapping for common queries.  
2. **MedGemma only if** the rule path returns `null` or `needsClarification == true` **and** `GemmaModelService.instance.isReady`.  
3. **Query-plan prompt** — FHIR-oriented JSON plan with `subject` vs `patient` guidance; **15 s timeout** on `generate()`.  
4. **JSON parsing** — tolerates incomplete JSON by prefixing `{"needsClarification":` when the model omits the opening brace.  
5. **`_isAmbiguous`** returns `false` so ambiguity is driven by rules/model, not a short-query heuristic.  
6. **Formatting** — `_formatResultsWithGemma` can call `generate()` for markdown-style summaries when configured.

### 1.3 Chat / streaming

**File:** `lib/services/gemma_service.dart`

- Streaming responses with **90 s** stream timeout.  
- Prompts for **no data**, **empty summary**, and **raw FHIR** payloads.  
- If the model is not ready: user-facing message about **~2.5 GB** model and retry.

### 1.4 Query orchestration and MCP

**Files:** `lib/providers/query_provider.dart`, `lib/services/mcp_client.dart`

- Extra logging through the RAG → execute → MCP fallback path.  
- MCP client improvements for **session / retry** behavior (see `UPDATE.md`).

### 1.5 App lifecycle

**File:** `lib/main.dart`

- After RAG init, **`unawaited(GemmaModelService.instance.ensureInitialized())`** warms the model in the **background** so the UI is usable while download/load proceeds.

### 1.6 UI

**Files:** `lib/screens/home_screen.dart`, `lib/widgets/conversation_message.dart`

- “Thinking” indicator in chat, bolt status tied to readiness, improved markdown for medical text.

### 1.7 Reference docs and tests

- `UPDATE.md` — release narrative (March 19, 2026).  
- `docs/MEDGEMMA_4B_IMPLEMENTATION_DESIGN.md` — design notes.  
- `test/ehr_rag_medgemma_test.dart` — E2E-style verification (environment-dependent).

---

## 2. Memory caps (implementation detail)

MLX-style `set_memory_limit()` is **not** available in Dart; caps are applied through **llamadart** `ModelParams` (load/context), **`GenerationParams`** (decode length), **prompt truncation**, and an **iOS entitlement**.

### 2.1 `ModelParams` (load / KV context)

**File:** `lib/services/gemma_model_service.dart` — `_modelParamsForPlatform()`

| Platform | `contextSize` | `gpuLayers` | `batchSize` | `microBatchSize` |
|----------|---------------|-------------|-------------|------------------|
| **iOS** | 2048 | 20 | 512 | 256 |
| **Android** | 3072 | 32 | 768 | 384 |
| **Desktop** | 4096 | 0 (CPU) | 1024 | 512 |

**Intent:** Smaller **n_ctx** reduces KV cache RAM; fewer **GPU layers** on phones lowers Metal/Vulkan working set; smaller **batch / micro-batch** lowers peak activation memory during prefill/decode.

### 2.2 `GenerationParams` (max new tokens)

**Same file** — `_generationParamsForPlatform()`

| Platform | `maxTokens` | Notes |
|----------|-------------|--------|
| **iOS** | 640 | `temp` 0.7, `topP` 0.9 |
| **Android** | 1024 | `temp` 0.7, `topP` 0.9 |
| **Desktop** | 2048 | `temp` 0.8, `topP` 0.9 |

Applied to every `LlamaEngine.generate()` / streamed `generate()` call from this service.

### 2.3 Prompt length cap

| Platform | Max characters |
|----------|----------------|
| **iOS** | 2000 |
| **Android** | 3500 |
| **Desktop** | 200000 (practical “no cap”) |

Long prompts are truncated **before** inference; a line is written to `LogService`.

### 2.4 iOS: increased memory entitlement

**File:** `ios/Runner/Runner.entitlements`

- `com.apple.developer.kernel.increased-memory-limit` = **true**

This requests a **higher jetsam ceiling** from the system for memory-heavy on-device inference. The capability must be valid for your **Apple Developer** provisioning profile when distributing; local dev signing usually works if the team has the entitlement enabled.

### 2.5 Logging

On load, the service logs the active caps, for example:

`Memory-capped ModelParams: contextSize=..., gpuLayers=..., batchSize=..., microBatchSize=...`

---

## 3. Tuning after field testing

If responses are **too short** on iPhone: raise `maxTokens` (iOS) slightly or `contextSize` (watch RAM).  
If the app is still **killed for memory**: lower `contextSize`, `gpuLayers`, or `maxTokens` on iOS first.

All tunables live in **`lib/services/gemma_model_service.dart`** (`_modelParamsForPlatform`, `_generationParamsForPlatform`, `_iosMaxPromptChars` / `_androidMaxPromptChars`).

---

## 4. After your testing: check in to GitHub

When you are satisfied with behavior on device:

```bash
cd /Users/veenamahesh/myWellWallet
git status
git add lib/services/gemma_model_service.dart ios/Runner/Runner.entitlements docs/MEDGEMMA_AND_MEMORY_CAPS.md
# add any other files you intentionally changed
git commit -m "MedGemma: document integration and add llamadart memory caps + iOS entitlement"
git push origin main
```

Adjust the commit message and file list to match your final diff.

---

## 5. Related documents

- `docs/MEDGEMMA_4B_IMPLEMENTATION_DESIGN.md` — original MedGemma design  
- `docs/GEMMA_MLX_AND_MEMORY.md` — future MLX / Apple-native path  
- `UPDATE.md` — user-facing release notes for the MedGemma drop  
