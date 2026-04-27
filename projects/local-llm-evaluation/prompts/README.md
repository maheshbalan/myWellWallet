# System prompts

Store versioned **system prompts** for the Dify “Personal Health Companion” persona.

## English → SQLite (for Dify + small LLM)

| File | Use |
|------|-----|
| `text_to_sql_for_dify_COPY_PASTE.txt` | **Paste into Dify** as system prompt: plain **SQL only** starting with **`SELECT`** (no markdown/fences); **JOIN**s where needed for **Database Query**. |
| `dify_text_to_sql_system_prompt.md` | Join-key table + Dify Database Query expectations (longer companion to the `.txt`). |

## Requirements (from proposal)

- Diabetes-aware, **non-clinician** role  
- **Cite** specific retrieved values (lab, date, source) when making claims  
- **Defer** medication changes and diagnosis to a licensed professional  
- **Escalate** emergency language when needed  

## Naming

`system_prompt_v0.1.md` — bump when you change anything material.

## Alignment

Final prompt text in Dify should match the committed file, or document the diff in a one-line change log in the same folder.
