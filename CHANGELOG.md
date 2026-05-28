# Changelog

All notable changes to MaluDB land here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); MaluDB
versions correspond to the extension migration chain
(`maludb_core--X.Y--X.Z.sql`) plus a release tag.

## Unreleased

The extension default_version advances to 0.80.3, adding search-path-safe
schema-local facades for editing an existing typed, dated subject<->subject
relationship: `maludb_subject_relationship_close(p_relationship_id, p_valid_to
DEFAULT now())` (expire now or at a chosen date),
`maludb_subject_relationship_delete(p_relationship_id)` (for relationships
entered by mistake), and `maludb_subject_relationship_set_type(p_relationship_id,
p_relationship_type)` (edit the type). All three are SECURITY INVOKER with a
pinned `search_path = <schema>, maludb_core, pg_temp` (matching the
`maludb_register_episode` and `maludb_svpor_relationship_create` pattern), so
the API can call them without `SET LOCAL search_path` while writes stay
tenant-owned (`current_schema()` + RLS). The writable `maludb_subject_relationship`
view continues to work too -- these facades are a parallel API path, not a
replacement. The facades write directly to
`maludb_core.malu$svpor_subject_relationship_edge` (executor already has CRUD;
RLS scopes by `owner_schema = current_schema()`) rather than wrapping a
separate core helper -- the 0.79.0 consolidation deliberately dropped the
`close`/`delete`/`list`/`add_svpor_relationship_edge` helpers in favor of the
view, and resurrecting them would fight that decision. Existing schemas pick
up the facades by re-running `maludb_core.enable_memory_schema()`.

The extension default_version advances to 0.80.2, closing the last two
API-project requests. `register_svpor_relationship` (behind
`maludb_svpor_relationship_create`) is now idempotent and FK-validates its
endpoints: a repeated `(source, target, relationship_type)` link in the same
tenant returns the existing edge id instead of inserting a duplicate, and a
dangling subject/verb id raises `foreign_key_violation` rather than recording
an orphan edge (the polymorphic edge table has no real FK to the SVPOR
tables) -- so the API no longer has to dedupe or existence-check itself. A new
schema-local `maludb_register_episode(...)` facade wraps
`maludb_core.register_episode` so the `/v1/episodes` endpoint can drop its
`SET LOCAL search_path`; it is SECURITY INVOKER with a pinned
`search_path = <schema>, maludb_core, pg_temp` (not security definer), so
episodes stay tenant-owned (`current_schema()` + RLS resolve to the caller's
schema, exactly as the direct call does today). The
`register_svpor_relationship` fix applies immediately; existing schemas pick
up `maludb_register_episode` by re-running `maludb_core.enable_memory_schema()`.
This release also hardens the 0.80.1 idempotency fix: 0.80.1 dropped
`maludb_subject`/`maludb_memory`/`maludb_skill`/`maludb_document` unconditionally
at the start of `enable_memory_schema`, which silently destroyed a tenant's own
same-named view and defeated the "refuse to replace an unmanaged view" guard.
Those four views are now dropped only when extension-managed (recorded in
`malu$enabled_schema_object`), so re-enable stays idempotent while an unmanaged
name collision is still refused.

The extension default_version advances to 0.80.1, fixing an
`enable_memory_schema()` idempotency regression from 0.80.0. The 0.80
facade widened several views (`maludb_subject`/`maludb_project`/
`maludb_person`/`maludb_stakeholder`, `maludb_memory`, `maludb_skill`,
`maludb_document`) by re-creating them after the base builders, so a
second enable made the base builder try to shrink an already-widened view
and failed with `cannot drop columns from view`. enable_memory_schema now
drops those views up front (inside its transaction) so the base builders
recreate them cleanly and the 0.80 facade re-widens; re-enabling a schema
is idempotent again.

