# Data (synthetic FHIR + RWE for Dify)

**Nothing sensitive should be committed by default.**

## Intended contents (from proposal)

- **Synthetic FHIR** for ~30 diabetic patient scenarios (labs, meds, comorbidities, etc.)  
- **RWE-style** traces: e.g. 7-day CGM, 30-day BP, 90-day steps  
- Exports for Dify: CSV / Markdown / SQL dumps per team pipeline  

## Suggested flow

1. Build or generate SQLite compatible with the app schema (`docs/SQLITE_SCHEMA.md`).  
2. Run `python3 scripts/export_sqlite_for_dify.py` from repo root, or a team-specific variant.  
3. Upload to Dify or load via Cloud SQL + External Knowledge API per `docs/CLOUD_SQL_DIFY_SETUP.md`.  

## Git policy

- Add large generated files to `.gitignore` in this folder if needed.  
- Check in only **sample** rows, **hashes**, or **documentation** of datasets unless the course explicitly allows full synthetic dumps in a private branch.
