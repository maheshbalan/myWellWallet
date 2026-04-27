# Candidate on-device models

| Tier | RAM envelope | Model | ~Size (proposal) |
|------|---------------|-------|------------------|
| 1 (low) | ≤ ~4 GB | Gemma 3 1B | ~529 MB |
| 1 (low) | ≤ ~4 GB | Phi-3 Mini 3.8B | ~2 GB |
| 2 (high) | 8–16 GB | MedGemma 1.5 4B | ~2.5 GB |
| 2 (high) | 8–16 GB | Gemma 3 4B | ~2.5 GB |

**Rule:** On-device or self-hosted only — **no** cloud chat API on real PHI.

**App alignment:** The shipping app in this repo may standardize on **MedGemma 4B** (`lib/services/gemma_model_service.dart`); this class project may compare **1.5 / 3 / 4B** variants and **Gemma/Phi** as listed — update the table if you swap checkpoints.

**Hardware targets (proposal):** e.g. iPhone SE 3 (low) vs iPhone 16 Pro (high), or emulators for first cut.

**Results:** put latency/accuracy tables under `../results/` with run date and exact **GGUF** or model revision string.