The extension default_version advances to 0.80.0 for REST API enablement.
Bug fixes: the six `_payload_validate_*` triggers now pin their search_path,
so `maludb_memory`/`maludb_fact`/`maludb_claim`/`maludb_episode`/
`maludb_source_package`/`maludb_memory_detail` are writable from any
connection (previously failed with `validate_payload ... does not exist`
when `maludb_core` was off the caller's search_path); and the document
inner helpers (`_upload_document_for_schema`, `_insert_document_svpor_hints_for_schema`)
are now granted to the memory roles, so `maludb_quick_add_note` /
`maludb_upload_document` work for tenants. New schema-local helpers:
`maludb_subject_verb_link` / `maludb_subject_verb_unlink` (link owns the
namespace + embedding defaults), `maludb_svpor_relationship_delete`,
`maludb_pool_remove_named_member`, and `maludb_project_archive` /
`maludb_project_unarchive` (backed by a new `archived_at` on subjects,
exposed on `maludb_subject`/`maludb_project`). New columns surface notes
issue-state (`issue_closed_at` on `maludb_memory`), skill body
(`markdown` on `maludb_skill`), and document body (`body_text` read column
on `maludb_document`, from the source package). Existing schemas pick up
the new helpers and widened views by re-running
`maludb_core.enable_memory_schema()`.

The extension default_version advances to 0.79.0, consolidating subject
relationships into a single object. A relationship is now one directed,
typed, dated row, surfaced as the `maludb_subject_relationship` facade view:
`relationship_type` is free text and required, and `valid_from`/`valid_to`
carry the date range — so "Mary is 'project manager of' Zozocal from
2025-01-01 until 2025-12-31" is a single `INSERT`, and "valid as of T" is a
single date-range `SELECT` (or the `maludb_subject_relationships(subject,
as_of, type, direction)` reader). The 0.78.0 split is removed: the symmetric
`maludb_related_subject` view + table + `add`/`list`/`delete` helpers, the
`malu$svpor_relationship_type` catalog, and the header auto-sync trigger are
all dropped (no data migration of the symmetric pairs). Directed rows recorded
under 0.78.0 are preserved; only the catalog foreign key is removed. Existing
schemas pick up the consolidated facade by re-running
`maludb_core.enable_memory_schema()`.

The extension default_version advances to 0.78.0 for typed, temporal subject
relationships. A new tenant-scoped `malu$svpor_relationship_type` catalog holds
the controlled vocabulary of relationship types (with optional inverse names),
and `malu$svpor_subject_relationship_edge` records directed, time-bounded edges
between subjects — e.g. "Mary was 'project manager of' Zozocal from 2025-01-01
until 2025-12-31" — using a generated `tstzrange` and a GiST overlap-exclusion
constraint. The existing `malu$svpor_subject_relationship` pair gains a
`relationship_type` column that a trigger keeps in sync with the pair's
currently-valid edge. Schema enablement adds the `maludb_relationship_type` and
`maludb_related_subject_edge` facade views plus `maludb_relationship_type_add`,
`maludb_related_subject_edge_add`, `maludb_related_subject_edges` (point-in-time
reads via `p_as_of`), `maludb_related_subject_edge_close`, and
`maludb_related_subject_edge_delete`; `maludb_related_subject` now also exposes
`relationship_type`. Existing schemas pick up the new facades by re-running
`maludb_core.enable_memory_schema()`.

The extension default_version advances to 0.74.0 for PostgreSQL-style user
onboarding. New convenience roles let operators grant access with normal role
membership: `maludb_read` for schema-local read access, `maludb_user` for normal
read/write use, and `maludb_admin` for admin delegation. Fresh installs also get
a guarded short `maludb` alias when that role name is not already occupied by an
operator login. The new `maludb_core.grant_memory_access()` helper and
`sql/grant-memory-access.sql` script provide scripted onboarding.

## v4.1.0 — 2026-05-19

The extension default_version advances to 0.73.0 for skill discovery.
Schema-local memory enablement now adds skill discovery facades and wrappers for
manual subject, verb, and keyword tagging; public skills in `maludb_public`;
and find/get/fork APIs exposed as SQL wrappers and MC2DB `skill.find`,
`skill.get`, and `skill.fork` tools.

## v4.0.0 — 2026-05-15

Version 4 GA plus schema memory enablement. The extension default_version
advances to 0.72.0 so ordinary PostgreSQL schemas can explicitly opt in to
schema-local MaluDB memory facades with `maludb_core.enable_memory_schema()`.
The V4 surface remains governed by the fresh-VM acceptance gate and keeps the
release artefacts aligned for public install testing.

The GA surface includes:

* PageIndex and ChatIndex as governed memory surfaces over the
  Verbatim Source Archive.
* SQL, MC2DB, REST, CLI, and C / Python / Node.js / PHP SDK access
  to the V4 tree build, append/list, ask, and supersession flows.
* Schema-local facades for subjects, verbs, memories, documents, raw
  ingest, vector search, memory pools, prompt/model-session objects,
  skills, workflow objects, and MCP catalog objects backed by shared
  `maludb_core` storage.
* `scripts/maludb-fieldtest-v4`, `bench/v4/run-bench`, and
  `docs/v4/acceptance-matrix.md` as the acceptance artefacts for
  the V4 plan.

## v4.0.0-rc.1 — 2026-05-14

V4 release candidate. No new migration; default_version stays at
0.71.0. Three new deliverables prepare the project for the
fresh-VM field test that gates v4.0.0 GA:

* **`scripts/maludb-fieldtest-v4`** — 28-case live-DB walkthrough
  mirroring the v3 cadence. Asserts the catalog + queue + audit
  surface for V4-PAGEINDEX-01..03, V4-CHATINDEX-01..02 against
  contrib_regression; spot-checks the alpha.5 MC2DB tools + the
  alpha.6 REST endpoint catalog; imports the beta.1 CLI command
  modules and Python SDK to catch wiring regressions. 28/28
  PASS on the build host today.

* **`bench/v4/run-bench`** + fixtures
  (`bench/v4/fixtures/reference.md`, `chat.jsonl`) — recall +
  latency baselines for the deterministic-`overlap` descent
  strategy across 5 markdown queries + 3 chat queries. Today
  on the build host: page_index recall=1.00 p95≈12 ms;
  chat_index recall=1.00 p95≈10 ms. The harness is re-runnable
  with `--choice llm --model-alias <id>` once the LLM strategy
  lands post-GA.

* **`docs/v4/acceptance-matrix.md`** — single-page mapping of
  the eleven plan §12 acceptance criteria to the test / check
  artefact that proves each one, with current status. Five
  criteria are green-and-done; two are green-for-the-API but
  bench-deferred; two are deferred per plan §10 (debian
  packaging for Python services; in-house PDF parser); one
  awaits the fresh-VM field test (the v4.0.0 GA gate proper).

Nothing in the extension itself changed at rc.1 — this tag exists
to mark the point where every V4 surface has a runnable acceptance
artefact pointing at it.

## v4.0.0-beta.1 — 2026-05-14

First Version 4 beta. Closes V4-CLI-01 + V4-SDK-01 — no new SQL
catalog (default_version stays at 0.71.0). PageIndex and ChatIndex
are now reachable through every external surface MaluDB supports:
SQL, MC2DB tools, REST endpoints, the first-party CLI, and typed
wrappers in all four SDK languages.

V4-CLI-01

* `maludb pageindex` subcommand family: `build`, `list`, `show`,
  `ask`, `supersede`. Each one drives the corresponding SQL surface
  introduced in alpha.1..alpha.6 (source_package_promote_to_page_index,
  pageindex_list_trees, pageindex_get_tree, retrieve_with_envelope_tree,
  page_index_tree_supersede). Honours the existing `--format`
  `text`/`json` switch on the global CLI.
* `maludb chatindex` subcommand family: `build`, `append`, `ask`,
  `list`. Append reads a JSON-Lines file (one message object per
  line) and feeds it to `chat_index_append_messages`.
* New command modules: `cli/maludb/src/maludb_cli/commands/pageindex.py`
  and `.../commands/chatindex.py`. Both are registered in
  `__main__.py` alongside the existing 18 subcommand families.

V4-SDK-01

Typed wrappers added to all four shipped SDKs:

* **Python** (`drivers/python/src/maludb/client.py`) — eleven new
  methods on `MaluDBClient`: `pageindex_build`, `pageindex_list`,
  `pageindex_get`, `pageindex_ask`, `pageindex_supersede`;
  `chatindex_build`, `chatindex_append`, `chatindex_list`,
  `chatindex_ask`. Same `_scalar` / `_rows` shape as the V3 methods.
* **Node.js** (`drivers/nodejs/src/client.ts`) — same method set on
  `MaluDBClient`, named `pageindexBuild` / `chatindexAppend` etc.
  Strong-typed argument objects (`{sourcePackageId, parserKind?, …}`)
  matching the project's existing TypeScript convention.
* **PHP** (`drivers/php/src/Client.php`) — same method set with
  PHP-idiomatic naming and PDO parameter binding (`CAST(:opts AS jsonb)`
  for JSONB args).
* **C** (`drivers/c/include/maludb.h` + `drivers/c/src/maludb.c`) —
  six new `MALUDB_API` functions: `maludb_pageindex_build`,
  `maludb_pageindex_supersede`, `maludb_pageindex_ask`,
  `maludb_chatindex_build`, `maludb_chatindex_append`,
  `maludb_chatindex_ask`. Ask functions return heap-allocated
  JSON strings (same idiom as `maludb_node_accept` / `maludb_skill_step_execution`);
  build functions return `int64_t` tree ids; append returns int.

V4 surface complete

| Surface       | PageIndex | ChatIndex |
|---------------|-----------|-----------|
| SQL           | ✓ alpha.1..alpha.3 | ✓ alpha.4 |
| MC2DB tools   | ✓ alpha.3 + alpha.5 (tree_summary) | ✓ alpha.5 |
| REST          | ✓ alpha.6 (4 endpoints) | ✓ alpha.6 (4 endpoints) |
| CLI           | ✓ beta.1 (5 subcommands) | ✓ beta.1 (4 subcommands) |
| SDK (C/Py/Node/PHP) | ✓ beta.1 | ✓ beta.1 |

Doc-consistency rolls forward: control / README / user-manual /
CHANGELOG all agree on 0.71.0 / v4.0.0-beta.1. 74/74 pg_regress
green on PG 17 (no new test files at beta.1; CLI smoke + SDK smoke
tests run in their own test harnesses against the live extension).

Next: rc.1 — V4 acceptance suite + bench fixtures published; v4.0.0
follows after a fresh-VM field test.

## v4.0.0-alpha.6 — 2026-05-14

Sixth Version 4 alpha. Closes V4-REST-01. Eight new REST endpoints
registered in `malu$rest_endpoint` via `rest_register_endpoint`,
covering build / list / get / ask / append for both V4 trees. All
share the same V3-AUTH-01 token model and arg_schema contract as
the existing v3 endpoints, so the maludb-restd gateway routes them
without code changes.

Endpoints (all under `/v4`):

* **POST /v4/pageindex/build** — handler
  `source_package_promote_to_page_index(bigint,text,bigint,bigint,jsonb)`,
  scope `pageindex.write`, risk `state_changing`.
* **GET /v4/pageindex/trees** — handler `pageindex_list_trees(text,integer)`,
  scope `pageindex.read`, query params `p_build_status`, `p_limit`.
* **GET /v4/pageindex/trees/:tree_id** — handler
  `pageindex_get_tree(bigint)`, scope `pageindex.read`, path param
  `p_tree_id`.
* **POST /v4/pageindex/ask** — handler
  `retrieve_with_envelope_tree(text,bigint,jsonb,integer)`, scopes
  `pageindex.read` + `retrieval.read`.
* **POST /v4/chatindex/build** — handler
  `source_package_promote_to_chat_index(bigint,bigint,bigint,integer,jsonb)`,
  scope `chatindex.write`.
* **POST /v4/chatindex/append** — handler
  `chat_index_append_messages(bigint,jsonb)`, scope `chatindex.write`.
  Larger `max_input_bytes` (4 MiB) to accommodate batched message
  appends.
* **GET /v4/chatindex/trees** — handler
  `chatindex_list_trees(text,integer)`, scope `chatindex.read`.
* **POST /v4/chatindex/ask** — handler
  `retrieve_with_envelope_chat_tree(text,bigint,jsonb,integer)`,
  scopes `chatindex.read` + `retrieval.read`.

Three new SETOF helpers (`pageindex_list_trees`,
`pageindex_get_tree`, `chatindex_list_trees`) back the GET
endpoints. They return RLS-filtered rows from the catalog tables
so the REST surface inherits the same tenancy posture as direct
SQL callers.

The migration-local `_v3_api_arg` helper is recreated at the top of
the migration and dropped at the end, same pattern as V3-API-02 in
the 0.61.0 → 0.62.0 migration.

Out of scope at this tag: CLI subcommands (V4-CLI-01) and SDK
wrappers (V4-SDK-01); both land at beta.1. OpenAPI generation is
already driven by the catalog's `arg_schema` column, so the V4
endpoints inherit auto-documentation through V3-API-02's existing
spec generator.

## v4.0.0-alpha.5 — 2026-05-14

Fifth Version 4 alpha. Closes V4-MC2DB-01 by completing the MC2DB
tool surface for both V4 trees. Five new tools land on the
`maludb.advanced` server (count rises 22 → 27):

* **maludb.chatindex.build** — state_changing. Wraps
  `source_package_promote_to_chat_index`. Returns `tree_id` +
  `build_status='pending'`.
* **maludb.chatindex.append** — state_changing. Wraps
  `chat_index_append_messages`. Returns one record per input
  message with `mdo_id` + `idempotent_hit`.
* **maludb.chatindex.ask** — read_only. Wraps the new
  `retrieve_with_envelope_chat_tree`. Returns the descent
  terminus (`leaf_mdo_id`, `leaf_title`, `leaf_summary`,
  `depth_reached`) plus the `envelope_id` so callers can inspect
  the trail via `retrieve_envelope_debug`.
* **maludb.chatindex.list** — read_only. Lists chat trees visible
  to the caller, optional `build_status` filter.
* **maludb.pageindex.tree_summary** — read_only. Returns the
  root + first-level node titles/summaries for a PageIndex tree.

Supporting SQL helpers added (no new catalog tables):

* `chat_tree_descent_retrieve(envelope_id, chat_tree_id, options)`
  mirrors the PageIndex `tree_descent_retrieve` but walks
  chat-tree MDO rows (`chat_index_topic`, `chat_index_message`).
  Same three-stage authz contract, same `'overlap'` default
  choice strategy, same per-step `malu$retrieval_decision_audit`
  and `'retrieval_summary'` ledger coverage. Empty / RLS-hidden
  trees raise `insufficient_privilege`; pending / failed trees
  raise `object_not_in_prerequisite_state`.
* `retrieve_with_envelope_chat_tree(cue_text, chat_tree_id,
  options, limit)` is the packaged operator entrypoint. Opens
  an envelope tagged with `chat_tree_id`, sets the
  `long_chat_recall` intent, invokes the descent, returns the
  terminus + envelope_id.

`expected/advanced_mc2db_tools.out` count assertion bumped 22 →
27; sql/preview_env.sql, sql/metrics_scrape.sql, and their
expected files bumped to `0.70.0`.

Out of scope at this tag: REST endpoints registered in
`malu$rest_endpoint` (V4-REST-01 ships at alpha.6), CLI
subcommands (V4-CLI-01, beta.1), and SDK wrappers (V4-SDK-01,
beta.1). Builder-worker branching on parser_kind for
'conversation' sources is also still a follow-up.

## v4.0.0-alpha.4 — 2026-05-14

Fourth Version 4 alpha. Closes the ChatIndex track: chat trees are
buildable and the incremental-append surface enforces the upstream
ancestor-only branching rule. PageIndex and ChatIndex now have
catalog parity.

* **V4-CHATINDEX-01** (Stage 19, migration `0.67.0 → 0.68.0`) — chat
  tree catalog. `malu$chat_index_tree` (mirrors `malu$page_index_tree`
  plus `current_node_mdo_id` load-bearing pointer, `max_children`,
  `sub_node_count`). `malu$memory_detail_object` gains a sibling
  `chat_tree_id` FK (separate from the existing `tree_id` so FK
  integrity stays unambiguous per node kind), plus `topic_name`,
  `system_message`, `user_message`, `assistant_message`,
  `message_index` columns. The shape check now distinguishes per
  `mdo_kind`: `page_index_node` rows require `tree_id` only;
  `chat_index_topic` / `chat_index_message` rows require
  `chat_tree_id` only; `memory_detail` rows have neither. The
  Stage-2 anchor check is relaxed once more to admit
  `chat_tree_id` as a valid anchor. `malu$derivation_ledger`
  admits `'chat_index_tree'`, `'chat_index_topic'`,
  `'chat_index_message'`; `malu$relationship_edge` admits
  `'chat_index_tree'` so supersession edges connect through the
  existing surface. SQL APIs mirror PageIndex:
  `chat_index_tree_register` / `_mark_building` / `_mark_ready` /
  `_mark_failed` / `_supersede`, `chat_index_record_topic` (atomic
  MDO + ledger for an internal topic node), `chat_index_record_message`
  (atomic insert for a leaf message node with the system / user /
  assistant trio + `message_index`),
  `source_package_promote_to_chat_index` (auto-registers the
  `chatindex_build` V3-QUEUE-01 queue, enqueues a build job).

* **V4-CHATINDEX-02** (Stage 19, migration `0.68.0 → 0.69.0`) —
  incremental append. `malu$chat_index_append_audit` records every
  call's decision breadcrumbs (range, idempotent_hits,
  `opened_new_topic`, `ancestor_branch_used`,
  `branched_from_mdo_id`, `decision_reason`).
  `chat_index_append_messages(tree_id, messages jsonb)` is the
  entry point. Each message can carry an optional `topic_branch`:
    * omitted → extend the current topic (or auto-open a root
      topic if the tree is empty).
    * `{"new": "X"}` → open a new topic from the current node;
      per upstream semantics the new topic is a sibling of the
      from-node, i.e. `new_topic.parent = parent_of(from)`.
    * `{"from_ancestor_mdo_id": N, "new": "X"}` → branch from a
      named ancestor. The ancestor MUST be the current node or
      one of its ancestors (verified via a recursive walk of the
      ancestor chain); a request to branch from an unrelated
      subtree raises `invalid_parameter_value`.
  Idempotency: a duplicate `(chat_tree_id, message_index)` returns
  the existing `mdo_id` without inserting a second row and bumps
  `idempotent_hits` in the audit row. Concurrent appends on the
  same tree serialize on a `SELECT … FOR UPDATE` of the header
  row (plan §11.5). `chat_index_close_topic(tree_id,
  topic_node_mdo_id)` is an admin-only override that clears the
  `current_node_mdo_id` pointer when the current node is inside
  the given topic's subtree.

Tests
* `sql/chat_index_catalog.sql` — 7 cases (register / status
  transitions / topic + message recording / shape constraint /
  ledger admission / supersession / RLS isolation).
* `sql/chat_index_append.sql` — 7 cases (auto-open root /
  extend-current / branch-from-current / branch-from-ancestor /
  non-ancestor rejection / idempotency / cross-tenant rejection).
* `expected/load.out`, `expected/catalog.out`,
  `expected/metrics_scrape.out`, `expected/preview_env.out`,
  `sql/metrics_scrape.sql`, `sql/preview_env.sql` bumped to
  `0.69.0`. `malu$` table count rises 123 → 125 (chat tree,
  append audit).

