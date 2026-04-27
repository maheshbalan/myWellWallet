# MyWellWallet

Flutter app for personal health data: **MedGemma** runs on the phone, FHIR comes in over **MCP**, and **Apple Health** adds day-to-day readings next to clinic data.

[![Flutter](https://img.shields.io/badge/Flutter-3.8+-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.8+-0175C2?logo=dart)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## What we are building

We started with small **Gemma**-style models for local inference. The app now targets **MedGemma** (a clinical Gemma variant) so inference can stay **on the device**.

**Privacy.** Prompts, FHIR JSON, and Apple Health-backed rows can stay on the phone when you use the full local path. You do not need a cloud LLM for that mode.

**Why local on a phone.** Phones sit idle a lot of the time. The app only does heavy work when you use it, so it can use spare CPU/GPU without paying for a server per user.

The phone stores **EHR-style FHIR** (from your MCP server) and **Apple Health** metrics in **SQLite** so queries and RAG can use both clinic records and home or wearable data.

---

## Apple Health and the FHIR server

**Apple Health (iOS).** The app reads HealthKit data such as glucose, heart rate, steps, blood pressure, and some lab-style rows when the OS provides them. Everything is written to local SQLite. See `docs/SQLITE_SCHEMA.md` and `docs/INTEGRATED_HEALTH_EHR_DESIGN.md` for tables and how EHR and Apple data fit together.

**MCP and FHIR.** The app includes an **MCP (Model Context Protocol) client** that talks to an **MCP FHIR server** built for this project. The server exposes FHIR resources (`Patient`, `Observation`, bundles, etc.) as MCP tools. The client pulls data, stores it in SQLite (`fhir_patients`, `fhir_resources`, `fetch_summaries`), and feeds it into query and RAG code.

**Two paths into SQLite.**

- FHIR from the server: MCP sync → SQLite.
- Apple Health: HealthKit → app service → SQLite (`health_*` tables, keyed by app user id).

`docs/INTEGRATED_HEALTH_EHR_DESIGN.md` explains how we merge or tag EHR JSON and Apple-derived facts so the model can tell chart data from device data.

---

## How the on-device model works

1. **Weights.** MedGemma 4B is shipped as a **GGUF** file. The download URL is in `AppConfig.gemmaModelUrl` inside `lib/config/app_config.dart`. The file is large and is not stored in git.

2. **Download.** On iOS and Android the app starts **`background_downloader`** at launch so the GGUF can download in the background with sensible timeouts. See `lib/main.dart` and `lib/services/gemma_model_service.dart`.

3. **Load and run.** **`llamadart`** loads the GGUF into a **`LlamaEngine`**. We cap context size, GPU layers, batch sizes, and output length so phones do not run out of memory. Details: `docs/MEDGEMMA_AND_MEMORY_CAPS.md`.

4. **Queries.** **`GemmaModelService`** handles download and load. **`GemmaRAGService`** and **`LocalQueryService`** pull text from SQLite (FHIR plus optional merged Apple Health) for retrieval-augmented prompts.

5. **Home screen.** You type or dictate questions; **`QueryProvider`** ties requests to the current user (`appUserId`) and FHIR patient id where applicable.

```text
┌──────────────────┐     ┌─────────────────────┐
│ MCP FHIR server  │     │ Apple HealthKit     │
└────────┬─────────┘     └──────────┬──────────┘
         │ MCP client                │ Health sync
         ▼                           ▼
┌─────────────────────────────────────────────────┐
│ SQLite: fhir_* + health_* + users               │
└────────────────────────┬────────────────────────┘
                         │ LocalQueryService / RAG
                         ▼
┌─────────────────────────────────────────────────┐
│ MedGemma (llamadart) on the phone                 │
└─────────────────────────────────────────────────┘
```

**Test database and Dify.** To copy this SQLite onto a simulator or phone, or to export CSV/Markdown for Dify, read `docs/DATABASE_FIXTURE_TESTING_AND_DIFY.md`.

---

## Where the code lives

| Topic | Paths |
|--------|--------|
| MCP client, routing, state | `lib/main.dart`, `lib/services/mcp_client.dart`, `lib/providers/` |
| MedGemma, download, memory limits | `lib/services/gemma_model_service.dart`, `docs/MEDGEMMA_AND_MEMORY_CAPS.md` |
| Apple Health → SQLite | `lib/services/apple_health_service.dart`, `lib/services/database_service.dart` |
| EHR + Apple design | `docs/INTEGRATED_HEALTH_EHR_DESIGN.md` |
| Server URL and model URL | `lib/config/app_config.dart` |

---

## Getting started

You need Flutter 3.8+, Dart 3.8+, Xcode for iOS, and the Android SDK for Android.

```bash
git clone https://github.com/maheshbalan/myWellWallet.git
cd myWellWallet
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter pub run flutter_launcher_icons
flutter run
```

**Physical iPhone.** Use `flutter run --release` when running with the native ML stack; see `docs/IOS_DEBUG_CRASH.md` if debug builds crash.

**Apple Health.** See `docs/APPLE_HEALTH_SETUP.md` (HealthKit, Profile → Apple Health, sync interval).

**MCP base URL.** Edit `mcpBaseUrl` in `lib/config/app_config.dart`.

---

## Security and privacy

- MCP traffic should use **TLS**.
- If MedGemma runs fully on-device, that path does not require a cloud LLM.
- FHIR and Apple Health rows live in **SQLite** on the device first.
- The app is a **client** of your MCP FHIR server; access rules live on the server side.

---

## Research next steps

### 1. FLAI and federated learning

We want the wallet to join a **federated learning** setup called **FLAI**, developed with **Eli Yune** at **Balkeum Labs**. Devices would send updates such as gradients or summaries instead of sending raw PHI, which matches the on-device privacy goal.

Presented at **ICCE 2026** (44th IEEE International Conference on Consumer Electronics), Dubai, February 2026. [Conference site](https://icce.org/2026/).

**Paper (PDF):** [FLAI, IEEE ICCE authored copy (Dropbox)](https://www.dropbox.com/scl/fi/zdxdtv20jw1gq1kykepqt/FLAI_ICCE_authored_251029.pdf?rlkey=z1l0hzngfajch7sxje1il7tp3&e=2&st=dfs6zmg5&dl=0)

---

### 2. Federated LoRA for local models

We are also looking at **federated LoRA** (low-rank adapters) for models like MedGemma. The full weights stay fixed; small adapter matrices are trained or combined across participants. That cuts upload size versus full-model federated learning and still fits a local GGUF plus adapter layout on the phone.

A paper on this topic has been **submitted to BCCA, Barcelona, November 2026**.

---

### 3. Harness work (summer 2026)

Planned work includes a **harness** around the local model:

- A **knowledge graph** for diseases, drugs, guideline snippets, and patient facts, used for lookup next to the neural model.
- A **rules layer** that checks model output against stored protocols (paths, contraindications, numeric bands where we encode them). This is for research demos only; it is not medical advice.
- **Per-condition configs** (for example diabetes, heart disease, cancer) that turn on different graph slices, rules, and RAG sources so one app build can focus the harness without splitting the whole codebase.

The idea is to pair **neural output** with **explicit clinical structure** on top of the current SQLite + FHIR + Apple Health stack.

---

## Multi–local-LLM evaluation (CGU IST 345)

A separate **class project** (team: Mahesh Balan, Yashas Basavaraj Mahesh, Prajwal Vinod Naik, Brandon Medina) compares several **on-device** models (Gemma 3, Phi-3, MedGemma tiers) using **Dify** as the evaluation harness, focused on **Type 2 diabetes** scenarios and synthetic **FHIR + RWE** data. It does not replace the main app; it lives under:

**`projects/local-llm-evaluation/`** — proposal summary, Dify checklists, eval test-set layout, model matrix, and results layout.

---

## Contributing, license, author

Pull requests welcome. Please run `flutter analyze` before you submit.

- License: [MIT](LICENSE)
- Author: Mahesh Balan — [@maheshbalan](https://github.com/maheshbalan)

---

## Thanks

Thanks to the Flutter and Dart teams, the FHIR community, the **llamadart** project and open medical model publishers, and co-authors and partners on federated learning and mobile health work.

---

## Issues

[github.com/maheshbalan/myWellWallet/issues](https://github.com/maheshbalan/myWellWallet/issues)
