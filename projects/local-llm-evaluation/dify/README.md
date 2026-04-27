# Dify evaluation testbed

**Intent:** Run the **same RAG pattern** as the wallet: knowledge base = synthetic **FHIR + RWE** + (optional) exports aligned with `fixtures/test_database_export/` practices.

## Setup checklist

- [ ] Dify instance URL and org access for all team members  
- [ ] Knowledge base created; documents ingested (see `../data/README.md`)  
- [ ] External API or file pipeline consistent with `docs/DATABASE_FIXTURE_TESTING_AND_DIFY.md` / `docs/CLOUD_SQL_DIFY_SETUP.md` if using Cloud SQL  
- [ ] One app workflow per model **or** one workflow with model switch (document which)  
- [ ] System prompt version pinned — store copy under `../prompts/`  
- [ ] AI-as-judge: Mistral (or agreed judge) with frozen judge prompt in `../eval/`

## Artifacts to export at milestone end (for course submission)

- Dify **workflow / DSL** or screenshots + YAML export if available  
- Knowledge base **document list** (no PHI in public repos)  
- **Run log** with model id, date, and eval set version

**PHI warning:** Do not commit real patient exports. Use only **synthetic** or **de-identified** sets approved for the class.