Out of scope at this tag: PageIndex/ChatIndex MC2DB symmetry
(only PageIndex got the alpha.3 surface; ChatIndex MC2DB tools
land with V4-MC2DB-01 full surface), CLI subcommands (V4-CLI-01),
REST endpoints (V4-REST-01), SDK wrappers (V4-SDK-01), and live
LLM-driven topic-opening decisions (the `topic_branch` field is
caller-supplied; the model gateway hook is post-alpha.4 work).

## v4.0.0-alpha.3 — 2026-05-14

Third Version 4 alpha. Closes the retrieval-planner descent path so
PageIndex trees are reachable through the public retrieval surface.

* **V4-PAGEINDEX-03** (Stage 18, migration `0.66.0 → 0.67.0`) —
  retrieval-planner descent. `malu$retrieval_envelope` gains
  `tree_descent_used`, `tree_descent_path`, and
  `tree_descent_authz_rejections` debug columns.
  `malu$retrieval_decision_audit.stage` admits `'tree_descent'` as a
  fourth value alongside `planning`/`expansion`/`assembly`.
  `malu$derivation_ledger.derived_object_type` admits
  `'retrieval_summary'` so every LLM-driven (or
  deterministic-stand-in) child choice has ledger coverage.
  `classify_intent` extended with two cue/hint patterns:
  `'structured_doc_qa'` (cue mentions a `tree_id` /
  `page_index_tree_id` hint or `page_index_node` object_type) and
  `'long_chat_recall'` (cue mentions a `chat_tree_id` /
  `chat_index_tree_id` hint or `chat_index_topic` /
  `chat_index_message` object_type). `select_search_paths` returns
  a `tree_descent` strategy for both. The descent runs one level
  at a time:
    1. Planning fetches the tree row through RLS (hidden trees raise
       `insufficient_privilege`; pending / failed trees raise
       `object_not_in_prerequisite_state`).
    2. Expansion fetches child MDO rows through RLS — the candidate
       set the choice strategy sees IS the authz-filtered set.
    3. Choice picks the highest-scoring child by cue-token overlap
       against `title + summary` (default `'overlap'` strategy).
       `'first'` strategy reserved for tests; `'llm'` strategy
       reserved for a future maludb_modeld wiring.
    4. The chosen child is re-checked through RLS before traversal
       (TOCTOU defense); a rejected re-check bumps
       `tree_descent_authz_rejections`.
    5. Each step writes a `malu$retrieval_decision_audit` row with
       `stage='tree_descent'` and a `malu$derivation_ledger` entry
       of kind `'retrieval_summary'`.
  Depth caps at `descent_options.max_depth` (default 6 per plan
  §11.2). `retrieve_with_envelope_tree(cue_text, tree_id, options)`
  is the packaged operator entrypoint; `tree_descent_retrieve` is
  the worker-facing call.

* **`tree_descent_prompt_template_v1`** seeded informationally in
  `malu$prompt_template`. The actual LLM call goes through the
  future `'llm'` choice strategy; the deterministic-overlap default
  is what runs today.

* **First PageIndex MC2DB surface** — three new tools on the
  existing `maludb.advanced` server: `maludb.pageindex.build`
  (state-changing, wraps `source_package_promote_to_page_index`),
  `maludb.pageindex.list` (read-only, filtered by `build_status`
  optionally), and `maludb.pageindex.ask` (read-only, wraps
  `retrieve_with_envelope_tree`). The tool count on
  `maludb.advanced` rises from 19 to 22.

Tests: `sql/page_index_descent.sql` (7 cases — intent classification,
end-to-end descent, decision-audit + ledger coverage, envelope trail,
pending-tree rejection, RLS cross-tenant rejection, supersession
during in-flight descent). `expected/advanced_mc2db_tools.out` count
bumped to 22.

Out of scope at this tag: live `maludb_modeld` integration for the
`'llm'` choice strategy (operators can wire it post-alpha.3 by
implementing a SECURITY DEFINER hook), ChatIndex catalog (V4-CHATINDEX-01),
PageIndex CLI subcommands (the MC2DB surface is the first cut; the
`maludb` CLI subcommand family lands with V4-CLI-01 later).

## v4.0.0-alpha.2 — 2026-05-14

Second Version 4 alpha. Two tickets land plus the new
`maludb-pageindexd` service binary.

* **V4-PARSER-01** (Stage 17, no migration) — pluggable
  `PageIndexParser` Protocol in `services/maludb-pageindexd/`. Three
  bundled parsers: `pypdf` for PDFs (BSD-3-Clause, system package
  `python3-pypdf`), stdlib-only markdown for ATX-style `#` headers
  with fenced-code-block awareness, plain-text fallback. The parser
  registry is keyed on both `parser_kind` (the
  `malu$page_index_tree.parser_kind` enum) and media type. AGPL
  parsers (PyMuPDF) remain operator-pluggable but are not bundled.
  Tests: `test_pypdf_parser.py` (4 cases: outlined / no-outline /
  single-page / determinism), `test_markdown_parser.py` (4 cases:
  hierarchy / no-headers / fenced-code / text round-trip),
  `test_plain_text_parser.py` (3 cases).

* **V4-PAGEINDEX-02** (Stage 17, migration `0.65.0 → 0.66.0`) —
  promotion path + builder substrate. New catalog table
  `malu$structure_pass_audit` records every deterministic parse run
  with its `parser_kind`, `parser_version`, outline / leaf counts,
  `deterministic_inputs_hash`, and outcome. New SQL helpers
  `source_package_promote_to_page_index` (registers tree, auto-
  registers `pageindex_build` V3 queue, enqueues a job),
  `page_index_record_structure_pass`, `page_index_record_node`
  (atomic MDO + Derivation Ledger insert per call), and
  `page_index_chunker_handoff` (returns leaf set in document order
  for the V3-EMBED-01 chunker). `embedding_enqueue` extended with
  the optional `p_precomputed_boundaries_from_tree_id` argument
  and `malu$embedding_job.precomputed_boundaries_from_tree_id`
  column — chunker callers that supply this consume leaf ranges
  from the tree handoff instead of running their own splitter.
  Tests: `sql/page_index_promote.sql` (6 cases: promote / re-promote
  + supersession / structure-pass audit / determinism / RLS cross-
  tenant / atomicity).

* **`maludb-pageindexd` v0.1.0** — new Python service. Polls the
  `pageindex_build` queue, runs the deterministic structure pass,
  calls the model gateway (default: `LocalDeterministicSummarizer`
  for offline tests; an HTTP `maludb_modeld` client lands later)
  for per-node summaries, writes MDO + ledger rows transactionally
  per node, transitions the tree to `ready`. Single-threaded per
  tree per worker (plan §10.4 v1 posture). Service-level tests in
  `services/maludb-pageindexd/tests/test_builder.py` cover four
  cases against a live DB: end-to-end build, idempotent retry,
  summarizer-failure → tree `failed`, structure-pass determinism
  across re-promotion. Gated behind `MALUDB_PAGEINDEXD_TEST_DB=1`
  so they don't run in pg_regress.

V3-EMBED-01 backward compatibility: callers passing the original six
`embedding_enqueue` arguments are unaffected — the seventh defaults
to NULL.

Out of scope at this tag: PageIndex retrieval planner descent
(V4-PAGEINDEX-03), MC2DB / REST / CLI / SDK surfaces, and any
ChatIndex catalog.

## v4.0.0-alpha.1 — 2026-05-14

First Version 4 alpha. Opens the PageIndex / ChatIndex track per
[`version4-pageindex-plan.md`](version4-pageindex-plan.md). Two
tickets land:

* **V4-DOC-01** (Stage 16) — adds §1.6 *Version 4 — PageIndex and
  ChatIndex* and §9 Stages 16+ to `requirements.md`; adds
  `version4-pageindex-plan.md` to the authoritative-documents list
  in `CLAUDE.md` and `AGENTS.md`; brings `AGENTS.md` to parity with
  `CLAUDE.md` after a long drift; extends
  `scripts/maludb-check-doc-consistency` to recognize V4 as the
  current track; ships the conceptual brief at
  `docs/pageindex/PageIndex_Technology_Guide.md`.
* **V4-PAGEINDEX-01** (Stage 17) — migration `0.64.0 → 0.65.0`
  introduces `malu$page_index_tree`, the `mdo_kind` discriminator
  on `malu$memory_detail_object` (defaults to `'memory_detail'` so
  existing callers behave unchanged), new `tree_id`, `node_kind`,
  `summary` columns (`title` is reused from Stage 2), the
  `malu$mdo_tree_node_shape_check` composite constraint, a
  relaxation of the Stage-2 anchor check to admit `tree_id` as an
  anchor kind, derivation-ledger admission for
  `'page_index_tree'` / `'page_index_node'`, relationship-edge
  admission for `'page_index_tree'`, and SQL APIs
  `page_index_tree_register` / `_mark_building` / `_mark_ready` /
  `_mark_failed` / `_supersede`. RLS on the new table tracks the
  V3 RLS-on-base-tables practice (no MALU_USER_* tier views — see
  `version4-pageindex-plan.md` §10.11 for the deferred tier-view
  decision).

Migration rebase note: the original V4 plan reserved migrations
`0.57.0`–`0.62.0`. The v3.1.0 follow-up consumed `0.57.0` through
`0.64.0`, so the V4 plan §4.1 was rebased to `0.64.0`–`0.69.0`.
Plan §V4-PAGEINDEX-01 was also revised to drop a false claim that
`MALU_USER_MEMORY_DETAIL_OBJECT` tier views already exist — they
don't; V3 ships RLS-on-base-tables.

Out of scope at this tag: promotion path (`source_package_promote_to_page_index`),
builder worker (`services/maludb-pageindexd/`), structure-pass
audit (`malu$structure_pass_audit`), retrieval-planner descent,
and any ChatIndex surface. Those land in subsequent V4 alphas.

## v3.1.0 — 2026-05-14

Post-`v3.0.0` GA feature release. Closes every follow-up tracked in
the `v3_scope` memory's "V3 follow-ups" list. Extension advances
through eight migrations from `0.57.0` to `0.64.0`. No breaking
changes; everything is additive or behind opt-in switches.

Headline:

* C-backed HMAC + JWT (HS256) verifier on the auth hot path.
* C-backed file:// / https:// secret resolver.
* S3 storage adapter with SigV4 + pre-signed URLs (stdlib, no boto3).
* `maludb-logsd` log-drain forwarder service.
* WebSocket transport alongside SSE in `maludb-realtimed`.
* Curated ~20-endpoint REST catalog with typed-arg dispatch.
* Three new CLI subcommand families (env / log-drain / backup).
* Ledger `embedding` kind, presence TTL + sweeper, `emit_event`
  in Stage 2/5/6 `register_*` helpers.
* Vector benchmark harness + reproducible measurement workflow.
* pgmq / pg_cron adoption decision recorded (pg_cron in, pgmq out).
* PgBouncer + HAProxy operator sample configs.

Gate matrix on the dev host at tag time:

| Suite | Result |
|---|---|
| `make installcheck` (PG 17) | **69/69** |
| `scripts/maludb-fieldtest-v3` | **30 pass / 0 fail / 0 warn** |
| `services/maludb-restd` smoke | **9/9** |
| `services/maludb-realtimed` smoke | **6/6** |
| `services/maludb-logsd` smoke | **4/4** |
| `cli/maludb` smoke | **15/15** |
| `scripts/maludb-check-doc-consistency` | **OK** at default_version 0.64.0 |

See `docs/v3/release-3.1.0.md` for the per-stage breakdown +
explicit follow-ups deferred past `v3.1.0`.

