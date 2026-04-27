# Google Cloud SQL + Dify (from the `fixtures` SQLite export)

This guide uses the files under **`fixtures/test_database_export/`**:

| File | Role |
|------|------|
| `mywellwallet_phone.sqlite3` | Full data export from the phone |
| `SQLITE_SCHEMA.md` | Human-readable table and column reference (authoritative copy: `docs/SQLITE_SCHEMA.md`) |

**Important:** **Google Cloud SQL does not host SQLite.** You create a **PostgreSQL** (recommended) or **MySQL** instance, then **copy the data** from the SQLite file into it. The schema in the docs is SQLite DDL; the migration tools below build the target tables for you or map types automatically.

**Privacy:** The fixture can contain real-looking PHI. Use a **private** GCP project, **restricted** networks, and **no public** Dify knowledge unless data is de-identified.

---

## Part A — Create a Cloud SQL (PostgreSQL) instance

You need a Google Cloud project with **billing** enabled (Cloud SQL is not free at scale; check current [Cloud SQL pricing](https://cloud.google.com/sql/pricing)).

### 1. Enable the API and open Cloud SQL

1. In [Google Cloud Console](https://console.cloud.google.com/), pick your project.
2. **APIs & Services → Library** → search **Cloud SQL Admin API** → **Enable** (or enable when prompted).

Or with `gcloud` (if installed):

```bash
gcloud services enable sqladmin.googleapis.com
```

3. Open **SQL** from the hamburger menu (or [console.cloud.google.com/sql](https://console.cloud.google.com/sql)).

### 2. Create an instance

1. Click **Create instance** → **Choose PostgreSQL**.
2. **Instance ID:** e.g. `mywellwallet-pg` (lowercase, hyphens).
3. **Password:** set a strong **root / postgres user password** and store it in a secret manager or password vault.
4. **Region / zone:** pick the region closest to you or to Dify (if self-hosted in GCP, same region reduces latency and egress).
5. **Machine type:** for testing, **db-f1-micro** or a small shared core is enough; increase if queries are slow.
6. **Storage:** SSD, auto-resize is fine for small datasets.
7. **Connections**
   - **Public IP** on + **Authorized networks** → add your **office/home IP** for admin access from your laptop, **or**
   - **Private IP** only (more secure) and use [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/postgres/connect-auth-proxy) from Cloud Run / GCE / your workstation.
8. **Create** and wait until the instance status is **RUNNABLE** (a few minutes).

### 3. Create a database and a login role

1. Open your instance → **Databases** → **Create database**  
   - Name: e.g. `mywellwallet`
2. **Users** → **Add user account**  
   - Name: e.g. `dify_loader` (or `postgres` if you use the default)  
   - Password: strong password, stored securely.

You will use:

- **Host:** instance **Public IP** (or `127.0.0.1` when using the Auth Proxy).
- **Port:** `5432` (default PostgreSQL).
- **Database:** `mywellwallet`
- **User / password:** as created.

**SSL:** For clients connecting over the public internet, use **SSL**; download the **server CA** from the instance **Connections** page if the client requires it. The Auth Proxy handles encryption when you use it.

---

## Part B — Load the SQLite file into PostgreSQL

### Option 1: pgloader (fastest for SQLite → Postgres)

[pgloader](https://pgloader.io/) maps SQLite types to PostgreSQL and copies all tables in one step.

1. **Install pgloader** (macOS: `brew install pgloader`; Linux: use your package manager or Docker image that includes `pgloader`).

2. **Connect to Cloud SQL** from your machine:

   - **Simplest for first tests:** [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/postgres/sql-proxy) listening on `localhost:5432` (add your instance connection name, e.g. `PROJECT:REGION:mywellwallet-pg`).

   ```bash
   # Example: download the proxy binary, then:
   ./cloud-sql-proxy --port 5432 PROJECT:REGION:mywellwallet-pg
   ```

   - Or use **Public IP** + **authorized network** and connect with `psql`/`pgloader` to the instance IP (enable SSL as required).

3. **Run pgloader** (paths relative to the repo root):

   ```bash
   pgloader \
     fixtures/test_database_export/mywellwallet_phone.sqlite3 \
     "postgresql://dify_loader:YOUR_PASSWORD@127.0.0.1:5432/mywellwallet"
   ```

   If you connect without the proxy, replace host with the instance **public IP** and add SSL options your `pgloader` build supports (see [pgloader PostgreSQL connection](https://pgloader.readthedocs.io/en/latest/ref/pgsql.html)).

4. **Check tables** with `psql`:

   ```bash
   psql "postgresql://dify_loader:YOUR_PASSWORD@127.0.0.1:5432/mywellwallet" -c "\dt"
   ```

   You should see `users`, `fhir_resources`, `health_glucose`, and the other tables from `SQLITE_SCHEMA.md`.

**If something fails** (e.g. reserved words, type quirks), use Option 2 or fix the generated DDL in an empty database and re-import with `COPY` from CSVs produced by the Python export script (see `scripts/export_sqlite_for_dify.py` and `docs/DATABASE_FIXTURE_TESTING_AND_DIFY.md`).

### Option 2: Manual or CSV-based load

1. Create tables in PostgreSQL with DDL equivalent to `docs/SQLITE_SCHEMA.md` (e.g. `TEXT` → `TEXT`, `REAL` → `DOUBLE PRECISION`, `INTEGER` → `INTEGER` or `BIGINT`, add `UNIQUE` constraints to match).
2. Use `python3 scripts/export_sqlite_for_dify.py` to export CSVs for the `health_*` and related tables, then `COPY ... FROM STDIN` or Cloud Console import for each CSV. **Note:** the script does not export every table; `fhir_resources` is large—**pgloader** (Option 1) is better for a full clone.

---

## Part C — Connect this database to Dify

Dify’s default **“Knowledge” file upload** does **not** read a live SQL connection string. You have three practical patterns:

### Pattern 1 — File-based knowledge (no live Cloud SQL in Dify)

What you may already be doing: generate **Markdown + CSV** from the same export and **upload** to a Dify Knowledge base.

- Run: `python3 scripts/export_sqlite_for_dify.py fixtures/test_database_export/mywellwallet_phone.sqlite3 fixtures/test_database_export/dify_export`
- In Dify: **Knowledge → Create → Import from file** and upload the generated files.

**When to use:** Fastest, no server code. **Cloud SQL** is still useful for analytics, Metabase, or other tools; Dify just does not “attach” the DB.

### Pattern 2 — External Knowledge API (Dify calls **your** service; service queries Cloud SQL)

This is the pattern that **uses** Cloud SQL as the backing store for retrieval in Dify.

1. **Read** the official spec: [External Knowledge API](https://docs.dify.ai/en/guides/knowledge-base/external-knowledge-api) and [Connect to external knowledge base](https://docs.dify.ai/en/use-dify/knowledge/connect-external-knowledge-base). Dify will `POST` to `YOUR_BASE_URL/retrieval` with JSON containing `knowledge_id`, `query`, and `retrieval_setting`.

2. **Deploy a small API** (e.g. **Cloud Run** in the same GCP project) that:

   - Verifies the `Authorization: Bearer` token you configure in Dify.
   - Uses the [Cloud SQL Python connector](https://cloud.google.com/sql/docs/postgres/connect-connectors) or the Auth Proxy sidecar to run **parameterized** SQL (or full-text / `pg_trgm` search on `fhir_resources.resource_data`, etc.).
   - Returns JSON: `{ "records": [ { "content": "...", "score": 0.9, "title": "...", "metadata": {} } ] }`  
   - **Do not** return `metadata: null`; use `{}` if empty (per Dify docs).

3. **In Dify UI**

   - **Knowledge** → **External Knowledge API** → **Add** → set **name**, **API base URL** (Dify will call `.../retrieval`), and **API key** Dify should send.
   - **Create knowledge** → **Connect to an external knowledge base** → pick that API, set an **External knowledge ID** string your service understands (e.g. `mywellwallet_fhir` vs `mywellwallet_health`), and tune **Top K** and **score** threshold.

4. **Self-hosted Dify:** if retrieval fails with proxy errors, add your API host to the [SSRF allowlist](https://docs.dify.ai/en/use-dify/knowledge/connect-external-knowledge-base) in `allowed_domains` as documented.

**When to use:** You want **one source of truth** in Cloud SQL and **live** retrieval in apps.

### Pattern 3 — ETL on a schedule

- Nightly job (Cloud Run / Workflows) runs SQL in Cloud SQL, exports Markdown/CSV, and **calls Dify’s [document API](https://docs.dify.ai/api-reference/documents/create-document-by-file)** or re-uploads files. Dify then stays file-based, but the **data** is refreshed from Cloud SQL.

**When to use:** You want Dify’s built-in chunking/embedding on files but still maintain Cloud SQL for reporting.

---

## Part D — Checklist

- [ ] Cloud SQL **PostgreSQL** instance running; database and user created.
- [ ] **Fixture** `mywellwallet_phone.sqlite3` loaded (prefer **pgloader**).
- [ ] `psql \dt` shows the expected tables (compare with `SQLITE_SCHEMA.md`).
- [ ] Dify: choose **file upload** OR **External Knowledge API** (with a real `/retrieval` implementation) OR **ETL to files**.
- [ ] If using External API: same VPC / connector / secrets as Cloud SQL, never expose raw SQL to the public internet without auth.

---

## Related files in this repo

| Document | Content |
|----------|--------|
| `fixtures/test_database_export/README.md` | Phone export, `devicectl`, row counts, synthetic seed |
| `docs/DATABASE_FIXTURE_TESTING_AND_DIFY.md` | Simulator seed, `export_sqlite_for_dify.py`, Dify file upload |
| `docs/SQLITE_SCHEMA.md` | Table definitions and query examples |

For **Google** specifics beyond this overview, use the current [Cloud SQL for PostgreSQL](https://cloud.google.com/sql/docs/postgres) and [connect from Cloud Run](https://cloud.google.com/sql/docs/postgres/connect-run) documentation.
