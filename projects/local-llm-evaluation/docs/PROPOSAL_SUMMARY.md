# Proposal summary (IST 345 – Group Health Wallet)

*Condensed from the team’s final project proposal. The signed PDF is the course submission; this file is for GitHub discoverability.*

## Title

**Generative AI Application Development for a Health Wallet**  
Subtitle used in the proposal: *MyWellWallet – On-Device LLM Evaluation for Diabetes Health Intelligence*.

## Problem (short)

U.S. adults with chronic conditions often have data split across EHRs and devices; Type 2 diabetes care involves multiple silos. The wallet already unifies **FHIR (via MCP)** and **RWE (Apple / Android Health)** locally. This project **does not re-implement the app**; it **evaluates** which **locally deployable LLMs** best support **diabetes-relevant** Q&A over that pattern, using **Dify** as a controlled testbed.

## Why only local / on-device models

- Patient data sovereignty and reduced HIPAA/FTC PHR risk vs sending FHIR to cloud chat APIs.  
- Offline and low-resource global scenarios.  
- Latency and zero marginal per-token cost after download.  
- Reproducible model versions.

## Dify as evaluation testbed

- **Knowledge base:** Synthetic + structured **FHIR + RWE** (e.g. CGM traces, steps, BP) ingested for RAG, aligned with wallet semantics.  
- **System prompt:** “Personal health companion” — diabetes context, **safety** (e.g. defer med changes to clinicians), **citation** to retrieved values.  
- **Workflow:** ~100 test queries; dimensions include **domain knowledge**, **faithfulness**, **instruction-following**, **latency/ops**.  
- **AI-as-judge:** e.g. Mistral-based scoring on open-ended answers; **BERTScore** and rubrics where applicable.

## Evaluation criteria (from proposal)

1. **Domain / diabetes** — MedMCQ / MedHELM-style MCQ, lab interpretation, guideline-aligned thresholds.  
2. **Generation / anti-hallucination** — Grounding in retrieved FHIR vs invented values.  
3. **Instruction-following** — Persona, refusals, formatting.  
4. **Cost & latency** — TTFT, tok/s, peak RAM, battery (on device or Dify first cut).  
5. **Metrics** — Accuracy targets (e.g. high MCQ bar), **faithfulness** = 1 − (unsupported claims / total claims) with high bar for clinical use.

## Responsible AI (headline)

- **Safety:** No unsupervised med dosing; emergency escalation; human-in-the-loop for edge cases.  
- **Faithfulness / transparency:** Citations to specific FHIR fields; flag ungrounded text.  
- **Mitigation:** RAG-first design, controlled synthetic data for training tests, on-device data path.

## References (see proposal PDF)

Gemma 3, Phi-3, MedGemma model cards; MedMCQA, PubMedQA; MedHELM / HAI medical LLM evaluation; Huyen (Ch. 4) style evaluation dimensions.

---

*Course: CGU IST 345. Team: Mahesh Balan, Yashas Basavaraj Mahesh, Prajwal Vinod Naik, Brandon Medina. Proposal date: April 12, 2026.*