### Added
- **v3.1 Stage A — V3-EMBED-02** — Ledger `embedding` kind. The
  Stage 2 `malu$derivation_ledger` CHECK constraint now admits
  `embedding` as a first-class derived-object kind, joining
  `source_package / claim / fact / memory / episode_object /
  memory_detail_object / relationship_edge`. `embedding_record_output`
  inserts ledger rows as `embedding` directly; existing rows that
  were placeholdered as `memory_detail_object` and point at
  `malu$embedding_output` via the FK are backfilled to `embedding`.
  Migration `0.57.0 → 0.58.0`. Closes the future-migration note in
  `maludb_core--0.51.0--0.52.0.sql`.
- **v3.1 Stage B — V3-REALTIME-02a** — `emit_event` integrated into
  Stage 2 / 5 / 6 `register_*` helpers so realtime subscribers see
  ingest activity without callers having to emit events explicitly.
  Instrumented: `register_source_package`, `register_claim`,
  `register_fact`, `register_memory`, `register_episode`,
  `register_memory_detail`, `register_relationship_edge`,
  `register_skill`, `register_local_node` (the last one already
  emits `audit_event`; now also emits the realtime stream event).
  Migration `0.58.0 → 0.59.0`.
- **v3.1 Stage M — V3-OPS-01** — operator sample configs for the
  load balancer + connection pooler front-ends.
  - `docs/v3/samples/pgbouncer.ini` — transaction-mode pool tuned
    for MaluDB's REST / MC2DB workload. Documents the prepared-
    statement and LISTEN/NOTIFY constraints inline.
  - `docs/v3/samples/haproxy.cfg` — two TCP frontends: `:5432`
    writes + realtime LISTEN to the current primary, `:5433` reads
    to any healthy replica with the primary as last-resort backup.
    Explicitly NOT an HA controller — promotion stays with the
    operator's chosen Patroni / repmgr / Stolon stack.
  - `docs/v3/samples/README.md` — operator guide; what's
    intentionally NOT in the samples (failover, TLS termination,
    V3-AUTH-01 token-catalog integration).
  - `docs/v3/read-replicas.md` cross-links the samples.
  - No code change. Extension stays at `0.64.0`. This is the last
    v3.1 stage before the GA tag.
- **v3.1 Stage L — V3-CRON-02 / V3-QUEUE-02** — pgmq + pg_cron
  adoption decision. Docs-only deliverable; closes the
  "future swap target" notes in V3-QUEUE-01 and V3-CRON-01.
  - `docs/v3/pgmq-pgcron-decision.md` records the v3.1 / GA
    posture:
    * `pg_cron` — adopt as an **optional tick driver** for V3-CRON-01.
      `pg_cron` is in PGDG (`postgresql-17-cron` 1.6.7). The
      recommended wiring schedules `SELECT schedule_tick();`
      once a minute via `cron.schedule`; the V3-CRON-01 surface
      stays unchanged. Operators who can't install `pg_cron`
      keep using a systemd timer (sample units inline).
    * `pgmq` — **deferred indefinitely**. Not in PGDG (source build
      only), functional parity with V3-QUEUE-01 already met,
      RLS-scoped tenancy is awkward to preserve on per-queue
      tables. The swap remains a small migration if we ever
      need it (V3-QUEUE-03, conditional).
  - No code change. Extension stays at `0.64.0`.
- **v3.1 Stage K — V3-VEC-02** — vector benchmark harness +
  reproducible measurement workflow. Closes the V3-VEC-01
  follow-up "bench fixtures so recall / latency can be measured
  against a reproducible corpus."
  - `scripts/maludb-bench-vector` — stdlib + psycopg Python script.
    Generates a deterministic L2-normalised corpus + query set
    (configurable seed), inserts them into a fresh compartment, runs
    an exact kNN baseline, and writes the recall summary jsonb into
    `malu$vector_index_status.recall_sample` via `vector_index_record`.
    Operators can trend the recall_sample column over time to catch
    regressions from tuning changes.
  - `sql/vector_bench.sql` (REGRESS grows 68 → 69) exercises the
    catalog round-trip: `vector_index_record` accepts the recall
    jsonb and `vector_index_status` surfaces it.
  - `docs/v3/vector-bench.md` — operator guide. Documents the
    quick-start, reproducibility guarantees, and the runway for the
    remaining vector kinds (`nsw` SQL surface, multilevel
    `hnsw_local` C implementation in V3-VEC-03, pgvector HNSW
    integration via a parallel `vector` column in V3-VEC-04).
  - Multilevel HNSW itself is **explicitly deferred** to V3-VEC-03.
    The catalog enum already accepts `hnsw_local` and
    `hnsw_pgvector`; only the search-path implementation is missing,
    and the bench harness is shaped to slot the alternate top-k
    call in without restructuring.
  - No migration; extension stays at `0.64.0`.
- **v3.1 Stage J — V3-STOR-02** — S3 storage adapter + SigV4
  pre-signed URLs in the CLI. Closes the V3-STOR-01 follow-up.
  - `cli/maludb/src/maludb_cli/s3.py` (~210 LOC) — stdlib-only AWS
    Signature v4 (no boto3): GET / PUT / HEAD plus pre-signed GET.
    `adapter.config.endpoint_url` + `addressing_style` overrides
    let operators point at minio / a local mock without touching
    the signing math.
  - Credentials resolve via `__secret_resolve(secret_ref)`; the
    secret payload is JSON `{access_key, secret_key, session_token?}`.
  - `_adapter_put_bytes` / `_adapter_read_bytes` in
    `commands/source.py` now dispatch to S3 for `kind = 's3'`
    (previously raised `RuntimeError("...follow-up...")`).
  - New CLI subcommand `maludb source signed-url --object-id N
    [--expires-in S]` issues a SigV4 pre-signed GET URL for any
    S3-backed source object. Returns 65 with `signed_url_unsupported`
    on a `local_fs` adapter.
  - Regression: cli/maludb test_smoke gains
    `test_15_s3_signed_url_round_trip` — spins up a stdlib mock S3
    server, registers an `s3` adapter pointing at it, round-trips
    bytes through put + get, asserts the SigV4 `AWS4-HMAC-SHA256`
    Authorization header was observed by the mock, and validates
    the pre-signed URL carries the right query params.
  - No migration; extension stays at `0.64.0`.
- **v3.1 Stage I — V3-SECRET-02** — C-backed `file://` + `https://`
  secret resolver. Closes the V3-SECRET-01 follow-up; replaces the
  `feature_not_supported` stub in `__secret_resolve` for external
  refs.
  - `src/maludb_secret.c` (~280 LOC) exposes
    `maludb_secret_resolve_external(text) RETURNS text` —
    `LANGUAGE C STRICT VOLATILE SECURITY DEFINER`, granted only to
    `maludb_secret_consumer`.
    * `file://<absolute-path>` — path must match the configurable
      allowlist GUC `maludb_core.secret_file_root` (default
      `/etc/maludb/secrets:/var/lib/maludb/secrets`), no `..` / `.`
      segments. File must be a regular file (not a symlink — `lstat`
      + `O_NOFOLLOW`), owned by the postgres OS user, mode `0400` or
      `0600`, and ≤ 1 MiB. Trailing whitespace stripped.
    * `https://<url>` — libcurl GET with `SSL_VERIFYPEER` +
      `SSL_VERIFYHOST` on, no redirect follow, 5 s connect / 10 s
      total timeout, ≤ 1 MiB response. Plain `http://` is rejected
      separately so an accidental downgrade can't bypass TLS.
    * Any other scheme raises `feature_not_supported`.
  - Migration `0.63.0 → 0.64.0`:
    * Extends `malu$secret_use.outcome` CHECK to accept
      `rejected_external_failed` (the row written when the C
      resolver raises mid-resolve).
    * `__secret_resolve` swap: external branch now calls the C
      function inside a `BEGIN … EXCEPTION` block that records a
      rejection row + audit event on failure and re-raises.
  - Makefile: `src/maludb_secret.o` joins OBJS; `SHLIB_LINK` gains
    `-lcurl`.
  - Regression test `sql/c_secret_resolver.sql` (6 sub-tests, REGRESS
    grows 67 → 68): unsupported-scheme reject, plain-http reject,
    file:// outside allowlist, file:// with `..`, file:// relative
    path, and the `__secret_resolve` dispatch path that writes a
    `rejected_external_failed` row.
  - `sql/secret_store.sql` Test 5 updated: pre-Stage-I the stub
    raised `feature_not_supported` for any input. Now we use an
    `s3://` ref so the live C resolver still raises the same
    SQLSTATE (unsupported scheme), preserving the original test
    intent without depending on filesystem mode bits.
- **v3.1 Stage H — V3-AUTH-02** — C-backed HMAC + JWT verifier.
  - `src/maludb_auth.c` (~400 LOC) ships two new SQL-callable C
    functions: `maludb_hmac_sha256(bytea, bytea)` (OpenSSL-backed,
    constant-time output) and `maludb_jwt_verify(text)` (parses,
    looks up the signing key by `kid` via SPI, dispatches by `alg`).
    HS256 is fully implemented end-to-end (HMAC compare uses
    `CRYPTO_memcmp`); RS256 / RS384 / RS512 / ES256 / ES384 / ES512 /
    EdDSA dispatch raises `feature_not_supported` until V3-AUTH-03.
  - Migration `0.62.0 → 0.63.0`:
    * Extends `malu$jwt_signing_key.alg` CHECK to include `HS256`
      and `.kty` CHECK to include `oct` (JWK convention for
      symmetric keys).
    * `__auth_token_hash` is now `RETURN maludb_hmac_sha256(__auth_pepper(), p_plaintext::bytea)`
      — removes the pgcrypto + PL/pgSQL hop from the token-verify
      hot path.
    * `jwt_verify(text)` swapped from a PL/pgSQL stub to
      `LANGUAGE C STABLE STRICT` pointing at `maludb_jwt_verify`.
  - Makefile: new `src/maludb_auth.o` object; `SHLIB_LINK = -lcrypto`
    so OpenSSL HMAC + (future) EVP_DigestVerify are linked.
  - Regression test `sql/c_hmac_jwt.sql` (7 sub-tests, REGRESS list
    grows 66 -> 67): RFC 4231 HMAC vector / hot-path hash length /
    malformed JWT / unknown kid / HS256 happy path + claim row /
    tampered-payload reject / RS256 unsupported-algorithm reject.
  - `sql/auth_token.sql` Test 8 updated to assert the new
    "registered key + RS256 alg -> feature_not_supported" path
    instead of the prior "any input -> stub raise".
- **v3.1 Stage G — V3-REALTIME-02b** — WebSocket transport alongside
  SSE in `maludb-realtimed`. New endpoint `GET /events/ws` performs
  the RFC 6455 handshake (auth verified first so a missing/invalid
  bearer still produces a plain 401, not a half-open WS close), then
  streams the same `event_fetch_batch` payloads as JSON text frames.
  Clients can ack inline by sending a text frame with
  `{"ack": <event_id>}` — no separate POST round-trip needed.
  Implementation lives in a new stdlib-only `ws.py` module (~120
  lines): handshake hash, frame parser/writer, control-frame
  handling. Smoke coverage bumped from 4 to 6: WS round-trip of an
  emitted event + WS 401-without-token. No migration; no extension
  version bump.
