# maludb-core → Oracle 19c (RHEL): Level-of-Effort & Migration Plan

- **Date:** 2026-06-17
- **Author:** Migration assessment (Claude Code)
- **Repo:** `maludb/maludb-oracle19c-core` (this repo) — forked from `maludb/maludb-core`
- **Target platform:** Oracle Database **19c** on **Red Hat Enterprise Linux** (hard requirement — legacy system, **no upgrade path** to 21c/23ai)
- **Status:** Approved scope; ready for Phase 0

---

## 1. Goal & framing

Re-platform the maludb-core in-database layer from a **PostgreSQL C extension** to a
**faithful in-database Oracle 19c implementation** (PL/SQL packages + PL/SQL/Java for the
C functions), keeping the "logic lives in the database" design.

This is a **re-platforming, not a port**. PostgreSQL extensions have no Oracle equivalent:
the `.control`/PGXS build model, the `fmgr`/`SPI` C ABI, and many PL/pgSQL idioms simply do
not exist in Oracle. Nearly every source file changes; the two codebases will share a
**behavioral specification and data model**, not source.

**Headline estimate: XL — ~8–13 person-months** (≈7–12 months for one engineer fluent in
both PostgreSQL and Oracle PL/SQL, or ~4–7 months with two working in parallel).

---

## 2. Scope (decided)

**In scope**
- In-database extension layer: **95 PL/pgSQL modules (~16K lines, 136 functions)** → Oracle PL/SQL packages.
- **5 non-vector C files (~1.6K LOC, 10 exported fns)**: `auth` (HMAC/JWT), `secret` (libcurl fetch), `atomic`, `type`, `search` → PL/SQL + `DBMS_CRYPTO`/`UTL_HTTP`, or Java stored procedures.
- **4 client drivers** (C ~1045, Node ~780, PHP ~788, Python ~838 LOC) → Oracle connectivity + SQL dialect.
- Schema/DDL (`DATABASE_STRUCTURE.md`, ~206 KB) → Oracle types/constraints.
- Install/upgrade tooling and the regression test suite (re-platformed).

**Out of scope**
- **All in-database vector search** — handled externally. Deletes the 3 hardest C files outright (`maludb_ann.c` 660, `maludb_topk.c` 490, `maludb_vector.c` 220 LOC) and the `vector`/`malu_vector` type. (~1.37K LOC removed.)
- The 5 Python service daemons (`restd`, `realtimed`, `logsd`, `pageindexd`, `mcp-broker`).
- The `mc2dbd` C daemon.
- `third_party/llama.cpp` submodule (embeddings — external).

---

## 3. Repository & sync strategy

This folder has been **switched to the new repo**:

| Remote | URL | Purpose |
|---|---|---|
| `origin` | `maludb/maludb-oracle19c-core` (private) | The Oracle port — where all work lands |
| `upstream` | `maludb/maludb-core` (push **disabled**) | **Sync channel** — source of spec/schema changes |

**Why a separate repo, not a branch:** the port diverges ~100% and never merges back. A
permanent never-merging branch is a fork in disguise and would conflict on nearly every file
on every sync. A separate repo lets each side keep its native toolchain/CI/release cadence
(the Postgres line is fast-moving at v4.5.0; this port is frozen-target legacy).

**Keeping it in sync** (the shared contract is the *spec & data model*, not code):
1. `git fetch upstream` on a cadence (and via scheduled CI).
2. Diff the **contract files** since the last synced ref:
   `requirements.md`, `DATABASE_STRUCTURE.md`, `SVPOR_ERD.md`, `design-notes.md`, `end-to-end.md`, and `sql/` *intent*.
3. For each meaningful change, port the equivalent PL/SQL and **re-baseline the affected tests**.
4. Record the last-synced upstream commit in `docs/UPSTREAM_SYNC.md` so drift is auditable.

A `scripts/sync-upstream.sh` helper (Phase 0) automates steps 1–2 and prints the drift report;
a scheduled GitHub Action opens a tracking issue when contract files change upstream.

---

## 4. Effort breakdown

