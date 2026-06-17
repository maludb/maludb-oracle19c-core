# MaluDB

MaluDB is a memory DBMS for long-term institutional memory, human-AI
knowledge sharing, and contextual recall. Built in **C** as PostgreSQL
extensions on **Ubuntu 24.04 LTS**, with **PostgreSQL 17** (PGDG) as
the foundation.

**New here?** Start with the [executive summary](executive-summary.md) —
what MaluDB is, the memory model, and why retrieval is relational/graph-first
with vector search reserved for the query classes that genuinely need it.

## Status

| | |
|---|---|
| Version | **0.100.0** (extension) — **document/note reindex protocol**: a background worker re-derives a document's or note's SVPOR graph footprint (subjects/verbs/SVO statements) against the current knowledge graph — `maludb_memory_reindex_claim` (stalest-first, registry-aware) → `maludb_memory_reindex_apply` (replace the `$source`-anchored statement footprint, then re-ingest idempotently with the document section stripped so `$source` re-links to the existing document; shared subjects/verbs merge, embeddings refresh via the 0.95.0 dirty-queue triggers), with `last_indexed`/`last_indexed_model` watermarks on `malu$document`; the documents/notes analogue of the 0.99.0 skill reindex, and likewise core never calls a model. On 0.99.0 **skill reindex protocol**: a background worker re-derives a skill's discovery tags (subjects/verbs/keywords) against the current knowledge graph — `maludb_skill_reindex_claim` (stalest-first, registry-aware staleness scan returning the skill body + current tags) → `maludb_skill_reindex_apply` (replace-`extracted`, preserving curator `manual` tags), with `last_indexed`/`last_indexed_model` watermarks on `malu$skill_package`; core never calls a model (a `claim → apply` contract an external worker drives, mirroring the 0.95.0 dirty-queue split). On 0.98.0 **note retrieval by subject/verb**: one-call `maludb_note_search` (subject-pattern + verb-exact/verb-like filters over extracted SVO edges, both statement→document rails, one row per note with matched edges aggregated) and deterministic `maludb_note_query_parse` free-text parsing against the tenant verb catalog. On 0.97.0 **agent-skill distribution**: skills become immutable, multi-file, distributable artifacts so Claude Agent Skills (SKILL.md bundles) can be ingested, discovered, and shared across teams. New `skill` entity subject type, `bundle_hash`/`frontmatter_jsonb` content identity, `malu$skill_file` bundle manifest, one-call `maludb_skill_register` (bundle-hash dedupe, extracted discovery tags, divergent fork lineage, supersession of non-materially-different parents), content-immutability guard, and a `fork_skill` fix (forks now copy the markdown body + bundle). Builds on 0.96.0 event-kind subject types (`docs/extraction-prompt-0.96.0.md`) and the 0.95.0 "semantic spine". Latest release tag `v4.5.0` shipped extension 0.100.0 on 2026-06-17. V4 acceptance suite: `scripts/maludb-fieldtest-v4` walks every V4 surface end-to-end; `bench/v4/run-bench` publishes recall + latency baselines; `docs/v4/acceptance-matrix.md` maps plan §12 criteria to test artefacts. |
| Test suite | **91 pg_regress targets** on PG 17 plus restd, realtimed, CLI, libmaludb v0.2, and pageindexd parser smoke checks |
| Drivers | Python, Node.js, PHP, C — all four validated against the live extension |
| External services | `maludb_modeld` (model gateway) + `maludb_mc2dbd` (database MCP listener) + `mcp-broker` (external-tool MCP broker) + `maludb-restd` (V3 REST gateway) + `maludb-realtimed` (V3 SSE event stream) + `maludb-pageindexd` (V4 PageIndex / ChatIndex builder) |
| Roadmap | `requirements.md` §9 Stages 1–16+ shipped through V4 GA — see [`version4-pageindex-plan.md`](version4-pageindex-plan.md) |
| Stage | Stages 1–15 (V3 GA + v3.1.0 follow-up) and Stage 16+ (V4 PageIndex / ChatIndex) shipped |
| License | PostgreSQL License (BSD-style) |
| Platforms | Ubuntu 24.04 LTS, x86_64 + arm64 |