- **v3.1 Stage F — V3-API-02** — curated REST endpoint catalog with
  typed-arg dispatch. Closes the V3-API-01b follow-up note.
  - Migration `0.61.0 → 0.62.0` adds `arg_schema jsonb` to
    `malu$rest_endpoint`. Each schema entry declares one PL/pgSQL
    parameter and how the dispatcher should source its value (body
    field, type, required, default). `rest_register_endpoint` gains
    a tail-default `p_arg_schema` argument.
  - 20 curated endpoints seeded across memory model / auth / secret /
    queue / cron / realtime / observability:
    POST /v3/source · /v3/claim · /v3/fact · /v3/memory · /v3/episode ·
    /v3/memory-detail · /v3/relationship · /v3/auth/token/create ·
    /v3/auth/token/revoke · /v3/secret/set · /v3/secret/metadata ·
    /v3/queue/enqueue · /v3/cron/run-now · /v3/event/emit ·
    /v3/event/subscribe · /v3/backup/manifest · /v3/preview-env/create ·
    /v3/log-drain/set · /v3/presence/sweep; GET /v3/metrics.
  - `maludb-restd` dispatcher upgrade: `_find_endpoint` now loads
    `arg_schema`; `_call_handler` binds JSON body fields to named
    SQL parameters with per-type coercion (`text`, `bigint`,
    `integer`, `boolean`, `numeric`, `jsonb`, `timestamptz`,
    `text[]`, `bigint[]`, `bytea_hex`). Empty `arg_schema` keeps
    the existing zero-arg dispatch path. SETOF / TABLE returns are
    serialised as `[{column: value, ...}]`.
  - Smoke tests bumped from 7 to 9: typed-arg path against
    /v3/memory (scope_missing flow) + a synthetic /test/typed-echo
    that asserts the missing-required-arg error path.
- **v3.1 Stage E — V3-LOG-02** — `maludb-logsd` log-drain forwarder
  service runner. Polls `malu$log_drain` rows, pulls per-stream batches
  past the drain's cursor, ships to a sink, advances the cursor on
  success, and records a `malu$log_drain_run` row.
  - Migration `0.60.0 → 0.61.0`:
    * `malu$log_drain.cursor_jsonb` column (one entry per source stream).
    * `log_drain_advance_cursor(drain_id, stream, last_id)` — monotonic.
    * `log_drain_fetch_batch(drain_id, stream, limit)` returns
      `(record_id, payload)` rows. Streams supported in this migration:
      `audit` (malu$audit_event) and `realtime_event` (malu$event).
      `queue` / `mc2db` are explicit follow-ups.
  - Service (`services/maludb-logsd/`, Python stdlib + psycopg only):
    `Worker.iterate_once()` synchronously drains every enabled drain
    over every subscribed stream; `run_forever()` loops with a
    `--poll-interval-ms` cadence. Sinks: `file` (JSONL append) and
    `http` (stdlib urllib POST) fully implemented; `s3` and
    `otlp_http` raise an explicit "not yet implemented" `SinkError`
    that gets recorded as a run-row error. Inline `malu$secret`
    resolution via `secret_get_inline`; file:// / https:// resolvers
    arrive in V3-SECRET-02 (Stage I).
  - Smoke coverage (`services/maludb-logsd/tests/test_smoke.py`, 4/4):
    file sink against `audit` + cursor advance + re-run no-op + the
    `malu$log_drain_run` row, http sink against `realtime_event`
    using a stdlib `BaseHTTPRequestHandler` collector, unimplemented
    sink kind records an error row, disabled drain is skipped.
- **v3.1 Stage D — V3-CLI-02** — three new CLI subcommand families
  wrap the V3-ENV-01 / V3-LOG-01 / V3-BACKUP-01 SQL surfaces so
  operators don't have to drop to psql:
  - `maludb env create | record-seed | promote-check | list`
  - `maludb log-drain set | enable | disable | list | record-run`
  - `maludb backup manifest | verify | latest`
  No migration; cli/maludb v0.1.0 still ships against extension
  `0.60.0` from Stage C. Adds three smoke tests
  (test_12_env_lifecycle / test_13_log_drain_lifecycle /
  test_14_backup_lifecycle), bringing CLI smoke total to 14/14.
- **v3.1 Stage C — V3-PRESENCE-02** — presence TTL + sweeper.
  `malu$pool_presence` gains an optional `ttl_seconds` column.
  `presence_update` accepts a `p_ttl_seconds` parameter (tail-default
  NULL; existing callers unchanged). New `presence_sweep()` function
  marks rows with `last_seen_at + ttl_seconds < now()` as left,
  inserts a `leave` event with `reason='ttl_expired'`, emits the
  realtime stream event, and records an audit row. Returns the
  number of rows swept. Intended to be invoked by `cron_schedule`
  (V3-CRON-01) or admin tooling. Migration `0.59.0 → 0.60.0`.

## v3.0.1 — 2026-05-14

Post-`v3.0.0` GA install-trap fix. No extension version bump (no SQL
or C contract change); migration chain stays at `0.41.0 → 0.57.0`.

### Fixed
- `scripts/maludb-bootstrap` now adds **both** `pgaudit` and
  `pg_stat_statements` to `shared_preload_libraries` (previously
  only `pgaudit`). Matches what `pgaudit_recommended_settings()`
  has always recommended.
- `sql/governance_audit.sql` pins `ORDER BY component COLLATE "C"`
  so the regression output is deterministic across locales (UTF-8
  default-collation clusters sort `_` after `a`, which previously
  flipped `pgaudit` and `pg_stat_statements` row order).
- `docs/v3/field-test-fresh-vm-copypaste.md` documents two
  first-run traps surfaced by the `ubuntu24-test` fresh-VM run
  (per `docs/v3/field-test-fresh-vm-ubuntu24-test-20260514T141552Z.md`):
  - `psycopg-binary`'s bundled libpq defaults to `/tmp/` for the
    Unix socket while Debian/Ubuntu PG listens at
    `/var/run/postgresql/`; the V3 service/CLI smokes need
    `export PGHOST=/var/run/postgresql`.
  - `ALTER SYSTEM SET shared_preload_libraries = '<comma list>'`
    stores the value as a single double-quoted blob that PG then
    fails to load. The correct psql form is bare identifiers
    (`ALTER SYSTEM SET shared_preload_libraries = pgaudit, pg_stat_statements;`).
    The canonical `scripts/maludb-bootstrap` path (via `pg_conftool`
    → `postgresql.conf`) is immune and now installs both libraries.

## v3.0.0 — 2026-05-14

V3 **GA**. Cut from `main` at `8896631` after the fresh-VM
field-test on `ubuntu24-test`
(`docs/v3/field-test-fresh-vm-ubuntu24-test-20260514T141552Z.md`).
Resolves the only outstanding V3 acceptance gate (criterion #2 —
fresh Ubuntu 24.04 host). C ABI, SQL surface, and migration chain
`0.41.0 → 0.57.0` are identical to `v3.0.0-rc.1`; extension
version remains `0.57.0`. No new tickets.

All 10 V3 acceptance criteria PASS; see the sign-off report for
detail (`make installcheck` 66/66, restd 7/7, realtimed 4/4, CLI
11/11, libmaludb v0.1 + v0.2 smokes, fieldtest-v3 30/30,
doc-consistency green).

## v3.0.0-rc.1 — 2026-05-14

**Closes `requirements.md` §9 Stage 15 and clears the V3 acceptance
criteria.** Extension advances to **0.57.0** through four migrations
(`0.53.0 → 0.54.0` for V3-OBS-01, `0.54.0 → 0.55.0` for V3-LOG-01,
`0.55.0 → 0.56.0` for V3-BACKUP-01, `0.56.0 → 0.57.0` for V3-ENV-01).
V3-REPL-01 is docs-only.

### Added
- **V3-OBS-01** — `malu$metric_definition` catalog with 17 seeded
  families. `metrics_prometheus_scrape()` returns the full exposition
  text in Prometheus format, assembled from live counters across
  audit / queue / REST / MC2DB / auth / secret / vector / event /
  source / schedule / embedding tables.
- **V3-LOG-01** — `malu$log_drain` (http / file / s3 / otlp_http
  kinds, source_streams[], redaction_rules, destination_secret_ref)
  + `malu$log_drain_run` audit. Helpers: `log_drain_set`,
  `log_drain_enable / _disable / _list / _record_run`. The service
  runner is a follow-up.
- **V3-BACKUP-01** — `malu$backup_manifest` catalogs every artifact
  a full MaluDB backup must capture (postgres state + WAL + /etc +
  source archive + model configs + TLS + tool binaries + broker
  configs). `malu$backup_verification` records restore-check
  outcomes. Helpers: `backup_manifest_record`,
  `backup_verification_record`, `backup_manifest_latest`.
- **V3-ENV-01** — `malu$preview_env` + `malu$preview_env_seed`.
  `preview_env_create` rejects `seed_policy.production_data = true`
  by default. `preview_env_promote_check` reports a gate matrix
  (no-production-data, has-seed, migration-current).
- **V3-REPL-01** — `docs/v3/read-replicas.md` documents the
  supported PostgreSQL streaming-replica posture, the write/read
  routing matrix, and an operator checklist before pointing reads
  at a replica.

### V3 acceptance (per `version3-requirements.md`)

| Acceptance criterion | Status |
|---|---|
| 1. Docs agree on shipped version and surface | doc-consistency gate green at v3.0.0-rc.1 / 0.57.0. |
| 2. Fresh Ubuntu 24.04 host installs MaluDB, creates extension, starts MC2DB / REST / model / queue / cron / realtime, passes field test | All four service binaries (`maludb_modeld`, `maludb_mc2dbd`, `mcp-broker`, `maludb-restd`, `maludb-realtimed`) install via `make install`; queue and cron are catalog-resident via the extension itself. Field-test on a fresh VM is the RC sign-off step. |
| 3. REST, MC2DB, CLI, SDKs share one token/account model | V3-AUTH-01 token verifier (`auth_token_verify`) is reused by `maludb-restd` and the CLI; MC2DB has its own session model but admits the same `malu$account` rows. |
| 4. Source objects can be stored / verified / restored / linked to Source Packages + ledger | V3-STOR-01 catalog + CLI + promotion path shipped. |
| 5. Ingestion / embedding / lifecycle / ANN rebuild / broker-audit run through queue + scheduler | V3-QUEUE-01 + V3-CRON-01 catalogs + CLI; embed pipeline auto-enqueues. |
| 6. Realtime subscribers see authorised events; replay missed events from durable table | V3-REALTIME-01 + V3-PRESENCE-01 catalogs + SSE service + CLI subscribe / fetch / ack. |
| 7. Metrics + log drains expose enough signal to operate without reading PG tables manually | V3-OBS-01 + V3-LOG-01 catalogs. |
| 8. Backup + restore validation proves PG state + source archive remain hash-consistent | V3-BACKUP-01 catalog; CLI `db backup` / `db restore-check` from Stage 10. |
| 9. `pg_regress` passes on PostgreSQL 17 and V3 service / SDK smoke tests pass | 66/66 pg_regress + 7/7 restd + 4/4 realtimed + 11/11 CLI + 12/12 libmaludb v0.2 smoke. |
| 10. ASan / UBSan / clang-tidy / scan-build add no new warnings for C code touched by V3 | V3 added no new C code; the existing CI matrix runs unchanged. |

### Subtle finding caught during smoke
- Same `$body$` + psql `:variable` issue as Stages 13–14: the
  V3-BACKUP-01 test was rewritten to look up the manifest_id inside
  the DO block.

### Stage 15 follow-ups (tracked, not blocking RC)
- `services/maludb-logsd/` runner that drains the `pg_log`,
  `audit_event`, `mc2db_invocation`, `rest_invocation`, broker, and
  secret_use streams to the configured `malu$log_drain` destinations
  with redaction.
- `maludb backup` CLI extension that calls
  `backup_manifest_record(...)` after writing the dump + sidecar.
- `maludb env create|destroy|seed|promote-check` CLI wrapper around
  the V3-ENV-01 catalog.
- `maludb log-drain set|list|disable|enable` CLI wrapper around
  V3-LOG-01.
- PgBouncer + HAProxy `samples/` for the V3-REPL-01 routing recipes.

### V3 next
`v3.0.0` GA — RC field-test on a fresh Ubuntu 24.04 host. No
further migrations or new catalogs before GA; only the follow-ups
above + the field-test sign-off.

## v3.0.0-alpha.7 — 2026-05-14

