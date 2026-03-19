# MedGemma 4B Implementation Design – MyWellWallet Health Wallet

This document describes a step-by-step design to implement **MedGemma 4B** (or equivalent) on-device in the MyWellWallet health wallet app, for iPhone and Android, using download-on-first-use and the existing RAG/query pipeline.

---

## 1. Goals and scope

- **Goal:** Run a specialized medical LLM (MedGemma 4B) on-device so that health queries and result formatting use real NLU/generation instead of only rule-based logic.
- **Scope:**
  - Model: MedGemma 4B instruction-tuned, quantized (Q4_K_M) in GGUF format (~2.5GB).
  - Platforms: Linux (Desktop), iOS (iPhone), and Android.
  - UX: Model **downloaded on first use** (not embedded in the app binary) to keep IPA/APK size acceptable and to comply with store policies.
  - Integration points: Query interpretation (optional), **result formatting** (primary), and future medical summarization.

---

## 2. Current state (as of March 2026)

- **GemmaModelService** exists: downloads a GGUF from a configurable URL, caches under app support directory, loads via **llamadart** (`LlamaEngine` + `LlamaBackend`), exposes `generate(prompt)` and `generateStream(prompt)`.
- **GemmaRAGService** already calls `GemmaModelService.instance.generate(prompt)` for result formatting when the model URL is set; otherwise it uses `LocalQueryService.formatAsMarkdown`.
- **AppConfig** points to `medgemma-4b-it-Q4_K_M.gguf` on Hugging Face.
- **Verified:** MedGemma 4B loads successfully on Linux using the CPU backend.

---

## 3. Step-by-step implementation plan

### Step 1: Model and hosting

1. **Choose exact model artifact**
   - Use **MedGemma 4B IT** (instruction-tuned) in GGUF (e.g. `medgemma-4b-it-Q4_K_M.gguf`).
   - Hosting: [unsloth/medgemma-4b-it-GGUF](https://huggingface.co/unsloth/medgemma-4b-it-GGUF) on Hugging Face.

2. **Memory Considerations**
   - MedGemma 4B Q4_K_M is ~2.5 GB.
   - Recommended RAM: 4GB+ for mobile devices.
   - For lower-end devices, the app should fallback to rule-based formatting if loading fails.

### Step 2: Download and storage

1. **GemmaModelService** handles download from `AppConfig.gemmaModelUrl`.
2. **Path:** `getApplicationSupportDirectory()/models/medgemma-4b-it-Q4_K_M.gguf`.
3. **Progress:** `downloadProgress` stream provides 0.0-1.0 progress updates.

### Step 3: Initialization

1. **Desktop (Linux/Windows/macOS):** Use CPU backend to avoid conflicts with Flutter rendering engine.
2. **Mobile (iOS/Android):** Use GPU acceleration (Metal/Vulkan) where available.
3. **Lazy Loading:** `ensureInitialized()` is called during app startup.

### Step 4: Prompt design for medical context

1. **System context**
   - MedGemma is a specialized medical model. The system prompt should reflect this:
     - "You are a specialized medical assistant. Provide clear, accurate summaries based on FHIR data."
     - "Always include a disclaimer: 'This is an AI summary for informational purposes only. Consult a healthcare professional for clinical advice.'"

2. **Result-formatting prompts**
   - Update `GemmaRAGService` to use MedGemma-specific prompts if needed.
   - Example: "Based on the following patient observations, summarize the recent health trends."

### Step 5: Future Enhancements

1. **Vision Integration:** MedGemma 4B is multimodal. Future support for `mmproj` files will allow interpreting scanned medical documents.
2. **Query Plan Generation:** Use MedGemma to translate natural language into structured FHIR search parameters.

---

## 4. Dependencies and references

- **llamadart:** [pub.dev/packages/llamadart](https://pub.dev/packages/llamadart) – GGUF loading and inference.
- **MedGemma:** [Google's MedGemma](https://huggingface.co/google/medgemma-4b-it) – Specialized medical model.
- **Unsloth GGUF:** [unsloth/medgemma-4b-it-GGUF](https://huggingface.co/unsloth/medgemma-4b-it-GGUF).

---

Once these steps are completed, the health wallet will leverage the power of a specialized 4B medical model running entirely on-device.