| Workstream | Estimate | Primary driver |
|---|---|---|
| Schema / DDL mapping | 2–4 wk | Type mapping (below); large schema |
| **PL/pgSQL → PL/SQL** | **12–20 wk** | **Dominant.** 16K lines; 519 JSONB + 244 array refs; dialect rewrites |
| C → PL/SQL / Java | 3–5 wk | HMAC/JWT, secret-over-HTTP, atomic writes, custom type, search |
| Vector removal surgery | 1–2 wk | Strip vector columns/fns across 20 files; external seam (subtractive) |
| Client drivers ×4 | 4–6 wk | Connectivity + dialect; thin (~3.4K LOC) |
| Bitemporal + security/session model | 2–3 wk | Temporal Validity; `SYS_CONTEXT`/VPD |
| Install/upgrade re-tooling | 2–4 wk | 140 versioned extension scripts → Liquibase/Flyway/SQLcl |
| Test harness + re-baseline | 4–8 wk | Rebuild 93 `pg_regress` suites on utPLSQL/SQLcl |
| **Total** | **30–52 wk (~8–13 person-months)** | |

Add ~15–20% contingency for integration, performance tuning, and unknowns.

---

## 5. PostgreSQL → Oracle 19c feature mapping (measured usage)

Counts are from the 95 modular `sql/` files (cumulative install scripts excluded to avoid 10× double-counting).

| Postgres feature | Usage | Oracle 19c approach | Difficulty |
|---|---|---|---|
| **JSONB** | 66 files / 519 hits | No native JSON type in 19c. Store as `CLOB CHECK (… IS JSON)`. Build via `JSON_OBJECT`/`JSON_ARRAYAGG` (`jsonb_build_object` ×216 maps cleanly). Read via `JSON_VALUE`/`JSON_QUERY`/`JSON_TABLE`. Mutate via `JSON_OBJECT_T`/`JSON_ARRAY_T` PL/SQL (no `JSON_TRANSFORM` in 19c). | **High** — but mostly *construction* (tractable); `jsonb_set` mutation = **0** (the painful kind is absent) |
| **Arrays** (`text[]`, `ARRAY[]`, `= ANY`, `unnest`) | 49 files / 244 hits | Nested-table/VARRAY collection types, `TABLE()`/`MEMBER OF`; or model as JSON arrays | High (semantic, not mechanical) |
| **TEXT** | 43 files / 197 hits | `VARCHAR2(4000)` or `CLOB` | Low (pervasive but mechanical) |
| **BOOLEAN columns** | 7 files | No SQL `BOOLEAN` in Oracle. Map to `NUMBER(1)`/`CHAR(1)` + check constraint (PL/SQL `BOOLEAN` is fine internally) | Low each, pervasive ripple |
| **`$$` / `DO` blocks** | 17 files / 110+55 | PL/SQL block syntax; q-quoting `q'[...]'` | Low–Med |
| **`RETURNING`** | 22 files / 91 | `RETURNING … INTO` (single-row); `BULK COLLECT`/cursors for multi-row | Med |
| **`ON CONFLICT` upsert** | 6 files | `MERGE` | Med |
| **`current_setting`/GUC** | 5 files / 17 | `SYS_CONTEXT` + `DBMS_SESSION.SET_CONTEXT` (app context namespace) | Med |
| **pgcrypto / uuid** | 4 files / 23+25 | `DBMS_CRYPTO`; `SYS_GUID()` → `RAW(16)` | Med |
| **Bitemporal** (`valid_from/valid_to`) | 2 files / 15 | Temporal Validity (`PERIOD FOR`) or app-managed columns | Med–High |
| **`RETURNS TABLE`/SETOF** | none found in modular SQL | (use pipelined fns / REF CURSOR where present in C-backed search) | — |
| `SECURITY DEFINER` | 1 | `AUTHID DEFINER` (PL/SQL default) | Low |
| pg_trgm similarity | 1 | Oracle Text / `UTL_MATCH` | Low (isolated) |
| recursive CTE / window / lateral | 1 / 2 / 2 | Supported natively in Oracle | Low |
| `money` / `inet` | 2 | `NUMBER` / `VARCHAR2` | Low |

**Confirmed absent in the in-DB code (de-risks the estimate):** no `CREATE POLICY` RLS, no
triggers, no `pg_cron`, no `LISTEN/NOTIFY`, no GIN/GiST/`EXCLUDE`, no FDW/dblink, no
PL/Python/PL/Perl, no materialized views, no partitioning, no generated columns.

