# MaluDB

MaluDB is a memory DBMS for long-term institutional memory, human-AI
knowledge sharing, and contextual recall. Built in **C** as PostgreSQL
extensions on **Ubuntu 24.04 LTS**, with **PostgreSQL 17** (PGDG) as
the foundation.

The project is a single managed installation: `sudo apt install maludb`
(forthcoming) gives you PostgreSQL 17 + pgvector + pgaudit + pg_partman
+ the `maludb_core` extension wired together. Operators don't have to
provision PostgreSQL manually.

## Status

| | |
|---|---|
| Version | **0.73.0** (extension) — release tag `v4.1.0` shipped the schema-local skill discovery update on 2026-05-19. V4 acceptance suite: `scripts/maludb-fieldtest-v4` walks every V4 surface end-to-end; `bench/v4/run-bench` publishes recall + latency baselines; `docs/v4/acceptance-matrix.md` maps plan §12 criteria to test artefacts. |
| Test suite | **79 pg_regress targets** on PG 17 plus restd, realtimed, CLI, libmaludb v0.2, and pageindexd parser smoke checks |
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

```bash
# 1. Install (Ubuntu 24.04 build host).
sudo scripts/maludb-bootstrap

# 2. Create a database and the extension.
sudo -u postgres createdb mydb
sudo -u postgres psql -d mydb -c "CREATE EXTENSION maludb_core CASCADE"

# 3. Walk through the first scenario.
psql -d mydb -f examples/01-ingest-to-replay.sql
```

### Enable MaluDB memory in an application schema

MaluDB does not modify ordinary PostgreSQL schemas automatically. To opt a
schema into schema-local memory views:

```sql
CREATE USER zozocal;
GRANT maludb_memory_executor TO zozocal;
CREATE SCHEMA zozocal AUTHORIZATION zozocal;
SET ROLE zozocal;
SET search_path TO zozocal, maludb_core, public;
SELECT * FROM maludb_core.enable_memory_schema();
SELECT * FROM maludb_subject;
```

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
- **Stages 8–15 (Version 3)** 🚧 — Platform-ergonomics track: identity/secrets, REST gateway + CLI + SDK parity, durable queue + cron, verbatim source archive v1, realtime + presence, vector/retrieval polish, metrics + log drains + backup/PITR + preview envs + replicas.
- **Stage 7** ✅ — Hardening: benchmarks, security review, docs, deb packaging, public alpha tagged.
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
