# Gemma on iOS: Memory, Lazy Loading, and MLX Migration (Doctoral Research)

This document captures the strategy for running Gemma 2B efficiently on iPhone (including iPhone 15/17) without the app being killed for memory, and the path to using **Apple MLX** with **mlx_lm**-style lazy loading and memory caps.

---

## 1. Current State

- **Stack**: Flutter app uses **llamadart** (Dart package wrapping llama.cpp) with a **GGUF** Gemma 2B model (~1.2GB Q2_K). No MLX yet.
- **Problem**: Loading the model at startup (or in background immediately after launch) causes iOS to kill the Runner process: *"The app 'Runner' has been killed by the operating system because it is using too much memory."*
- **Immediate fix applied**: **Lazy load on first use** — the Gemma model is **not** loaded at app startup or during RAG init. It is loaded only when:
  - The user first triggers inference (e.g. sends a chat message that uses Gemma for interpretation or streaming), or
  - The user taps the Gemma status chip and chooses to initialize.
  So the app starts light; the phone initiates the model only when the user actually uses the AI feature.

---

## 2. Why MLX and What You Recommended

For a robust, research-grade setup on iPhone, the goal is to use **Apple’s MLX** with the same patterns used in successful on-device LLM apps:

1. **Lazy loading**: Load the model only when first needed (`lazy=True` in `mlx_lm.load`), not at startup.
2. **MLX memory limits**: Cap memory so MLX does not wire too much RAM (e.g. `mx.metal.set_memory_limit()` or in Swift `MLX.GPU.set(memoryLimit:)` / `MLX.GPU.set(cacheLimit:)`).
3. **KV cache cap**: Limit context length / KV cache (e.g. `--max-kv-size`) so memory does not grow unbounded in long conversations.
4. **4-bit quantization**: Use a 4-bit quantized Gemma (e.g. mlx-community Gemma-2B-4bit) to stay within mobile limits.
5. **Manual disposal**: Explicitly release native model references when not in use (Flutter does not auto-dispose native resources; MethodChannel / Swift side must set references to `nil` or dispose).
6. **Debugging**: Use Flutter DevTools Memory tab and Xcode Instruments (Allocations, Leaks) to find spikes and leaks.

The current app does **not** use MLX; it uses **llamadart** (GGUF/llama.cpp). To adopt MLX fully, we need a **native iOS (Swift) path** and a **Flutter bridge**.

---

## 3. Current Implementation: Lazy Load Only (llamadart)

Already done:

- **No** `ensureInitialized()` at app startup (`main.dart` does not start Gemma).
- **No** `ensureInitialized()` inside `GemmaRAGService.initialize()` (RAG only loads docs).
- **First use** triggers load: `GemmaRAGService.processQuery()` and `GemmaService.generateStreamingResponse()` each call `await gemma.ensureInitialized()` before using the model, so the first time the user sends a query (or the first time we have results to summarize with the model), the app loads Gemma then. No load until then.
- User can also trigger load explicitly by tapping the Gemma status on the home screen and choosing to initialize.

This keeps startup memory low. It does **not** add MLX-style memory caps or KV limits; those require the MLX-based path below.

---

## 4. Target: MLX-Based Stack on iOS

To align with your recommendations and with examples where Gemma 2B runs well on iPhone 15/17, the long-term approach is:

### 4.1 Use MLX Swift on iOS

