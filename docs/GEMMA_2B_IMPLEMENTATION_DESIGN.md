# Gemma 2B Implementation Design – MyWellWallet Health Wallet

This document describes a step-by-step design to implement **Gemma 2 2B** (or equivalent) on-device in the MyWellWallet health wallet app, for iPhone and Android, using download-on-first-use and the existing RAG/query pipeline.

---

## 1. Goals and scope

- **Goal:** Run a small, instruction-tuned LLM (Gemma 2 2B) on-device so that health queries and result formatting use real NLU/generation instead of only rule-based logic.
- **Scope:**
  - Model: Gemma 2 2B instruction-tuned, quantized (e.g. Q2_K or Q4_K) in GGUF format.
  - Platforms: iOS (iPhone) and Android.
  - UX: Model **downloaded on first use** (not embedded in the app binary) to keep IPA/APK size acceptable and to comply with store policies.
  - Integration points: Query interpretation (optional), **result formatting** (primary), and any future “explain this result” or follow-up generation.

---

## 2. Current state (as of Release 1.2)

- **GemmaModelService** exists: downloads a GGUF from a configurable URL, caches under app support directory, loads via **llamadart** (`LlamaEngine` + `LlamaBackend`), exposes `generate(prompt)` and `generateStream(prompt)`.
- **GemmaRAGService** already calls `GemmaModelService.instance.generate(prompt)` for result formatting when the model URL is set; otherwise it uses `LocalQueryService.formatAsMarkdown`.
- **llamadart** is in `pubspec.yaml`; iOS/Android builds are unchanged except for the plugin’s native runtime.
- **Gap:** `_modelUrl` in `GemmaModelService` is empty; no first-run download UI; no progress or error surfacing; no explicit “Gemma 2B for health wallet” prompt design or safety constraints.

---

## 3. Step-by-step implementation plan

### Step 1: Model and hosting

1. **Choose exact model artifact**
   - Use **Gemma 2 2B IT** (instruction-tuned) in GGUF (e.g. `gemma-2-2b-it-Q2_K.gguf` or `Q4_K_M` for better quality, larger file).
   - Ensure license permits use in a mobile health app (Google Gemma terms).

2. **Host the GGUF**
   - Host the file on a CDN or blob store (e.g. your own server, Hugging Face, or GCS/S3 with signed URLs).
   - Use HTTPS; support range requests if you want resumable downloads later.
   - Document the URL and update `GemmaModelService._modelUrl` (or move to a config asset / remote config).

3. **Optional: Multiple quantizations**
   - Offer Q2_K (smaller) vs Q4_K (better quality) via a setting or build flavor; `_modelUrl` (or config) points to the chosen file.

### Step 2: Download and storage (already partially done)

1. **Keep download in GemmaModelService**
   - Current logic: check app support `models/` for the GGUF; if missing, download from `_modelUrl` and save.
   - Ensure path and filename match what `LlamaEngine.loadModel(path)` expects.

2. **Improve download UX**
   - Add a **download progress callback** (e.g. `void Function(int bytes, int? total)`) and/or a **stream** of progress (0.0–1.0) so the UI can show a progress bar.
   - On first use of a feature that needs the model, call `ensureInitialized()`; if the model is not present, trigger download and show a full-screen or modal: “Downloading Gemma 2B (~XXX MB). Wi‑Fi recommended.”
   - Handle errors: network failure, disk full, invalid file. Offer “Retry” and optionally “Use without AI” (fallback to rule-based).

3. **Storage and lifecycle**
   - Store only in app-private storage (already the case with `getApplicationSupportDirectory()`).
   - On app update, reuse the same path so the cached model is kept; optionally add a version or hash in the filename to support future model updates.

### Step 3: Initialization and threading

1. **When to load the model**
   - **Lazy:** On first call to `generate()` or `generateStream()` (current behavior via `ensureInitialized()`).
   - **Eager (optional):** After download completes, show “Ready” and optionally preload the model in the background so the first query is fast.

2. **Threading / isolates**
   - llamadart may run inference on a background thread or isolate; follow the package’s guidance to avoid blocking the UI. If the API is synchronous on the main isolate, consider spawning an isolate for `generate()` and passing results back.

3. **Memory**
   - Gemma 2B Q2_K is ~700–900 MB in memory; Q4_K ~1.2–1.5 GB. Ensure devices with limited RAM can still run the app (optional: show a “Low memory” message and skip model load on very low-end devices).

### Step 4: Prompt design for health wallet

1. **System context**
   - Give the model a short system prompt that it is a **health assistant** for the MyWellWallet app, and that it must:
     - Respond only about the user’s health data or the provided context.
     - Not give clinical advice (suggest “talk to your doctor” for interpretation).
     - Prefer concise, readable answers (e.g. markdown where helpful).