**Closes `requirements.md` §9 Stage 14** — vector and retrieval
ergonomics. Extension advances to **0.53.0** through three
migrations (`0.50.0 → 0.51.0` for V3-VEC-01, `0.51.0 → 0.52.0` for
V3-EMBED-01, `0.52.0 → 0.53.0` for V3-RET-01).

### Added
- **V3-VEC-01** — vector metadata filter + index status.
  - `malu$vector_chunk.metadata jsonb` (UNIQUE GIN index) — every
    chunk now carries an attached metadata document.
  - `search_memory_filter(...)` runs the existing auth-aware
    compartment search and then applies `metadata @> p_filter`
    AFTER three-stage authorization — never as a substitute.
  - `malu$vector_index_status` — per-compartment index health
    (kind in exact/nsw/hnsw_local/hnsw_pgvector, delta_count,
    tombstone_count, last_rebuild_at, recall_sample).
    `vector_index_record()` UPSERTs status rows;
    `vector_index_status()` returns the operator matrix.
- **V3-EMBED-01** — embedding job pipeline.
  - `malu$embedding_job` + `malu$embedding_output` (vector + SVPOR
    frame text + input/output hashes + Derivation Ledger link).
  - `embedding_enqueue(...)` auto-registers the `embed` V3-QUEUE-01
    queue, creates a job row, enqueues an idempotency-keyed
    payload, and links `queue_job_id` back. Workers call
    `embedding_record_output(...)` which writes the vector + a
    `malu$derivation_ledger` entry of kind `memory_detail_object`
    (the existing ledger CHECK accepts that — a follow-up may add
    `embedding` as its own kind).
  - SVPOR frame text is required per `requirements.md` §3.2; an
    empty frame is rejected with `check_violation`.
- **V3-RET-01** — public retrieval envelope.
  - Stage 4's `malu$retrieval_envelope` extended with V3 columns:
    `account_id`, `partitions`, `temporal_mode`, `started_at`,
    `finished_at`, `candidate_counts`, `final_count`,
    `authz_decisions`.
  - `malu$retrieval_decision_audit` (envelope_id, stage in
    planning/expansion/assembly, allowed, reason, object_ref).
  - `retrieve_with_envelope(...)` wraps `execute_retrieval`,
    materialises the hits into a temp table once, records the
    envelope + per-row assembly decisions, then streams the rows.
  - `retrieve_envelope_debug(envelope_id)` returns the per-stage
    breakdown — requires `maludb_memory_auditor` membership
    (non-auditors get `insufficient_privilege`).

### Subtle findings caught during smoke
- Stage 4 already owned `malu$retrieval_envelope` as a plan record;
  V3-RET-01 extends it with ALTER TABLE rather than CREATE TABLE to
  avoid a collision.
- `malu$model_alias`'s identifier column is `alias_name`, not
  `alias` — found via the V3-EMBED-01 ledger lookup and fixed
  there + in `cli/maludb/commands/model.py`.
- psql `:variable` substitution does NOT happen inside
  `$body$ ... $body$` literals; the V3-EMBED-01 regression test
  was rewritten to look up the job_id inside the DO block.
- The Stage 13 `event_ack` expected snapshot was generated when
  the function buggily returned 1 (the trailing UPDATE's row
  count). The Stage 13 commit's CTE-counted fix now returns the
  number of events between the cursor and through_event_id; the
  expected snapshot is updated to match.

### Stage 14 follow-ups (tracked, not blocking)
- Multilevel-HNSW (local or pgvector-delegated) implementation;
  the catalog row supports either kind.
- Per-handler typed argument marshalling for the curated REST
  endpoints, so `retrieve_with_envelope` can be wired directly to
  `POST /retrieve` with structured body args.
- Bench fixtures (recall@k / latency) under `bench/v3_vec/`.
- Ledger `embedding` kind in a future migration so V3-EMBED-01
  outputs don't share the `memory_detail_object` derived_type.

### V3 next
Stage 15 (V3-OBS-01 + V3-LOG-01 + V3-BACKUP-01 + V3-ENV-01 +
V3-REPL-01) opens migration `0.53.0 → 0.54.0` — the final
production-operations track.

## v3.0.0-alpha.6 — 2026-05-13

**Closes `requirements.md` §9 Stage 13** — memory event stream and
active memory pool presence. Extension advances to **0.50.0** through
two migrations (`0.48.0 → 0.49.0` for V3-REALTIME-01,
`0.49.0 → 0.50.0` for V3-PRESENCE-01). New service binary
`maludb-realtimed` ships an SSE gateway over `malu$event`.

### Added
- **V3-REALTIME-01a** — event catalog. Migration `0.48.0 → 0.49.0`
  adds `malu$event` (event_id BIGSERIAL is the cursor; kind, account,
  partition, active_pool, object_ref, scope, transaction_time,
  payload), `malu$event_subscription` (per-account filter set +
  persistent cursor), `malu$event_delivery` (append-only delivery
  audit). SQL APIs: `emit_event`, `event_subscribe`,
  `event_fetch_batch` (returns events past cursor without advancing
  it — at-least-once is the default), `event_ack` (advances cursor +
  records delivery rows), `event_list_subscriptions`. `emit_event`
  NOTIFY-s on channel `maludb_event` so `maludb-realtimed` can use
  `LISTEN` for low-latency wakeups.
- **V3-REALTIME-01b** — retrofitted V3 write paths. `auth_token_create`,
  `queue_enqueue`, and `source_object_register` now `emit_event(...)`
  alongside their existing `audit_event(...)` call. Stage 2-7
  `register_*` functions stay untouched (a Stage 13 follow-up
  extends them).
- **V3-REALTIME-01c** — `services/maludb-realtimed/` v0.1.0. Stdlib
  Python SSE service. `GET /events?subscription=<id>` streams events
  with `Authorization: Bearer <V3-AUTH-01 token>`; the daemon binds
  the verified account's GUC per stream so RLS hides cross-tenant
  events. `LISTEN maludb_event` for wakeups; `select.select` with
  configurable poll interval as fallback. `POST /events/ack` advances
  the persistent cursor. 4/4 smoke tests pass against the live PG.
- **V3-PRESENCE-01** — pool presence. Migration `0.49.0 → 0.50.0`
  adds `malu$pool_presence` (UNIQUE per (pool, kind, ref)) and
  `malu$pool_presence_event`. Helpers: `presence_update`
  (UPSERT — emits join on first call, update on subsequent),
  `presence_leave`, `presence_list`. Every presence transition
  also emits a `pool_presence_{join,update,leave}` row on
  `malu$event` so realtime subscribers see them.
- **CLI** — new `maludb realtime` family: `subscribe`, `list`,
  `fetch` (no auto-ack), `ack`, `tail` (poll-loop with optional
  `--auto-ack`). 1 new CLI smoke test (subscribe → emit → fetch →
  ack → confirm empty).

### Subtle finding caught during smoke
- psycopg3's `conn.notifies()` generator blocks indefinitely without
  a `timeout=` arg. Switched to the low-level
  `conn.pgconn.consume_input()` + `conn.pgconn.notifies()` drain
  pattern in `maludb-realtimed`.
- `event_ack`'s row count was reading the trailing UPDATE's
  ROW_COUNT, not the INSERT's. Fixed by wrapping the INSERT in a
  CTE and counting it explicitly.

### Stage 13 follow-ups (tracked, not blocking)
- Extend `emit_event` into Stage 2-7 `register_*` functions
  (claim, fact, memory, episode, MDO, relationship, supersession,
  pool member changes, skill executions, retrieval) so subscribers
  see the full memory-write surface.
- WebSocket transport alongside SSE (the spec mentions both;
  current ship is SSE-only).
- Presence TTL (today presence rows stay "active" until an explicit
  `presence_leave`; an inactivity timeout is a Stage 13 follow-up).

### V3 next
Stage 14 (V3-VEC-01 + V3-EMBED-01 + V3-RET-01) opens migration
`0.50.0 → 0.51.0` — vector metadata filters + the HNSW/NSW choice,
the embedding job pipeline, and a public retrieval endpoint with an
explicit envelope.

## v3.0.0-alpha.5 — 2026-05-13

**Closes `requirements.md` §9 Stage 12** — Verbatim Source Archive v1.
Extension advances to **0.48.0** through two migrations
(`0.46.0 → 0.47.0` for the catalog, `0.47.0 → 0.48.0` for the
promotion path). The `maludb source` CLI family — the last
remaining `StagePendingError` stub — is now real wiring.

### Added
- **V3-STOR-01a** — source archive catalog. Migration
  `0.46.0 → 0.47.0` adds `malu$storage_adapter` (local_fs / s3),
  `malu$source_object` (32-byte raw `content_hash` bytea UNIQUE,
  retention_class, legal_hold, sensitivity, partition, adapter_id +
  adapter_uri, signed_url_policy), and
  `malu$source_object_reference` (byte_range / line_range / page /
  timestamp / cursor anchors). SQL APIs: `register_storage_adapter`
  (UPSERT, validates kind-specific config), `source_object_register`
  (dedup by content_hash), `source_object_lookup_by_hash`,
  `source_object_set_legal_hold`, `source_object_add_reference`,
  `source_object_metadata`. RLS owner_schema-bound across all three
  tables.
- **V3-STOR-01b** — promotion path. Migration `0.47.0 → 0.48.0` adds
  `source_object_promote_to_source_package`, which wraps
  `register_source_package` with the archive's content_hash,
  byte_length, media_type, retention_class, sensitivity, source_time,
  and writes a `malu$derivation_ledger` entry of kind
  `source_package` recording `source_object_id`, `adapter`,
  `content_hash`, `byte_length`.
- **CLI** — `maludb source` family flipped from
  `StagePendingError` stub to real wiring:
    `source adapter-register`  registers a local_fs / s3 adapter.
    `source put`               reads a file, computes SHA-256,
                               writes to the adapter, registers.
    `source get`               downloads + hash-verifies a stored
                               object to a local path.
    `source verify`            re-reads and confirms hash + length.
    `source list`              enumerates objects (optionally by
                               partition).
    `source promote`           promotes object → source_package +
                               Derivation Ledger entry.
  The local_fs adapter is implemented end-to-end in the CLI; the
  s3 adapter is catalog-only (the CLI raises a clear error on
  `put`/`get` until the Stage 12 follow-up wires `boto3`-style I/O).
- **Sharded layout for local_fs**: objects are written to
  `<base_path>/<hash[0:2]>/<hash[2:4]>/<hash_hex>` so a single
  archive can hold ~17M objects without bumping into the per-dir
  inode ceilings of common filesystems.

### Stage 12 follow-ups (tracked, not blocking)
- S3-compatible adapter `put`/`get` wired in the CLI (and in
  `maludb-restd` when it grows a `/sources` endpoint).
- Signed-URL issuance per `malu$source_object.signed_url_policy`.
- Bulk verify command (today the CLI verifies one object at a time).
- `maludb-restd` `/sources` endpoint that proxies put/get/verify.

### V3 next
Stage 13 (V3-REALTIME-01 + V3-PRESENCE-01) opens migration
`0.48.0 → 0.49.0` — the memory event stream (SSE / WebSocket) and
active memory pool presence. Subscriptions are authorized via
V3-AUTH-01 tokens; durable events live in `malu$event` so missed
deliveries can be replayed at-least-once on reconnect.

## v3.0.0-alpha.4 — 2026-05-13

**Closes `requirements.md` §9 Stage 11** — durable job queue and
scheduler. Extension advances to **0.46.0** through two migrations
(`0.44.0 → 0.45.0` for V3-QUEUE-01, `0.45.0 → 0.46.0` for
V3-CRON-01). All native PL/pgSQL; the pgmq / pg_cron adoption gates
remain open as future swap targets.