## What's in it

| Capability | Where |
|---|---|
| Source → claim → fact → episode/memory pipeline | Stage 2 |
| Bitemporal time (valid + transaction time) | Stage 3 (S3-1) |
| Temporal supersession (corrections never overwrite) | Stage 3 (S3-2) |
| SVPOR organization registries | Stage 3 (S3-3) |
| MAUT confidence scoring | Stage 3 (S3-4) |
| Lifecycle + decay + legal hold | Stage 3 (S3-5) |
| Recursive-CTE graph traversal | Stage 4 (S4-1) |
| FTS + pg_trgm fuzzy matching | Stage 4 (S4-2) |
| Retrieval planner + query hints | Stage 4 (S4-3, S4-4) |
| Authorization-aware retrieval (3-stage authz) | Stage 4 (S4-5) |
| Workflow Extraction Engine | Stage 5 (S5-1) |
| Skill Runtime as governed state machine | Stage 5 (S5-2) |
| Skill discovery: manual subject / verb / keyword search, public skills, find/get/fork APIs | Stage 5 (S5-2) |
| User onboarding roles: `GRANT maludb_user TO role`, read/admin variants, and guarded `GRANT maludb TO role` alias | Stage 5 (S5-2) |
| Active Memory Pool manager | Stage 5 (S5-3) |
| Episode replay API | Stage 5 (S5-4) |
| Local Node sync protocol | Stage 6 (S6-1) |
| Model Registry blue-green + dual-space routing | Stage 6 (S6-2) |
| Embedding adapters + capability negotiation | Stage 6 (S6-3) |
| Advanced MC2DB tools | Stage 6 (S6-4) |
| External MCP broker (reference impl) | Stage 6 (S6-5) |
| C / Python / Node.js / PHP SDKs | Stage 6 (S6-6) |

## Doctrine

A small number of invariants run through the whole system:

1. **Corrections never silently overwrite history.** Supersession
   closes a valid window and opens a new version with an explicit
   supersession edge (`malu$supersession_edge`).
2. **Provenance is mandatory.** Every derived object has a
   `malu$derivation_ledger` entry. No row appears without one.
3. **Authorization is checked at three points** — planning,
   expansion, assembly. Never only at the final answer.
4. **Multi-model writes are atomic.** A logical operation that
   touches metadata, source links, graph edges, temporal windows,
   FTS, vectors, workflows, and audit logs commits or aborts as one.
5. **Nodes (local memory nodes) are never authoritative.** They
   submit proposals; the server applies them under governance.
6. **Workflow candidates don't auto-promote.** Approving a candidate
   flips a status; it doesn't create a procedural memory by side
   effect.

## Quickstart

Each block below is one step: copy it, run it, and check the result
against the line underneath before moving on.

**1. Install (Ubuntu 24.04 build host).**

Clone the repository and run the bootstrap. It builds and installs the
`maludb_core` PostgreSQL extension (PostgreSQL 17 from PGDG, plus pgvector,
pgaudit, and pg_partman) from source, then **creates the `maludb` database,
installs the extension into it (`CREATE EXTENSION maludb_core`), and sets its
`search_path`** — so on the default path you do not create the database or
the extension by hand:

```bash
git clone https://github.com/maludb/maludb-core
cd maludb-core
sudo scripts/maludb-bootstrap
```

You should see: the bootstrap finishes with a `Next steps:` checklist
(optional services, post-install validator, listener smoke test). Run the
remaining steps from this `maludb-core` checkout — that's where the
`examples/` scripts step 3 uses live.

