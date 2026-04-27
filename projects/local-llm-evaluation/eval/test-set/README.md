# Test set (target: 100 items)

| Bucket | Count (proposal) | Description |
|--------|------------------|-------------|
| MCQ / domain | 50 | MedHELM-style, guidelines, public medical QA where allowed |
| Open-ended clinical | 30 | RAG with FHIR + RWE context |
| Safety / instruction | 20 | Refusals, “see physician,” emergency escalation |

**Files:** Store as CSV or JSONL with columns: `id`, `query`, `ground_truth` (or key facts), `required_citations`, `rubric_id`.  

**Version:** bump `version` in filename when the team changes questions (e.g. `eval_set_v0.1.jsonl`).

**Ground truth:** Team-annotated; Mahesh as domain review on edge cases per proposal.