- **Packages**: [mlx-swift](https://github.com/ml-explore/mlx-swift), [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) (MLXLLM, MLXLMCommon).
- **Model**: 4-bit Gemma from MLX community, e.g. `mlx-community/Gemma-2B-4bit` (load via Hub or local).
- **Lazy load**: Load the model only when first needed (e.g. first inference or first “Use AI” action), not in `application(_:didFinishLaunchingWithOptions:)`.
- **Memory limits** (Swift side):
  - `MLX.GPU.set(cacheLimit: 512 * 1024 * 1024)` (512 MB cache) or lower if needed.
  - `MLX.GPU.set(memoryLimit: value, relaxed: false)` where `value` is a safe cap (see [mlx-swift GPU memory](https://github.com/ml-explore/mlx-swift/issues/37)).
- **KV cache / context**: Use the model/generation config to set a maximum context length (or equivalent `max-kv-size`-style cap) so long chats do not grow memory unbounded.
- **Disposal**: When the user leaves the AI flow or the app goes to background, clear or release the model reference and optionally shrink the cache so the OS does not kill the app.

### 4.2 Flutter Bridge

- **Option A – Flutter plugin (MethodChannel)**  
  - iOS: Swift code that uses MLX Swift + MLXLMCommon to load (lazy), set memory limits, run inference, and stream tokens.  
  - Dart: `GemmaModelService` (or a new `MLXGemmaService`) calls the plugin to load, generate, generateStream, and dispose.  
  - No MLX from Dart directly; all MLX usage is in Swift.

- **Option B – FFI**  
  - Less common for MLX; MethodChannel is the usual approach for Flutter ↔ native LLM.

### 4.3 Android / Desktop

- Keep **llamadart** (or existing path) for Android and desktop.
- Use the **MLX plugin only on iOS** (or iOS + macOS if you want MLX on Mac too).

---

## 5. Checklist (Your Recommendations → Actions)

| Recommendation | Current (llamadart) | With MLX plugin (iOS) |
|----------------|---------------------|------------------------|
| Lazy load on first use | ✅ Done: no init at startup; first `generate`/user init loads model | ✅ Load in Swift only on first inference or explicit “load” from Flutter |
| Set hard memory limit | ❌ Not available in llamadart | ✅ `MLX.GPU.set(memoryLimit:)` / `set(cacheLimit:)` in Swift before load |
| Cap KV cache | ❌ Not exposed in current API | ✅ Model/generation config: max context / max-kv-size |
| 4-bit quantization | ✅ Q2_K GGUF (current); for MLX use 4-bit (e.g. Gemma-2B-4bit) | ✅ Use mlx-community 4-bit Gemma |
| lazy=True (mlx_lm.load) | N/A (different runtime) | ✅ Defer Swift `loadModel` until first use; no load at app launch |
| Manual disposal | ⚠️ Partial (engine dispose exists) | ✅ Plugin method “dispose” that nils model and optionally reduces cache |
| DevTools / Instruments | ✅ Use for leaks and spikes | ✅ Use for Dart vs native breakdown |

---

## 6. References (from your list and research)

- MLX Swift: [mlx-swift](https://github.com/ml-explore/mlx-swift), [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples).
- MLX memory on iOS: [Memory usage on iOS #37](https://github.com/ml-explore/mlx-swift/issues/37), [use memory limit API #13](https://github.com/ml-explore/mlx-swift-examples/pull/13), [GPU Memory/Cache Limit #66](https://github.com/ml-explore/mlx-swift-examples/issues/66).
- Integrating MLX in iOS apps: [Integrating Local LLMs into iOS Apps with MLX Swift](https://compiledthoughts.pages.dev/blog/integrating-mlx-local-llms-ios-apps).
- On-device RAG with Gemma 2B on iOS: [Part 2: On Device RAG system in IOS (SwiftUI) using Gemma 2B](https://medium.com/@malpureomkar5/part-2-on-device-rag-system-in-ios-swiftui-using-gemma-2b-for-llm-processing-cabcda923fd4).
- macOS kernel panic / memory: [mlx_lm.server causes macOS kernel panic (IOGPUMemory)](https://github.com/ml-explore/mlx-lm/issues/883).
- Flutter memory: DevTools Memory tab, Xcode Instruments (Allocations, Leaks), and the Flutter/iOS memory guides you referenced.

---

## 7. Next Steps (Research Roadmap)

1. **Short term**: Keep current lazy load (llamadart, no startup init). Test on device; if iOS still kills the app at first use, reduce concurrent load (e.g. ensure only one heavy operation at a time) and consider a smaller quantization for the GGUF path.
2. **Medium term**: Implement an **iOS Flutter plugin** that uses **mlx-swift** and **MLXLMCommon**:
   - Lazy load (first use or explicit “load”).
   - Set `MLX.GPU.set(cacheLimit:)` and optionally `memoryLimit` before load.
   - Use 4-bit Gemma (e.g. mlx-community/Gemma-2B-4bit).
   - Cap KV/context in generation config.
   - Expose load / generate / stream / dispose to Dart via MethodChannel.
3. **Integration**: From Dart, on iOS only, use this plugin instead of llamadart for Gemma; keep existing RAG and UI flow, swapping only the backend used for generation.
4. **Evaluation**: Use DevTools and Instruments to confirm memory stays under the OS limit and that disposal and cache limits behave as expected.

This keeps your doctoral work aligned with best practices (lazy load, memory caps, 4-bit, disposal) and with the MLX-based approach used in successful on-device Gemma 2B demos on iPhone.