2. **Result-formatting prompts (current use case)**
   - `_buildFormattingPrompt` in GemmaRAGService already passes resource type, count, and JSON; add explicit instructions:
     - “Format the following FHIR resources as clear markdown. Use headings, lists, and human-readable dates. Do not invent values. If a reference range exists, show it next to the value.”
   - Optionally prepend 1–2 example lines (few-shot) for consistency.

3. **Query interpretation (future)**
   - If you later use Gemma for turning natural language into a query plan, design a structured prompt (and optionally JSON mode or a small parser) so the model outputs a fixed schema (resource type, filters, sort) that the app can execute safely.

4. **Safety and PII**
   - Prompts may contain PHI (patient data). The model runs on-device; no data is sent to a server. Document this in the app’s privacy policy and in-code comments.

### Step 5: UI integration

1. **First-run / download screen**
   - When the user first triggers a feature that needs Gemma (e.g. asks a question that goes through RAG formatting), check `GemmaModelService.isConfigured` and `GemmaModelService.isReady`.
   - If configured but not ready, call `ensureInitialized()`; if this triggers download, show a dedicated screen or bottom sheet: title “Download AI model”, progress bar, “Wi‑Fi recommended”, and “Cancel” (cancel leaves model not ready; next time the flow can offer again).

2. **Progress and errors**
   - Surface download progress (bytes or %) from Step 2.
   - On failure (network, disk, corrupt file), show a clear message and “Retry” or “Continue without AI”.

3. **Streaming (optional)**
   - For result formatting, current code uses `generate()` (full string). If you switch to `generateStream()`, you can stream tokens into the conversation UI so the user sees text appearing incrementally.

4. **Settings**
   - In Profile or Settings: “AI model” section with:
     - Status: “Downloaded” / “Not downloaded” / “Downloading”.
     - Button: “Download model” (if not present) or “Delete model” (to free space and re-download later).
     - Optional: choice of quantization (if you support multiple URLs).

### Step 6: Testing and validation

1. **Unit / widget tests**
   - Mock `GemmaModelService` (e.g. return a fixed string from `generate`) and test that GemmaRAGService and the UI behave when the model is “available” vs “unavailable”.

2. **Integration**
   - On a real device, set `_modelUrl` to a valid GGUF URL, run through download once, then run several queries and confirm:
     - Formatting uses model output.
     - Fallback to rule-based formatting when the model is not configured or fails.

3. **Performance**
   - Measure time to first token and time to full response on a mid-range iPhone and Android device; document and, if needed, add a “Generating…” indicator with a timeout.

4. **Edge cases**
   - No network on first use; interrupt download; disk full; invalid or truncated GGUF. Handle gracefully and leave the app usable without the model.

### Step 7: Documentation and release

1. **In-repo docs**
   - Update README or a dedicated “AI model” doc: how to set the model URL, how download works, storage location, and that the model runs fully on-device.

2. **App Store / Play Store**
   - In the app description or release notes, mention optional on-device AI (Gemma 2B) for health summaries; clarify that health data stays on device.

3. **Privacy / compliance**
   - Ensure privacy policy and any health-compliance docs (e.g. HIPAA if applicable) state that AI processing is on-device and no health data is sent to external servers for the model.

---

## 4. Dependencies and references

- **llamadart:** [pub.dev/packages/llamadart](https://pub.dev/packages/llamadart) – GGUF loading and inference; supports iOS and Android.
- **Gemma 2:** [Google’s Gemma 2](https://ai.google.dev/gemma) – Base models; use an instruction-tuned 2B variant in GGUF form (e.g. from Hugging Face or community quantizations).
- **GGUF:** Standard format for llama.cpp–compatible models; Gemma 2 2B quantized models are available in this format for iPhone and Android use.

---

## 5. Summary checklist

- [ ] Choose and host Gemma 2 2B GGUF (Q2_K or Q4_K).
- [ ] Set `_modelUrl` (or config) and optionally support multiple quantizations.
- [ ] Add download progress reporting and first-run download UI (progress bar, Wi‑Fi note, Retry/Cancel).
- [ ] Ensure model load runs off the UI thread/isolate if required by llamadart.
- [ ] Define health-wallet system prompt and formatting prompt text; add safety and “no clinical advice” instructions.
- [ ] Optional: use `generateStream()` for streaming into the conversation UI.
- [ ] Add Settings/Profile entry for model status and Download/Delete.
- [ ] Test download, inference, fallback, and error paths on iOS and Android.
- [ ] Update README and privacy/compliance docs.

Once these steps are done, the health wallet will use Gemma 2B on-device for result formatting (and optionally for query interpretation) with a clear, safe, and store-friendly UX.