### In-scope C functions → Oracle
| C file | LOC / fns | Uses | Oracle target |
|---|---|---|---|
| `maludb_auth.c` | 488 / 2 | OpenSSL HMAC/SHA (JWT) | `DBMS_CRYPTO.MAC` (HMAC-SHA256/512) + PL/SQL JWT assembly |
| `maludb_secret.c` | 321 / 1 | **libcurl** (HTTP secret fetch) | `UTL_HTTP` + network ACL (`DBMS_NETWORK_ACL_ADMIN`) |
| `maludb_atomic.c` | 319 / 2 | SPI | PL/SQL + `SELECT … FOR UPDATE` / autonomous txn |
| `maludb_type.c` | 166 / 4 | custom type I/O | Oracle OBJECT type or relational columns |
| `maludb_search.c` | 307 / 1 | SPI search | PL/SQL; Oracle Text if full-text |

---

## 6. Phased plan

**Phase 0 — Foundation (1 wk)**
- Rebrand repo identity (README, `LICENSE` headers, control/Makefile removal plan).
- Stand up Oracle 19c on RHEL dev instance; pick migration tool (Liquibase or SQLcl) and test framework (**utPLSQL**).
- Land `scripts/sync-upstream.sh` + `docs/UPSTREAM_SYNC.md` + scheduled drift-check CI.
- Decide PL/SQL vs Java for the 5 C functions (lean PL/SQL + `DBMS_CRYPTO`/`UTL_HTTP`).

**Phase 1 — Schema & vector excision (3–5 wk)**
- Convert DDL with the type-mapping table; establish JSON-in-CLOB and collection conventions.
- Strip vector columns/types/functions (20 files) and define the **external-vector seam**
  (store embedding row keys; logic calls out to the external vector service).
- Stand up the Liquibase/SQLcl changelog as the new install/upgrade model.

**Phase 2 — Core PL/SQL conversion (12–20 wk)**
- Port modules in dependency order; group into Oracle **packages** by domain (auth, ingestion, retrieval, governance, lifecycle, …).
- Build a reusable JSON helper package (`JSON_OBJECT_T` wrappers) and a collection helper package to keep call sites clean.
- Reimplement the 5 C functions (3–5 wk, parallelizable).

**Phase 3 — Drivers (4–6 wk, parallel with Phase 2)**
- C: libpq → ODPI-C/OCI. Node: `pg` → `oracledb`. PHP: `pgsql` → `oci8`/`pdo_oci`. Python: `psycopg` → `python-oracledb`.
- Adjust embedded SQL/dialect; keep public driver API stable.

**Phase 4 — Test parity & hardening (4–8 wk)**
- Re-express the 93 `pg_regress` suites as utPLSQL; re-baseline expected outputs against Oracle.
- Behavioral-equivalence pass vs the Postgres reference; performance tuning (indexes, JSON search paths).

**Phase 5 — Packaging & docs (2–4 wk)**
- RHEL install artifacts (SQL scripts/RPM), runbook, upgrade path, ops docs.

---

## 7. Top risks & mitigations

1. **Oracle 19c JSON maturity** — no native JSON type / `JSON_TRANSFORM`. *Mitigation:* `JSON_OBJECT_T` PL/SQL APIs (12.2+); favorably, the code is JSON-*construction*-heavy, not mutation-heavy.
2. **Test parity is the long pole** — proving equivalence across 93 suites. *Mitigation:* automate diffing against the Postgres reference; budget Phase 4 generously.
3. **Tooling gap** — `ora2pg` handles schema + ~40–60% of vanilla PL/pgSQL, weak on JSONB/array-heavy code. *Mitigation:* use it for the mechanical 40–60%; plan manual rework for the rest.
4. **Array semantics** — `= ANY`, `unnest`, `array_agg` ordering differ. *Mitigation:* centralize in a collection helper package; test ordering explicitly.
5. **No SQL `BOOLEAN`** — pervasive ripple. *Mitigation:* one convention (`NUMBER(1)` + check), applied mechanically.
6. **Sync discipline** — upstream is fast-moving. *Mitigation:* automated drift-check CI + `UPSTREAM_SYNC.md` ledger.

---

## 8. Open questions
- External vector seam: what's the integration contract (sync call vs queue; who owns embedding lifecycle)?
- C-function target: PL/SQL-only acceptable, or is the JVM available in the Oracle instance (enables Java stored procs)?
- Network ACLs: is outbound `UTL_HTTP` from the DB permitted in the target environment (for the secret resolver)?
- Migration framework preference: Liquibase vs SQLcl/`liquibase`-via-SQLcl vs Flyway?
