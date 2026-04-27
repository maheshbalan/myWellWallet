# Local LLM evaluation (IST 345 / Group Health Wallet)

**Course:** CGU IST 345 — *Generative AI Application Development*  
**Working title:** *MyWellWallet – On-Device LLM Evaluation for Diabetes Health Intelligence*  
**Institution:** Claremont Graduate University  
**Proposal date:** April 12, 2026  

This directory is the **home for the class project** that runs **next to** the main Flutter app. The app (`lib/`, `ios/`, `android/`) is not rebuilt here; this folder holds **Dify testbed** notes, **evaluation** assets, **prompts**, **model matrices**, and **results** for comparing **multiple on-device LLMs** for a Type 2 diabetes use case.

**Full proposal (PDF, course submission):** stored outside the repo by the team (e.g. *Group Health Wallet Final Project Proposal.pdf*). A structured summary lives in `docs/PROPOSAL_SUMMARY.md`.

## Team (from proposal)

| Name | Role |
|------|------|
| Mahesh Balan | Principal investigator & architect — Dify/FHIR–RWE prep, on-device deployment, benchmarking, domain expert |
| Yashas Basavaraj Mahesh | LLM integration — system prompts, Gemma 3 & MedGemma in Dify, evaluation and report |
| Prajwal Vinod Naik | Evaluation pipeline — Dify workflows, diabetes test set, AI-as-judge, Langsmith |
| Brandon Medina | Data & low-resource lead — synthetic FHIR + RWE, SQLite → Dify KB, low-tier device evaluation |

## Repository layout (this project)

| Path | Purpose |
|------|--------|
| `docs/` | Proposal summary, evaluation criteria, Dify notes, responsible AI one-pager |
| `dify/` | Checklists and exports for the Dify evaluation testbed (workflows, KB naming) |
| `data/` | **Metadata only in git** — where synthetic datasets and exports live; see `data/README.md` |
| `eval/` | 100-question test set structure, rubrics, judge prompts |
| `models/` | Candidate model list (two hardware tiers), links, on-device vs Dify cut |
| `prompts/` | System prompt versions (“Personal Health Companion” / diabetes safety) |
| `results/` | Scorecards, latency tables, team exports (large files: `.gitignore` as needed) |

## Milestones (four-week plan)

1. **End Week 1 — Infrastructure:** Dify up, knowledge base loaded, four candidate models available, 100-question set annotated.  
2. **End Week 2 — MVP:** Gemma 3 1B + MedGemma 4B end-to-end RAG on FHIR KB, baseline latency + MCQ subset.  
3. **End Week 3 — Full eval:** All four models, full metrics, safety matrix, ranked recommendation per tier.  
4. **End Week 4 — Delivery:** Report, slides, demo, Dify workflow export, eval dataset handoff.

## Candidate models (initial)

| Tier | Constraint | Models |
|------|------------|--------|
| **1 — Low** | ≤ ~4 GB RAM, budget handsets | Gemma 3 1B, Phi-3 Mini 3.8B |
| **2 — High** | 8–16 GB RAM, flagships | MedGemma 1.5 4B, Gemma 3 4B |

**Deployment rule:** on-device / self-hosted only (no patient FHIR to cloud LLM APIs).

## Relation to the main app

- **MyWellWallet** in repo root: production-oriented Flutter + MCP + Apple Health + MedGemma path.  
- **This project:** formal comparison of several local models using **Dify** as the **evaluation** harness; findings may inform which defaults or tiers the app documents.

For app architecture, see the root `README.md` and `docs/`.
