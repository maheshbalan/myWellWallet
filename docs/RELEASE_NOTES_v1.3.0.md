# MyWellWallet v1.3.0 — Release notes

**Release date:** March 25, 2026  
**Version:** 1.3.0 (build 1)  
**Git tag:** `v1.3.0` (use this tag for the GitHub Release)

> **Note:** Earlier repository tags `v1.1.0` and `v1.2.0` point at older milestones. **v1.3.0** is the current release line for MedGemma 4B, Apple Health integration, and the stable authentication changes described below.

## Summary

This release stabilizes authentication and navigation, ships on-device **MedGemma** support with **background model download** and **memory-conscious inference settings**, and expands **Apple Health** integration (including **glucose** and related vitals) with documentation for EHR-oriented design. Glucose-related MedGemma answers are usable but may still need prompt/RAG fine-tuning in a follow-up.

---

## Highlights

### On-device MedGemma (local LLM)

- **llamadart** integration for a local **MedGemma 4B** GGUF workflow.
- **Background downloads** via `background_downloader` (initialized at app startup on iOS/Android) so large model transfers can continue reliably; extended timeouts and logging for multi-GB CDN pulls.
- **Memory and safety caps** on mobile: reduced context size, GPU layer limits, batch/micro-batch caps, bounded generation (`maxTokens`), and prompt length limits to lower peak RAM and reduce jetsam risk on phones.
- **Lazy / on-demand** model load path remains available through `GemmaModelService.ensureInitialized()` (also kicked from main init for early download start where configured).

### Apple Health and integrated health UI

- HealthKit-backed flows for **glucose**, heart rate, steps, blood pressure, and lab-oriented surfaces (where implemented in-app), aligned with the integrated health/EHR design direction documented in-repo.

### Authentication and routing

- **Stable login flow**: alignment between **GoRouter** (`isAuthenticated`) and in-memory user state; no redundant “null `currentUser` → force login” check that could fight the router after biometric/PIN success.
- **`AuthProvider.ensureCurrentUserLoaded()`** reloads the SQLite user row when it is missing after auth (race-safe path).
- **Login screen** waits for a loaded profile before navigating home; shows a clear message if the profile cannot be loaded.
- **Home screen** syncs authenticated session to DB once; if the user row is still missing after reload, performs a clean **logout** and sends the user to login (consistent state).

### Query, RAG, and user context

- **Query pipeline** wired to pass **`appUserId`** from the signed-in user into local query/RAG paths so retrieval and answers stay scoped to the correct profile.

### iOS platform

- Runner updates (e.g. **AppDelegate**, **Info.plist**, entitlements, pods) to support HealthKit, background execution/download behavior, and release-friendly builds on **physical devices** (use **Release** for device runs per project guidance).

### Documentation

- **MedGemma / MLX / memory** notes, **GEMMA integration**, **integrated health & EHR design**, **iOS device / simulator** troubleshooting (developer disk image, invalid signature), and **crash log** guidance.

### Schema and glossary assets

- Updates to **FHIR medical glossary** and **SQLite schema** documentation (including mirrored copies under `assets/docs/` where bundled for in-app or packaging use).

---

## Upgrade and install notes

- **Fresh install** is supported: uninstalling the app clears local DB, preferences, and on-device model files; users can re-register and re-download the model.
- **MedGemma** requires a configured model URL and sufficient storage; first run may take significant time on cellular—Wi-Fi is recommended.

---

## Known limitations / next steps

- **Glucose (and related) MedGemma responses** may need further **prompt engineering**, RAG chunking, or glossary/schema tuning for clinical precision; behavior is stable but not final.
- Dependency updates are available upstream; this release keeps current **pubspec** constraints for reproducibility.

---

## Technical stack (reference)

- Flutter, Provider, go_router  
- sqflite (local user + FHIR-related storage)  
- local_auth, Health (`health` package) on iOS  
- llamadart, background_downloader, http  

---

## Thanks

Thanks to everyone testing on real hardware; device-specific fixes in this cycle were driven by production-like runs on iPhone.
