# MaluDB

MaluDB is a memory DBMS for long-term institutional memory, human-AI
knowledge sharing, and contextual recall. Built in **C** as PostgreSQL
extensions on **Ubuntu 24.04 LTS**, with **PostgreSQL 17** (PGDG) as
the foundation.

The project is a single managed installation: `sudo apt install maludb`
(forthcoming) gives you PostgreSQL 17 + pgvector + pgaudit + pg_partman
+ the `maludb_core` extension wired together. Operators don't have to
provision PostgreSQL manually.

**New here?** Start with the [executive summary](executive-summary.md) —
what MaluDB is, the memory model, and why retrieval is relational/graph-first
with vector search reserved for the query classes that genuinely need it.

## Status

| | |
|---|---|
| Version | **0.95.0** (extension) — the "semantic spine": subjects/verbs/edges are the vector layer (deterministic in-DB entity cards + trigger-fed dirty queue + external embed worker, landing in the object-embedding rail) with **opt-in** `similar_to` traversal jumps; the chunk-compartment rail is frozen/deprecated; extraction JSON contract unchanged (see `docs/semantic-entity-embeddings.md`). Includes 0.94.0: episodes folded into subjects (**BREAKING** ingest contract — `episodes[]` removed; events are `subjects[]` entries with `occurred_at`). Latest release tag `v4.3.0` shipped extension 0.95.0 on 2026-06-07. V4 acceptance suite: `scripts/maludb-fieldtest-v4` walks every V4 surface end-to-end; `bench/v4/run-bench` publishes recall + latency baselines; `docs/v4/acceptance-matrix.md` maps plan §12 criteria to test artefacts. |
| Test suite | **89 pg_regress targets** on PG 17 plus restd, realtimed, CLI, libmaludb v0.2, and pageindexd parser smoke checks |
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

```bash
sudo scripts/maludb-bootstrap
```

You should see: the bootstrap finishes with a `Next steps:` checklist
(optional services, post-install validator, listener smoke test).

**2. Create a database and install the extension.**

```bash
sudo -u postgres createdb maludb
sudo -u postgres psql -d maludb -c "CREATE EXTENSION maludb_core CASCADE"
```

You should see: a few `NOTICE: installing required extension ...` lines
(`vector`, `btree_gist`, `pg_trgm`, `pgcrypto`), then `CREATE EXTENSION`.

**3. Verify the version before going further.**

```bash
sudo -u postgres psql -d maludb -tAc "SELECT maludb_core.maludb_core_version()"
```

You should see exactly: `0.95.0`

**4. Walk through the first scenario.**

```bash
psql -d maludb -f examples/01-ingest-to-replay.sql
```

You should see: the ingest→replay walkthrough stream by, ending with
`example 01 done.`

### Enable MaluDB memory in an application schema

MaluDB does not modify ordinary PostgreSQL schemas automatically. To opt a
schema into schema-local memory views:

```sql
-- Run this connected to the database where maludb_core is installed
-- (e.g. `psql -d maludb` or `\c maludb`). The extension is per-database:
-- running this from the default `postgres` database fails with
-- ERROR: schema "maludb_core" does not exist.
-- `app` below is your application's user and schema — name it after
-- your application.
CREATE USER app;
GRANT maludb_user TO app;
CREATE SCHEMA app AUTHORIZATION app;
SET ROLE app;
SET search_path TO app, maludb_core, public;
SELECT * FROM maludb_core.enable_memory_schema();
SELECT * FROM maludb_subject;
```

You should see: `enable_memory_schema()` returns one row —
`(app, 0.95.0, 145)` — and `maludb_subject` returns an empty result
(0 rows) until you ingest your first memory.

For read-only users, grant `maludb_read`. On fresh installs where the role name
is available, `GRANT maludb TO app_user` is also a short alias for
`GRANT maludb_user TO app_user`. Existing operator installs that already have a
login role named `maludb` keep using `maludb_user` to avoid privilege confusion.

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
sudo -u postgres psql -c "ALTER USER app PASSWORD 'choose-a-password'"
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
PGPASSWORD='choose-a-password' psql -h <server-address> -p 5432 -U app -d maludb \
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
