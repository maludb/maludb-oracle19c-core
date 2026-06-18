# NEXT SESSION — Oracle 19c port kickoff (read me first)

**For:** the agent/engineer resuming this work, likely on a **RHEL server with Oracle 19c installed**, with **no access to the prior conversation**. This note is the bridge.

**Date written:** 2026-06-17

---

## 0. Orientation (read before touching anything)

- This repo (`maludb/maludb-oracle19c-core`) is the **Oracle 19c (RHEL) port** of `maludb-core`.
- **It was forked from the PostgreSQL codebase, so it still LOOKS like a Postgres extension** —
  `src/*.c`, `sql/*.sql`, `maludb_core.control`, `Makefile`, `debian/` are all present. That is
  **intentional**: this is the **source you are porting FROM**, not Oracle code. As of this note,
  the *only* Oracle-specific content is under `docs/plans/`.
- **Authoritative plan:** [`docs/plans/2026-06-17-oracle19c-migration-loe.md`](./2026-06-17-oracle19c-migration-loe.md).
  Read it in full before starting. It contains scope, the feature-mapping table, effort, phasing,
  risks, and all decisions (§5 C-functions, §9 migration tooling).

## 1. Decisions already locked (do not relitigate without the user)

1. **Separate repo + `upstream` sync.** `origin` = this repo; `upstream` = `maludb-core` (the
   PostgreSQL source) and is the **sync channel**. Shared contract = spec/data-model, not code.
2. **Faithful in-DB port.** PL/pgSQL → Oracle PL/SQL packages; C → PL/SQL (see #3).
3. **PL/SQL only — NO Oracle JVM (OJVM).** (Plan §5.) The C functions become PL/SQL using
   `DBMS_CRYPTO` (HS256/HMAC), `UTL_HTTP`, `UTL_FILE`. JWT verify is **HS256-only** in the source.
4. **Migration tool = SQLcl** (primary); **bespoke SQL\*Plus-delegating wrapper** as fallback only
   if a client won't approve SQLcl. (Plan §9.) Tier-1 orchestrator only — **do not** write a SQL
   statement parser / execution engine.
5. **Vector search is external** — excised from the DB. Out of scope: the 5 Python service daemons,
   `mc2dbd`, `third_party/llama.cpp`, and the vector C (`ann`/`topk`/`vector`). (Plan §2.)
6. **In scope:** in-DB layer (PL/pgSQL + 5 non-vector C files → PL/SQL) **and** the 4 client drivers.

## 2. DO NOT

- Do **not** enable/require OJVM. - Do **not** build a SQL parser/execution engine (use SQL\*Plus/SQLcl).
- Do **not** add a third-party migration tool other than SQLcl (client-approval constraint).
- Do **not** push to `upstream` (push is disabled by design; it's read-only / PostgreSQL).
- Do **not** "fix" the Postgres extension files as if they were the deliverable — they are the
  porting baseline. New Oracle artifacts go in new locations (e.g. `oracle/` — agree the layout first).

## 3. First steps on the RHEL + Oracle 19c box (Phase 0)

A fresh clone has `origin` only. **Re-establish the sync remote first:**

```bash
git remote add upstream https://github.com/maludb/maludb-core.git
git remote set-url --push upstream DISABLED_use_origin   # safety: never push to PostgreSQL repo
git remote -v        # expect: origin=maludb-oracle19c-core, upstream=maludb-core (push DISABLED)
git fetch upstream   # confirm the sync channel works
```

Then verify the toolchain (commands to actually run and confirm):

```bash
cat /etc/redhat-release          # confirm RHEL version
sqlplus -v                       # SQL*Plus present (ships with Oracle) — fallback executor
sql -v                           # SQLcl present? if not, install it (primary migration tool)
java -version                    # JDK present for SQLcl
# connectivity smoke test (adjust connect string):
echo "select banner from v\$version where rownum=1;" | sqlplus -s <user>/<pwd>@<service>
```

Phase 0 deliverables (see plan §6):
- Stand up a dev schema/user for the port; install **utPLSQL** (test framework).
- Land the sync tooling: `scripts/sync-upstream.sh` (drift report), `docs/UPSTREAM_SYNC.md`
  (last-synced upstream commit ledger), and the scheduled drift-check GitHub Action.
- Agree the Oracle source layout (proposed: `oracle/sql/`, `oracle/packages/`, `oracle/migrations/`).
- Begin Phase 1: DDL/type mapping (plan §5 table) + vector excision; establish the JSON-in-CLOB
  and collection conventions and the two foundational helper packages (JSON + collections) early.

## 4. Open questions to resolve with the user/client (carry forward)

- External vector seam: integration contract (sync call vs queue; embedding lifecycle owner)?
- Asymmetric JWT roadmap: RS256/ES256 coming upstream, and must it be **in-DB** (else external tier)?
- `secret` resolver: is the **`file://`** path used in production, or **`https://`** only?
- Is outbound **`UTL_HTTP`** from the DB permitted in the target environment (for the secret resolver)?

## 5. Sync workflow reminder (the "kept in sync" requirement)

`git fetch upstream` → diff contract files since last synced ref (`requirements.md`,
`DATABASE_STRUCTURE.md`, `SVPOR_ERD.md`, `design-notes.md`, `end-to-end.md`, and `sql/` intent) →
port the equivalent PL/SQL → re-baseline affected tests → record the synced commit in
`docs/UPSTREAM_SYNC.md`. Automate steps 1–2 in `scripts/sync-upstream.sh` (Phase 0).