### Added
- **V3-QUEUE-01** — durable job queue.
  Migration `0.44.0 → 0.45.0` adds `malu$queue`, `malu$queue_job`,
  `malu$queue_lease`, and the `maludb_queue_worker` NOLOGIN role.
  SQL APIs: `queue_register`, `queue_enqueue` (idempotency-key
  aware), `queue_lease` (FOR UPDATE SKIP LOCKED batch), `queue_ack`,
  `queue_nack` (auto-DLQ when attempts > max_retries),
  `queue_reap_expired_leases`, `queue_stats`. RLS owner_schema-bound
  across all three tables. 9 regression cases in `sql/queue.sql`.
- **V3-CRON-01** — scheduler.
  Migration `0.45.0 → 0.46.0` adds `malu$schedule`,
  `malu$schedule_run`, a PL/pgSQL cron-expression evaluator
  (`_cron_expand_field`, `cron_next_after`) that supports the 5-field
  syntax plus `@hourly`/`@daily`/`@weekly`/`@monthly`/`@yearly`
  aliases, and SQL APIs `schedule_create`, `schedule_enable`,
  `schedule_disable`, `schedule_list`, `schedule_run_now`,
  `schedule_tick` (operator-callable, runs every schedule whose
  `next_run_at <= now()`). Two action kinds: `enqueue` (preferred —
  pushes onto a V3-QUEUE-01 queue) and `sql` (admin-only — narrowly
  granted, runs arbitrary SQL). 7 regression cases in
  `sql/cron_schedule.sql`. Cron honors session TimeZone (matches
  conventional cron behavior); the regression test pins UTC.
- **CLI** — `maludb queue *` and `maludb cron *` flipped from
  `StagePendingError` stubs to real wiring: `queue enqueue|list|
  drain|retry|stats`, `cron list|create|enable|disable|run-now|
  tick`. CLI smoke tests cover the new lifecycle paths.

### Stage 11 follow-ups (tracked, not blocking)
- pg_cron / pgmq adoption review — both are PostgreSQL-licensed and
  packaged by PGDG; deferred while the native implementation proves
  itself in alpha.
- A bridge worker that polls `schedule_tick()` (currently operators
  call it via an external clock — pg_cron or a one-line `psql` loop).
- DLQ replay tool (today the CLI's `queue retry --job-id` flips a
  single dead job back to pending; bulk replay is a follow-up).

### V3 next
Stage 12 (V3-STOR-01) opens migration `0.46.0 → 0.47.0` — the
Verbatim Source Archive v1 (local FS + S3-compatible adapters,
signed URLs, retention / legal-hold, promotion path into Source
Packages). Wires up the `maludb source put|get|verify` CLI family
(currently the only remaining StagePendingError stub).

## v3.0.0-alpha.3 — 2026-05-13

**Closes `requirements.md` §9 Stage 10** — V3 REST gateway, CLI, and
SDK parity. Extension advances to **0.44.0** through a single
migration (`0.43.0 → 0.44.0`) plus a new service binary, a new CLI,
and a major version bump on the C SDK.

### Added
- **V3-API-01a** — curated REST endpoint catalog + invocation audit.
  Migration `0.43.0 → 0.44.0` adds `malu$rest_endpoint`,
  `malu$rest_invocation`, the `maludb_rest_dispatcher` NOLOGIN role,
  and SQL helpers `rest_register_endpoint`, `rest_disable_endpoint`,
  `rest_list_endpoints`, `rest_openapi_spec`, `rest_log_invocation`.
  9 regression cases in `sql/rest_endpoint.sql`. The catalog refuses
  bogus handlers via the `regprocedure` cast, so private `malu$`
  tables are never reachable through the REST API.
- **V3-API-01b** — `services/maludb-restd/` v0.1.0. Stdlib-Python
  HTTP service (matches the `services/mcp-broker/` precedent;
  `psycopg[binary]>=3.1` reused from the Python driver). Three
  built-in routes (`/healthz`, `/version`, `/openapi.json`) plus a
  catalog-driven dispatcher that verifies V3-AUTH-01 bearer tokens,
  checks required scopes, binds the tenant GUC, dispatches to the
  registered handler, and writes `malu$rest_invocation` audit.
  7/7 smoke tests pass against the live PG.
- **V3-CLI-01** — `cli/maludb/` v0.1.0. First-party stdlib-Python
  CLI with 14 subcommand families: `status`, `install doctor`,
  `db upgrade|backup|restore-check`, `auth token *`, `secret *`,
  `model *`, `prompt *`, `tool *`, `retrieve`, `replay`,
  `metrics scrape`, plus `source`/`queue`/`cron` stubs that raise
  `StagePendingError` (exit 70) pending the V3-STOR-01 /
  V3-QUEUE-01 / V3-CRON-01 stages. Human and JSON output for every
  command. 10/10 smoke tests pass.
- **V3-SDK-01** — `drivers/c/libmaludb` v0.2.0. New wrappers:
  `maludb_pool_create`, `maludb_pool_add_observation`,
  `maludb_pool_promote_to_claim`, `maludb_skill_register`,
  `maludb_skill_add_state`, `maludb_skill_add_transition`,
  `maludb_skill_begin_execution`, `maludb_skill_step_execution`,
  `maludb_skill_abort_execution`, `maludb_node_register`,
  `maludb_node_submit`, `maludb_node_accept`, `maludb_node_reject`.
  CMake bumped to project VERSION 0.2.0; the v0.1.0 `smoke` test
  continues to pass and the new `smoke_v02` test exercises all 13
  wrappers (12/12 named checks pass).
- **Doc reconciliation**: README + user-manual now name
  `maludb-restd` as a shipped service and the `maludb` CLI as a
  shipped surface; `scripts/maludb-check-doc-consistency` learned
  to look for `maludb-restd` (or `restd`) in both docs.

### Decision
- `version3-plan.md` V3-API-01 was specified as "Go (default) or
  Rust"; the actual ship is stdlib Python + psycopg, matching the
  `mcp-broker` precedent. The plan and the §8.1 dependency table
  are updated to reflect this; Go remains an acceptable alternative
  if the dispatcher needs to scale past the GIL.

### Stage 10 follow-ups (tracked, not blocking)
- C-backed HMAC verifier and JWT signature verifier (V3-AUTH-01
  performance follow-up).
- C-backed file/HTTPS secret resolver (V3-SECRET-01 follow-up).
- Curated REST catalog of stable endpoints (~20 routes listed in
  `version3-plan.md` V3-API-01) — only the three built-in routes
  are populated automatically today.
- Typed-argument marshalling for non-zero-arg REST handlers and CLI
  tool invocations.

### V3 next
Stage 11 (V3-QUEUE-01 + V3-CRON-01) opens migration `0.44.0 →
0.45.0`. Durable job queue + scheduler unlock V3-EMBED-01 and
V3-OBS-01 / V3-LOG-01.

## v3.0.0-alpha.2 — 2026-05-13

**Closes `requirements.md` §9 Stage 9** — V3 identity and secrets.
Extension advances to **0.43.0** across two migrations
(`0.41.0 → 0.42.0` for V3-AUTH-01, `0.42.0 → 0.43.0` for V3-SECRET-01).
SQL surface only; the C-backed HMAC/JWT verifier (V3-AUTH-01) and
the file/HTTPS secret resolver (V3-SECRET-01) are tracked as Stage 9
follow-ups and not blocking this tag.

### Added
- **V3-AUTH-01** — first-party API token catalog. Migration
  `0.41.0 → 0.42.0` adds `malu$auth_token`, `malu$auth_token_use`,
  `malu$jwt_signing_key`, and `malu$auth_pepper`. SQL APIs:
  `auth_token_create`, `auth_token_revoke`, `auth_token_verify`
  (HMAC-SHA256 under a server-side pepper via `pgcrypto.hmac`).
  `jwt_verify` is stubbed and raises `feature_not_supported` until
  the C verifier lands. RLS per owner_schema; audit on every
  create / revoke / accept / reject. Plaintext tokens use the
  `mldbat_<base64url>` shape and are returned exactly once by
  `auth_token_create`.
- **V3-SECRET-01** — governed secret store. Migration
  `0.42.0 → 0.43.0` adds `malu$secret`, `malu$secret_version`,
  `malu$secret_use`, and `malu$secret_master_key`. SQL APIs:
  `secret_set` (inline AES-256 via `pgcrypto.pgp_sym_encrypt`),
  `secret_set_external` (registers an external `file://` / `env://`
  reference; resolver stubbed), `secret_revoke`, `secret_get_metadata`
  (metadata-only — never returns ciphertext or external_ref),
  `__secret_resolve` (granted only to the new `maludb_secret_consumer`
  NOLOGIN role). RLS per owner_schema across the entire catalog.
- **`pgcrypto`** added to `maludb_core.control` `requires`. Fresh
  installs get it via `CREATE EXTENSION ... CASCADE`; in-place
  upgraders get it via the `CREATE EXTENSION IF NOT EXISTS pgcrypto`
  guard in the 0.41 → 0.42 migration.
- **Schema USAGE for the memory_* role family**. Previously, only
  the `maludb_llm_*` roles had `USAGE` on schema `maludb_core`; the
  `maludb_memory_admin / _executor / _auditor` roles created in
  0.14.0 had table grants but no schema USAGE — the gap was invisible
  because earlier tests bound to the LLM role family. The 0.41 → 0.42
  migration adds the missing USAGE grants.
- **`scripts/maludb-check-doc-consistency`** loosened its release-tag
  pattern to accept `Last release tag` as a label so tag bumps
  between stages don't trip the doc gate.

### Tests
- New `sql/auth_token.sql` + `expected/auth_token.out` — 9 cases:
  create / verify / unknown / revoke / expire / CIDR allow-list /
  RLS isolation / `jwt_verify` stub / audit-event coverage.
- New `sql/secret_store.sql` + `expected/secret_store.out` — 8 cases:
  inline create / resolve / non-consumer denied / rotation / external
  ref stub / revocation / ciphertext-not-plaintext / audit-event
  coverage.
- `expected/load.out` and `expected/catalog.out` updated to the new
  default_version, the pgcrypto CASCADE NOTICE, and the new catalog
  table count.

### V3 next
Stage 10 (V3-API-01 + V3-CLI-01 + V3-SDK-01) opens migration
`0.43.0 → 0.44.0` — REST endpoint catalog and invocation audit, then
the first-party `maludb` CLI and SDK parity work. The C-backed
HMAC/JWT verifier (V3-AUTH-01 follow-up) and the file/HTTPS secret
resolver (V3-SECRET-01 follow-up) are tracked but not blocking
Stage 10.

## v3.0.0-alpha.1 — 2026-05-13

**Closes `requirements.md` §9 Stage 8** — Version 3 documentation
reconciliation (V3-DOC-01, V3-DOC-02). Docs-only release; extension
stays at **0.41.0**, no migration added.

### Added
- `requirements.md` §1.5 *Version 3 — Platform Ergonomics* and §9
  Stages 8–15 covering V3-DOC-01 … V3-REPL-01. §8.1 *V3 dependency
  candidates* table for `pg_cron`, `pgmq`, PostgREST, `pgsodium`,
  PgBouncer, S3 SDK, OTLP HTTP. §10 V3-specific open decisions.
- `version3-requirements.md` — V3
  themes (A–G) and ticket-level scope.
- `version3-plan.md` — V3 implementation plan:
  per-ticket deliverables, dependency graph, migration assignments
  (`0.42.0` → `0.57.0`), tag plan (`v3.0.0-alpha.1` … `v3.0.0`),
  license gates, cross-cutting engineering rules, risks, done-when.
- `docs/user-manual.md` §1.1 *Current Version* block, §1.2 *Shipped
  Memory Surface (Stages 1–7)*, §1.3 *What's NOT in 2.0.0-alpha*,
  §12.1 *Search modes* (corrects the stale "ANN/HNSW not
  implemented" claim — local ANN is implemented as **single-layer
  NSW**, callable through `search_memory_exact` after `ann_build`),
  §20 *Version 3 Preview*.
