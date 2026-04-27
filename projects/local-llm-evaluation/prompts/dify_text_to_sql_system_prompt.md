# Text-to-SQL for Dify Database Query — plain SQL only

The copy-paste system prompt lives in **`text_to_sql_for_dify_COPY_PASTE.txt`**.

## Output contract

- **No Markdown** — no headings, fences, `` ` `` blocks, or labels.
- The model reply must be **SQL only**. The **first keyword** must be **`SELECT`** (after optional whitespace).
- Dify passes that string straight into **Database Query** as one runnable statement.

## Joins

Use **`INNER JOIN` / `LEFT JOIN`** whenever the question pulls from more than one table. Same join keys as in the `.txt` file.

Schema reference: **`docs/SQLITE_SCHEMA.md`** at repo root.

## Security

Read-only execution; validate before sending to production PHI.