> **Using a different or existing database?** Step 1 already created the
> default `maludb` database and installed the extension into it — so on the
> default path skip straight to verification below. To use another name (or
> an existing database), create it if needed and install the extension there
> yourself, then substitute that name for `maludb` in every step that
> follows:
>
> ```bash
> sudo -u postgres createdb mydb                                       # omit if it already exists
> sudo -u postgres psql -d mydb -c "CREATE EXTENSION maludb_core CASCADE"
> ```
>
> `CREATE EXTENSION` prints a few `NOTICE: installing required extension ...`
> lines (`vector`, `btree_gist`, `pg_trgm`, `pgcrypto`), then `CREATE EXTENSION`.

**2. Verify the version.**

```bash
sudo -u postgres psql -d maludb -tAc "SELECT maludb_core.maludb_core_version()"
```

You should see exactly: `0.100.0`

**3. Walk through the first scenario (optional).**

This script connects to the target database and runs a series of commands.
Replace 'maludb' with your database name if necessary.

Run it as `postgres`, like the steps above, and feed the file in over stdin
(`<`) rather than with `-f`: your shell opens the script from your checkout,
while `psql` connects as the superuser. Using `psql -d maludb -f …` directly
fails two ways — bare `psql` logs in peer-auth as your shell user (which maps to
the NOLOGIN `maludb` group role: `FATAL: role "maludb" is not permitted to log
in`), and `sudo -u postgres psql -f …` can't read a file under your `0750` home
directory.

```bash
sudo -u postgres psql -d maludb < examples/01-ingest-to-replay.sql
```

You should see: the ingest→replay walkthrough stream by, ending with
`example 01 done.`

### Enable MaluDB memory in application schemas

MaluDB does not modify new or existing PostgreSQL schemas automatically — you
enable each schema explicitly. The steps below create an application user 
named `app` with a schema of the same name; substitute your application's name in
both places. All commands target the `maludb` database from the Quickstart: the
extension is per-database, so pointing them at the default `postgres`
database fails with `ERROR: schema "maludb_core" does not exist`.

**1. Create the application user if necessary.**

Make sure you change the database name to your target database and 'app' to 
the name of your new user.

```bash
sudo -u postgres psql -d maludb -c "CREATE USER app"
```
You should see: `CREATE ROLE`.

**2. Grant the schema MaluDB access.**

Make sure you change the database name to your target database and 'app' to 
the name of your new user.

```bash
sudo -u postgres psql -d maludb -c "GRANT maludb_user TO app"
```

You should see: `GRANT ROLE`.

**3. Create the application schema and point the role's search path at it.**

Make sure you change the database name to your target database and 'app' to 
the name of your new schema and user.

```bash
sudo -u postgres psql -d maludb -c "CREATE SCHEMA app AUTHORIZATION app"
sudo -u postgres psql -d maludb -c "ALTER ROLE app SET search_path TO app, maludb_core, public"
```

You should see: `CREATE SCHEMA`, then `ALTER ROLE`.