- `scripts/maludb-check-doc-consistency` — Stage 8 acceptance gate
  that fails CI when `maludb_core.control`, `README.md`,
  `docs/user-manual.md`, and `CHANGELOG.md` disagree on
  `default_version`, release tag, supported PG majors, shipped
  services, or shipped SDKs. Wired into `.github/workflows/ci.yml`
  as job `doc-consistency`.
- `CLAUDE.md` *Authoritative documents* now references
  `version3-requirements.md` and `version3-plan.md`; *Staging
  strategy* now reflects Stages 1–7 shipped and Stages 8–15 in
  progress.

### Fixed
- `docs/user-manual.md` no longer reports `default_version = 0.4.0`
  (the actual control-file value is `0.41.0`).
- `docs/user-manual.md` no longer claims the memory object model,
  bitemporal truth, Derivation Ledger, Workflow Extraction, Skill
  Runtime, Active Memory Pools, and Local Memory Nodes are roadmap
  scope — Stages 2–6 shipped them.
- `README.md` *Stage 6 (drivers)* status corrected from `⏸ deferred`
  to `✅` (S6-5 broker and S6-6 SDKs both shipped); C SDK v0.2.0
  pool/skill/node wrappers tracked as V3-SDK-01 follow-up.
- `README.md` *External services* row now names the model gateway
  (`maludb_modeld`) alongside `maludb_mc2dbd` and `mcp-broker`.

### V3 next
Stage 9 (V3-AUTH-01, V3-SECRET-01) opens migration `0.41.0 →
0.42.0`.

## v2.0.0-alpha.4 — 2026-05-13

**Closes `requirements.md` §9 Stage 6** — every roadmap item from
the staged plan is now shipped. Extension stays at **0.41.0**.

### Added
- **External MCP broker** (`services/mcp-broker` v0.1.0): stdlib-only
  Python reference broker that proxies non-database tools to MCP
  clients over stdio JSON-RPC. Shell tool kind with `{{var}}`
  substitution, schema-validated input, per-call timeouts,
  absolute-path argv enforcement, `shell=False` dispatch, JSONL
  audit on stderr. 6/6 smoke tests pass via stdlib `unittest`.
- `docs/mcp-broker-design.md`: contract — motivation, architecture
  diagram, wire shape (initialize / tools/list / tools/call),
  threat model, v1 scope vs deferred-to-v2.

### Roadmap status
All §9 items now ✅. Remaining nice-to-haves are quality polish, not
new functionality:
- C SDK v0.2.0 (pool / skill / node wrappers) — mechanical follow-up.
- Lintian-clean source tree + apt-repo upload posture.
- mc2dbd ingest of broker JSONL audit lines into
  `malu$mc2db_invocation`.

## v2.0.0-alpha.3 — 2026-05-13

Completes the four-language driver matrix. Extension stays at
**0.41.0**.

### Added
- **C SDK** (`drivers/c/libmaludb` v0.1.0): native C library over
  libpq, CMake 3.16+ build, generates `libmaludb.so` + `maludb.pc`
  pkg-config metadata for downstream consumers. First cut covers
  the headline ~12 methods (`maludb_connect`, `maludb_close`, error
  inspection, `version`, the five `register_*` ingest helpers,
  `text_search`, `retrieve`, `replay_episode`, with matching
  `free_*` helpers for the returned hit arrays). 6/6 plain-C smoke
  pass; example output matches Python / Node.js / PHP / SQL.

### Pending in C SDK v0.2.0
- Active memory pool wrappers (create, add_observation, promote*).
- Skill runtime wrappers (register, add_state, add_transition,
  begin/step/abort_execution).
- Local-node sync wrappers (register, submit, accept, reject, revoke).

## v2.0.0-alpha.2 — 2026-05-13

Driver + packaging rollup since `v2.0.0-alpha.1`. Extension stays at
**0.41.0**; **51/51 pg_regress** unchanged.

### Added
- **Node.js / TypeScript SDK** (`drivers/nodejs/@maludb/client` v0.1.0):
  ESM + TypeScript over node-postgres. 27 methods mirroring the
  Python shape, typed exception hierarchy, models, smoke test
  (3/3 pass), runnable example matching SQL output.
- **PHP SDK** (`drivers/php/maludb/client` v0.1.0): PHP 8.2+ via
  PDO_PGSQL, PSR-4 layout. 27 methods, typed exception hierarchy
  with SQLSTATE translation, smoke runner (6/6 pass — both PHPUnit
  and a plain-PHP runner that works without ext-dom), runnable
  example matching SQL/Python/Node.js output.
- **`scripts/maludb-force-rls`** — operator opt-in helper for FORCE
  ROW LEVEL SECURITY across every Stage 2+ governed table.
  `--status`, `--apply`, `--revert` modes; idempotent; discovers
  candidates programmatically via `tenant_owner` policy presence.
  Closes `docs/security-review.md` finding #1.
- **Multi-PG-version Debian packaging**: `dpkg-buildpackage` now
  produces three per-version `.deb` files:
  - `postgresql-16-maludb-core_0.41.0-1_amd64.deb`
  - `postgresql-17-maludb-core_0.41.0-1_amd64.deb`
  - `postgresql-18-maludb-core_0.41.0-1_amd64.deb`
  plus `maludb-mc2dbd_0.41.0-1_amd64.deb`. `debian/pgversions` is
  the narrowing knob.

### Fixed
- `drivers/php/src/Client.php`: empty-authority libpq URIs
  (`postgresql:///mydb`) now parse correctly. PHP's built-in
  `parse_url` returned false on those; we inject a placeholder host
  before parsing and strip it afterward.
- `debian/.gitignore` (new): keeps `dpkg-buildpackage` artefact trees
  (`postgresql-*-maludb-core/`, `maludb-mc2dbd/`, `.debhelper/`,
  `tmp/`, `*.substvars`, `*.debhelper.log`) out of git.

### Deferred
- S6-5 External MCP broker reference.
- C driver SDK (libmaludb).
- Lintian-clean apt-repo upload.

## v2.0.0-alpha.1 — 2026-05-13

Post-alpha rollup. Extension at **0.41.0**; **51/51 pg_regress** on PG 17.

### Added
- **Python driver SDK** (`drivers/python/maludb` v0.1.0): synchronous
  client over the maludb_core SQL surface with 27 methods covering
  ingest / retrieve / pool / skill / node, typed dataclass return
  shapes, SQLSTATE-class-mapped exception hierarchy, pytest smoke
  test (3/3 pass against a live extension), and a runnable example
  mirroring `examples/01-ingest-to-replay.sql`.
- **`scripts/maludb-bootstrap` section 3a**: configures
  `shared_preload_libraries=pgaudit` + `pgaudit.log` at install
  time via `pg_conftool` and restarts `postgresql@17-main`.
  Idempotent.
- **`scripts/maludb-validate` section 3a**: PASS/WARN check for
  `pgaudit` in `shared_preload_libraries` + non-empty `pgaudit.log`.

### Changed
- **migration 0.40.0→0.41.0** adds `owner_schema name NOT NULL` to
  `malu$mc2db_invocation` with a `tenant_owner` RLS policy. Closes
  `docs/security-review.md` finding #2 (medium). Existing rows
  backfilled to `'maludb_core'`.
- `docs/security-review.md` updated: findings #2 and #3 marked
  CLOSED; #1 (no FORCE RLS) and S7-2.b remain open.
- `examples/01-ingest-to-replay.py` made idempotent via per-run
  uuid suffix on the SVPOR signature — re-runs no longer trip
  `malu$fact_active_window_excl`.

### Deferred (unchanged from v2.0.0-alpha)
- S6-5 External MCP broker reference implementation.
- S6-6 Drivers for C / Node.js / PHP.
- S7-2.b operator opt-in for FORCE RLS.
- Multi-PG-version `.deb` (PG 16, 18).

## v2.0.0-alpha — 2026-05-13

**First public alpha.** Stages 1–6 in-DB feature set complete plus
Stage 7 hardening deliverables (perf benchmark, security review,
documentation, deb packaging). Extension at 0.40.0; 50/50 pg_regress
tests pass on PG 17.

### Stage 7 hardening
- `bench/` directory with seed + three pgbench scripts +
  `run-baseline.sh` runner. Initial baseline:
  text_search 3856 tps · graph_walk 2135 tps · retrieve 141 tps.
- `docs/security-review.md` — RLS / pgaudit / grants audit. 87
  malu$* tables; 59 with RLS + tenant_owner policy; 0 fail-closed
  bugs. Three follow-ups flagged (mc2db_invocation RLS, optional
  FORCE RLS, pgaudit preload at bootstrap).
- `docs/getting-started.md` + `docs/admin-guide.md` + `examples/`
  (four end-to-end SQL scenarios: ingest-to-replay, skill-execution,
  pool-promotion, local-node-sync). All examples verified to run.
- `debian/` refreshed at 0.40.0-1; `dpkg-buildpackage` produces two
  binary packages: `postgresql-17-maludb-core` (181 KB, 40
  migrations) + `maludb-mc2dbd` (37 KB).

### Deferred to follow-ups
- S6-5 External MCP broker reference implementation.
- S6-6 Drivers/SDKs for C / Python / Node.js / PHP.
- Multi-PG-version `.deb` (16/18) — mechanical add via `pgversions`
  + `pg_buildext supported-versions` loop in `debian/rules`.
- Lintian-clean packaging for apt-repo upload.

## v1.6.0 — 2026-05-13

Stage 6 in-DB closer. Extension 0.40.0. 50/50 tests.
- S6-1 Local node sync protocol + conflict records.
- S6-2 Model registry blue-green + dual-space query routing.
- S6-3 Embedding adapters + local model capability negotiation.
- S6-4 Advanced MC2DB tools (19 tools on a new `maludb.advanced`
  server).

## v1.5.0 — 2026-05-13

Stage 5 closer. Extension 0.36.0. 46/46 tests.
- S5-1 Workflow extraction engine (positive + negative evidence;
  no auto-promotion).
- S5-2 Skill runtime as governed state machine (applicability,
  preconditions, exception:* wildcard, terminal states).
- S5-3 Active memory pool manager + promotion path observation →
  pending_claim → fact.
- S5-4 Episode replay API (four modes: current_valid, historical,
  as_of_transaction_time, full_bitemporal).

## v1.4.0 — 2026-05-13

Stage 4 closer. Extension 0.32.0. 42/42 tests.
- S4-1 Graph traversal (recursive CTE, BFS/DFS, cycle prevention).
- S4-2 Native FTS + pg_trgm with weighted SVPOR frame.
- S4-3 Retrieval planner (envelopes, cues, plans).
- S4-4 Query hint API (six directives).
- S4-5 Authorization-aware retrieval — three-stage authz
  (planning, expansion, assembly).

## v1.3.0 — 2026-05-13

Stage 3. Extension 0.27.0. 37/37 tests.
- Bitemporal time (valid + transaction time, GIST indexes).
- Temporal supersession engine.
- SVPOR organization registries.
- MAUT confidence scoring.
- Lifecycle + salience + legal hold.

## v1.2.0 — 2026-05-13

Stage 2. Extension 0.22.0. 32/32 tests.
- Source packages, claims, facts, episode objects, memory detail
  objects, relationship edges, derivation ledger, governed-object
  base, verbatim archive, recursive MDO addressing, payload schema
  validation, atomic multi-model writes, ingestion connectors,
  governance audit.

## v1.1.0 — 2026-05-13

R1.1 advanced vector substrate. Extension 0.14.0. 24/24 + 28 service
tests.

## v1.0.0-rc1 — 2026-05-06

Initial R1.0 field-test surface — Stage 1 substrate, Stage 1.5 model
runtime + Session Context, Stage 1.6 MC2DB listener.
