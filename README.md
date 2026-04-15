# MyWellWallet

**Personal health intelligence with on-device MedGemma, FHIR over MCP, and Apple Health–derived real-world evidence**

[![Flutter](https://img.shields.io/badge/Flutter-3.8+-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.8+-0175C2?logo=dart)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Research motivation and design thesis

The project originally explored **Google Gemma**–class models for local inference; the stack now targets **MedGemma** (a clinically oriented Gemma derivative) for **on-device** use. The central design bet is **local LLM execution**:

1. **Absolute privacy** — Sensitive prompts, FHIR payloads, and Apple Health–linked context can stay on the handset. No cloud inference is required for the core assistant path when the model is fully local.
2. **Idle compute at planetary scale** — Billions of smartphones spend large fractions of time **idle or lightly loaded**. A wallet-shaped agent that runs **only when the user engages** can exploit **spare CPU/GPU/NPU cycles** for inference and RAG prep without provisioning a datacenter for every user.

Together, **local MedGemma + local SQLite (EHR + device metrics)** supports a research agenda around **privacy-preserving, patient-centric clinical AI** grounded in **authoritative EHR data** and **real-world evidence (RWE)** from consumer wearables and phone-integrated health platforms.

---

## Real-world evidence and EHR fusion

### Apple Health (iOS / HealthKit)

On supported devices, the app integrates **Apple Health** to ingest **RWE-class** streams—e.g. continuous glucose–style metrics, heart rate, steps, blood pressure, and structured lab-oriented rows where available. These are **persisted locally** (see `docs/SQLITE_SCHEMA.md` and `docs/INTEGRATED_HEALTH_EHR_DESIGN.md`) alongside server-backed FHIR, so analytics and LLM context can **contrast clinic-recorded care with day-to-day physiology** (activity, home-range vitals, longitudinal device trends).

### MCP client and custom MCP FHIR server

The app ships an **MCP (Model Context Protocol) client** that talks to an **MCP FHIR server** developed for this line of work. That server exposes FHIR resources (e.g. `Patient`, `Observation`, bundles) through MCP tools so the Flutter client can **fetch, cache, and reason** over **EHR-aligned** data. In the architecture:

- **EHR / Medplum-style FHIR** flows: **MCP → sync → SQLite** (`fhir_patients`, `fhir_resources`, `fetch_summaries`).
- **RWE** flows: **HealthKit → Apple Health service → SQLite** (`health_*` tables keyed by app user).

The **integrated clinical layer** (see `docs/INTEGRATED_HEALTH_EHR_DESIGN.md`) describes how query and RAG paths can **merge** EHR-native JSON with **FHIR-shaped** projections from Apple-sourced rows, with **explicit provenance** so answers can distinguish chart data from device-derived evidence.

---

## How a local LLM runs on the phone (architecture)

At a high level:

1. **Model artifact** — A **MedGemma 4B** GGUF is configured via `AppConfig.gemmaModelUrl` (`lib/config/app_config.dart`). The file is large (~multi-GB); it is not bundled in the repo.
2. **Download** — **`background_downloader`** is initialized at startup on iOS/Android so the model can be retrieved **reliably in the background** (timeouts and progress handling tuned for CDN behavior). See `lib/main.dart` and `lib/services/gemma_model_service.dart`.
3. **Runtime** — **`llamadart`** loads the GGUF into a **`LlamaEngine`** with **platform-specific memory caps** (reduced context, GPU layer limits, batch sizes, capped decode length, prompt truncation) to reduce peak RAM and OS jetsam risk on phones—documented in `docs/MEDGEMMA_AND_MEMORY_CAPS.md`.
4. **Orchestration** — **`GemmaModelService`** ensures download + load; **`GemmaRAGService`** / **`LocalQueryService`** combine **MCP-backed FHIR context**, **SQLite**, and optional **merged Apple Health** views for retrieval-augmented prompting.
5. **UI** — The **Home** surface supports conversational queries (including speech-to-text) that go through the **query provider** pipeline with **patient and user scoping** (`appUserId`, FHIR `patient_id`).

```text
┌──────────────────┐     ┌─────────────────────┐
│ MCP FHIR Server  │     │ Apple HealthKit     │
│ (tools / FHIR)   │     │ (RWE streams)       │
└────────┬─────────┘     └──────────┬──────────┘
         │ MCP client                │ Health plugin + sync
         ▼                           ▼
┌─────────────────────────────────────────────────┐
│ SQLite: fhir_* + health_* + users               │
└────────────────────────┬────────────────────────┘
                         │ LocalQueryService / RAG
                         ▼
┌─────────────────────────────────────────────────┐
│ MedGemma (llamadart) on-device                   │
│ GGUF download → load → generate                  │
└─────────────────────────────────────────────────┘
```

For **fixture databases**, **Dify exports**, and **device seeding**, see `docs/DATABASE_FIXTURE_TESTING_AND_DIFY.md`.

---

## Repository map (engineering)

| Area | Location |
|------|-----------|
| MCP client, routing, providers | `lib/main.dart`, `lib/services/mcp_client.dart`, `lib/providers/` |
| MedGemma + download + caps | `lib/services/gemma_model_service.dart`, `docs/MEDGEMMA_AND_MEMORY_CAPS.md` |
| Apple Health → SQLite | `lib/services/apple_health_service.dart`, `lib/services/database_service.dart` |
| EHR + RWE integration design | `docs/INTEGRATED_HEALTH_EHR_DESIGN.md` |
| App configuration | `lib/config/app_config.dart` |

---

## Getting started

**Prerequisites:** Flutter 3.8+, Dart 3.8+, Xcode (iOS), Android SDK (Android).

```bash
git clone https://github.com/maheshbalan/myWellWallet.git
cd myWellWallet
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter pub run flutter_launcher_icons
flutter run
```

**iOS physical device:** For builds that load native ML stacks, prefer **`flutter run --release`** on device per project notes (see `docs/IOS_DEBUG_CRASH.md` if applicable).

**Apple Health:** `docs/APPLE_HEALTH_SETUP.md` — HealthKit capability, Profile → Apple Health connection, sync interval.

**MCP server URL:** Set in `lib/config/app_config.dart` (`mcpBaseUrl`).

---

## Security and privacy (research framing)

- **TLS** for MCP traffic; **no cloud requirement** for the local model path when MedGemma is fully on-device.
- **Local-first persistence** for synced FHIR and Apple Health rows (SQLite).
- **Session and tool semantics** are enforced by the MCP FHIR server design; the wallet remains a **client** that can be audited for data minimization.

---

## Next steps (research roadmap)

### 1. Federated learning: FLAI (wallet as participant)

The wallet is intended to participate in a **federated learning protocol (FLAI)** developed as part of ongoing research with **Eli Yune** (**Balkeum Labs**). The goal is to let many devices contribute **privacy-preserving gradient- or statistic-level updates** without centralizing raw PHI—aligning with the same privacy story as on-device inference.

**Publication:** A joint paper on this direction was presented at the **44th IEEE International Conference on Consumer Electronics (ICCE 2026)**, **Dubai, UAE, February 2026** (see [icce.org](https://icce.org/2026/) for the official program).

**Paper (PDF):** [FLAI — IEEE ICCE authored version (Dropbox)](https://www.dropbox.com/scl/fi/zdxdtv20jw1gq1kykepqt/FLAI_ICCE_authored_251029.pdf?rlkey=z1l0hzngfajch7sxje1il7tp3&e=2&st=dfs6zmg5&dl=0)

---

### 2. Decentralized federated LoRA fine-tuning for local LLMs

A complementary research thread targets **decentralized federated LoRA (Low-Rank Adaptation) fine-tuning** for **local LLMs** such as the MedGemma stack used here. In brief:

- **Personalization without data pooling** — Small adapter matrices are trained or aggregated across participants so the **base model stays fixed** while **low-rank updates** capture cohort- or site-specific structure.
- **Communication efficiency** — LoRA reduces the volume of updates compared to full-model federated learning, which matters on **mobile uplinks**.
- **Alignment with local execution** — Adapters can be deployed alongside the GGUF workflow so the phone keeps **inference local** while still benefiting from **federated adaptation**.

A paper describing this line of work has been **submitted to the BCCA conference in Barcelona (November 2026)**.

---

### 3. Harness engineering (summer 2026)

Summer **2026** work will emphasize **harness engineering** to **ground** the local model in a **structured knowledge graph (KG)**:

- **Knowledge graph** — Encode disease entities, medications, guidelines nodes, and patient-specific facts in a form suitable for **symbolic** traversal and **retrieval** alongside neural generation.
- **Symbolic rules engine** — Cross-check model outputs against **established, disease-specific medical protocols** (pathways, contraindications, dosing bands where encoded as rules—not a substitute for licensed care, but a **safety and consistency** layer for research prototypes).
- **Per–chronic-condition harnesses** — Pluggable **harness configurations** (e.g. **diabetes**, **heart disease**, **cancer**) that select **which subgraphs of the KG are active**, which **rules** fire, and which **RAG corpora** (EHR + RWE) are prioritized—so the same MedGemma runtime can be **specialized** without forking the entire app for each disease area.

This connects the current **SQLite + FHIR + Apple Health** foundation to a **neuro-symbolic** research agenda: **neural generation** bounded by **explicit clinical structure**.

---

## Contributing, license, author

Contributions are welcome via fork and pull request. Run `flutter analyze` before submitting changes.

- **License:** [MIT](LICENSE)
- **Author:** Mahesh Balan — [@maheshbalan](https://github.com/maheshbalan)

---

## Acknowledgments

- Flutter and Dart teams; FHIR community; **llamadart** and open medically oriented model releases; co-authors and collaborators on federated learning and mobile health research.

---

## Support

Open an issue: [github.com/maheshbalan/myWellWallet/issues](https://github.com/maheshbalan/myWellWallet/issues).
