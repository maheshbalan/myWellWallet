# Evaluation dimensions (checklist)

Use this with `eval/test-set/` and Dify run logs.

| # | Dimension | What to measure | Notes (from proposal) |
|---|------------|-----------------|------------------------|
| 1 | Domain — diabetes & labs | MCQ, lab threshold interpretation, FHIR field reading | MedHELM-style categories; target strong MCQ bar |
| 2 | Faithfulness / anti-hallucination | Stated values vs ground-truth in KB; judge score | Highest weight; clinical risk |
| 3 | Instruction-following | Persona, disclaimers, “no diagnosis,” format | ~20 safety-critical scenarios |
| 4 | Latency & resources | TTFT, throughput, peak RAM, battery (if on device) | Two tiers: low- vs high-resource handsets |
| 5 | Composite | Weighted score + tier-specific recommendation | Publish in `results/` with version date |

**Success targets (from proposal, tune as you run):** e.g. high MCQ accuracy; **faithfulness** ratio of supported vs total claims; faithfulness bar for critical values.

**Disclaimer:** This is a **class research** artifact, not a regulated clinical system.