Step 1's bootstrap set the **database** default `search_path` to
`maludb_core, public` (so admin calls to unqualified `maludb_core` functions
resolve) — which omits the tenant schema. The `ALTER ROLE` above pins the path
on the **role**, so every login as `app` resolves its own schema-local
`maludb_*` views automatically, with no per-connection `SET search_path`.
Without it you get `ERROR: relation "maludb_subject" does not exist`. (This
applies at login; the `SET ROLE` one-liner in step 5 still sets `search_path`
explicitly because `SET ROLE` does not pick up a role's default.)

**4. Enable the memory facades in the schema.**

Make sure you change the database name to your target database and 'app' to 
the name of your new schema.

```bash
sudo -u postgres psql -d maludb -c "SELECT * FROM maludb_core.enable_memory_schema('app')"
```

You should see one row:

```
 schema_name | enabled_version | object_count
-------------+-----------------+--------------
 app         | 0.100.0         |          155
```

**5. Verify the schema works as the application user.**

Make sure you change the database name to your target database and 'app' to 
the name of your new schema.

```bash
sudo -u postgres psql -d maludb -c "SET ROLE app; SET search_path TO app, maludb_core, public; SELECT * FROM maludb_subject"
```

You should see: an empty subject list — `(0 rows)` — the schema is ready
for its first ingest. Your application connects as `app` with
`search_path = app, maludb_core, public` and uses the schema-local
`maludb_*` views and functions from there.

For read-only users, grant `maludb_read`. On fresh installs where the role name
is available, `GRANT maludb TO app_user` is also a short alias for
`GRANT maludb_user TO app_user`. Existing operator installs that already have a
login role named `maludb` keep using `maludb_user` to avoid privilege confusion.

**6. Give the application role a password.** Peer authentication does
not work over TCP; remote logins use `scram-sha-256`. The `app`
user created above has no password yet:

```bash
sudo -u postgres psql -c "ALTER USER app PASSWORD '#change_on_install#'"
```

### Upgrade an existing installation

Upgrading is three steps, and **all three are per-host / per-database /
per-schema respectively** — stopping early leaves the system in a mixed state:

```bash
# 1. PER HOST: install the new extension files (from this checkout).
#    Build/install ONLY from the current checkout — an old working tree
#    `make install`s the same filenames and silently downgrades
#    default_version for every future CREATE EXTENSION on the host.
cd <this-checkout> && git pull
sudo make install PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config

# 2. PER DATABASE: update the extension in every database that has it.
sudo -u postgres psql -d maludb -c "ALTER EXTENSION maludb_core UPDATE"
sudo -u postgres psql -d maludb -tAc "SELECT maludb_core.maludb_core_version()"  # confirm

# 3. PER TENANT SCHEMA: refresh the memory facades. A migration cannot
#    replace tenant-owned views/functions (they are not extension members),
#    so new or changed facade objects only appear after this re-run.
sudo -u postgres psql -d maludb -c "SELECT * FROM maludb_core.enable_memory_schema('app')"
```

To list the schemas that need step 3 in a database:

```sql
SELECT schema_name, enabled_version FROM maludb_core.malu$enabled_schema;
```

Schemas still showing the old `enabled_version` haven't been refreshed.
`scripts/maludb-validate` checks that the installed extension version in the
database matches the version the host's extension files declare.

### Connect from an application server

A fresh install only accepts local connections. Four server-side changes
are required before an application server on the same network can reach
the database; all four are needed — if any one is missing, the
connection fails.

**1. Make PostgreSQL listen on the network.** This is the step that
blocks everything else: Ubuntu's PostgreSQL 17 default is
`listen_addresses = 'localhost'`, so remote clients get *connection
refused* regardless of any `pg_hba.conf` or firewall setup. Edit
`/etc/postgresql/17/main/postgresql.conf`:

```conf
listen_addresses = '*'        # or a specific address, e.g. '192.168.100.163'
```

A full restart is required — `reload` does not apply this setting:

```bash
sudo systemctl restart postgresql
ss -tln | grep 5432           # should now show 0.0.0.0:5432 (or your address)
```

**2. Give the application role a password.** Peer authentication does
not work over TCP; remote logins use `scram-sha-256`. The `app`
user created above has no password yet:

```bash
sudo -u postgres psql -c "ALTER USER app PASSWORD '#change_on_install#'"
```

**3. Allow the client in `pg_hba.conf`.** Add a `host` line to
`/etc/postgresql/17/main/pg_hba.conf` for the application server's
address (or subnet), then reload:

```conf
# TYPE  DATABASE   USER      ADDRESS               METHOD
host    maludb     app       192.168.100.0/24      scram-sha-256
```

```bash
sudo systemctl reload postgresql
```

**4. If `ufw` is active, open `5432/tcp` to the client subnet.** The
[hardening guide](docs/post-install-hardening.md) only opens `5329/tcp`
(the MC2DB listener); database connections need their own rule:

```bash
sudo ufw allow from 192.168.100.0/24 to any port 5432 proto tcp
```

**Verify from the application server** before wiring up a driver:

```bash
PGPASSWORD='#change_on_install#' psql -h <server-address> -p 5432 -U app -d maludb \
    -c 'select current_user, current_database()'
```

To expose the MC2DB listener (`:5329`) to the network as well, set
`HOST=0.0.0.0` together with TLS and a bearer token — see
[docs/install.md](docs/install.md) §6 and
[docs/post-install-hardening.md](docs/post-install-hardening.md).

The detailed install playbook is in [docs/install.md](docs/install.md).
A first-time tutorial is in [docs/getting-started.md](docs/getting-started.md).
Day-2 operations are in [docs/admin-guide.md](docs/admin-guide.md).

PHP applications can install the published Composer package directly:

```bash
composer require maludb/client:^0.1
```

If Composer reports that ZIP extraction tools are missing, install
`unzip` or `7z` first. On Ubuntu:

```bash
sudo apt install unzip
```

See [drivers/php/README.md](drivers/php/README.md) for connection setup,
autoloading notes, examples, and smoke-test instructions.

## Documents

- [`requirements.md`](requirements.md) — what the system must satisfy.
- [`version4-pageindex-plan.md`](version4-pageindex-plan.md) — Version 4 PageIndex / ChatIndex implementation plan.
- [`docs/install.md`](docs/install.md) — operator-grade install playbook.
- [`docs/getting-started.md`](docs/getting-started.md) — first-time walkthrough.
- [`docs/admin-guide.md`](docs/admin-guide.md) — backups, audit queries, lifecycle.
- [`docs/bench-baseline.md`](docs/bench-baseline.md) — performance baseline.
- [`docs/security-review.md`](docs/security-review.md) — RLS / pgaudit / grants audit.
- [`docs/runtime.md`](docs/runtime.md) — local model runtime details.
- [`docs/monitoring.md`](docs/monitoring.md) — Prometheus integration.
- [`docs/maludb-mc2dbd-contract.md`](docs/maludb-mc2dbd-contract.md) — MC2DB listener contract.
- [`examples/`](examples/) — end-to-end SQL scenarios.

## Stage roadmap

The project ships in stages (`requirements.md` §9):

- **Stage 1** ✅ — PostgreSQL substrate + pgvector + packaging.
- **Stage 1.5/1.6** ✅ — Model runtime + MC2DB listener (R1.0).
- **Stage 1.7 (R1.1)** ✅ — Advanced vector substrate.
- **Stage 2** ✅ — Memory object model.
- **Stage 3** ✅ — Bitemporal, SVPOR, MAUT, lifecycle.
- **Stage 4** ✅ — Retrieval planner, hybrid search, authz.
- **Stage 5** ✅ — Workflow extraction, skill runtime, active pools, episode replay.
- **Stage 6 (in-DB)** ✅ — Local node sync, model registry migration, advanced MC2DB tools.
- **Stage 6 (broker)** ✅ — External MCP broker reference (`services/mcp-broker` v0.1.0).
- **Stage 6 (drivers)** ✅ — C / Python / Node.js / PHP SDKs (v0.1.0 each). C SDK v0.2.0 (pool / skill / node wrappers) is a V3-SDK-01 follow-up.
- **Stage 7** ✅ — Hardening: benchmarks, security review, docs, deb packaging, **public alpha tagged**.
- **Stages 8–15 (Version 3)** ✅ — Platform-ergonomics track: identity/secrets, REST gateway + CLI + SDK parity, durable queue + cron, verbatim source archive v1, realtime + presence, vector/retrieval polish, metrics + log drains + backup/PITR + preview envs + replicas. Shipped as `v3.0.0` and `v3.1.0`.
- **Stages 16+ (Version 4)** ✅ — PageIndex / ChatIndex as governed memory surfaces over the Verbatim Source Archive. Reachable through every external surface (SQL / MC2DB / REST / CLI / 4-language SDK). Shipped as `v4.0.0`. See [`version4-pageindex-plan.md`](version4-pageindex-plan.md).

## Contributing

Sign-off (DCO) required on every commit. Commit messages start with
the imperative subject; the body explains the *why* and references
`requirements.md` section numbers when implementing a specific
requirement.

Branch naming:
- `phase-N/<topic>` for roadmap work
- `fix/<topic>` for fixes
- `spike/<topic>` for exploration
