# Memory-Extraction JSON Contract (DRAFT for approval)

> **Status: BUILT in 0.92.0 — verified live 2026-06-02.** Shipped as
> `maludb_memory_ingest_extraction(...)`
> (`sql/extension/maludb_core--0.91.0--0.92.0.sql`); acceptance test
> `examples/mist-e2e/07-extraction-json.sql` (deltas 0.82→0.92 on PG17, all
> assertions pass). Decisions locked: C = v1 is the full core (claims/facts
> fast-follow); D = provenance `accepted`; E = episodes dedup on
> `(kind, title, occurred_at)`; hints are NOT a DB concept (the external
> extractor bakes them into explicit subjects/edges). This document defines the single JSON object the project
> ingests to create memory structures. The LLM that produces this object runs
> **outside** the project; the project receives the object and materializes it.
>
> Scope set by the requirements conversation: the project does **not** call any
> LLM, run prompts, manage a queue, or hold model config. Everything arrives as
> one JSON object in this format. Embeddings are **deferred** to a separate
> background worker — this ingest builds graph structures only.

---

## 1. What the ingest does (and does not)

**Does:** create/merge subjects (nodes), verbs, episodes, edges (statements),
node attributes, edge attributes, subject↔subject relationships, external
reference pointers, and (optionally) the source document — all from one JSON
object, in one transaction (per item; see §7 skip-bad-item).

**Does not:** call an LLM, compute embeddings, run prompts, dedup by fuzzy
matching, or require human review. Names are trusted: the external extractor was
given the canonical match-list, so the DB resolves a subject/verb by exact
canonical name or alias and **only creates a new one if it isn't already
present**.

**Deferred (separate worker, not this contract):** embeddings. Each edge carries
its `source_span`, so a later worker can embed it into the correct `(subject,
verb)` compartment and link the chunk back to the statement. Until then, edges
exist in the graph but are not yet returned by `maludb_memory_search`.

---

## 2. Top-level object

```json
{
  "document":      { ... },      // optional — create the source doc in the same call
  "source":        { "kind": "document", "id": 1234 },  // optional — anchor to an EXISTING object instead
  "subjects":      [ <subject> ],
  "verbs":         [ <verb> ],   // optional — only to set aliases/type/description explicitly
  "episodes":      [ <episode> ],
  "edges":         [ <edge> ],
  "relationships": [ <relationship> ],
  "claims":        [ <claim> ],  // ⚠ DECISION C — v1 or fast-follow
  "facts":         [ <fact> ]    // ⚠ DECISION C
}
```

- All sections are optional; an object may contain only `subjects`, only
  `edges`, etc.
- **The source anchor** is either `document` (created now) or `source` (an
  existing `(kind, id)`). Edges/relationships reference it with the reserved key
  `"$source"`. If neither is present, edges that reference `"$source"` are
  skipped (recorded as skipped — see §7).

---

## 3. Subjects (nodes)

```json
{
  "key": "oracle21c",                       // REQUIRED — unique within this object; how edges refer to it
  "name": "Oracle Database 21c",            // REQUIRED — canonical_name (exact-match resolve/create)
  "type": "software",                       // subject_type picker; default "other"
  "aliases": ["Oracle 21c", "the database"],// merged into the node on match
  "attributes": [ <attribute> ],            // NODE attributes -> attributes on the subject
  "ref": { "source": "cmdb", "entity": "servers", "key": "srv-100" }  // optional external pointer
}
```

| Field | MaluDB mapping |
|---|---|
| `name`, `type`, `aliases` | `register_svpor_subject` (upsert on `(owner_schema, canonical_name)`; aliases merged) |
| `attributes[]` | `attributes_apply('subject', subject_id, …)` — **node** attributes |
| `ref` | stored as a reference attribute (`ref_source/ref_entity/ref_key`) on the node |

`key` is a local handle used only inside this object; it is **not** stored.

---

## 4. Verbs (optional)

Only needed to register aliases / type / description. A verb named in an edge but
absent here is auto-created by canonical name.

```json
{ "name": "upgrade", "type": "updated", "aliases": ["upgraded","performed upgrade"], "description": "…" }
```
→ `register_svpor_verb`. **Rule (locked earlier):** verbs stay small/canonical;
status / timing / "performed" live in **edge attributes**, not in the verb.

---

## 5. Episodes (all kinds)

```json
{
  "key": "kickoff",
  "kind": "Planning",            // episode_type: Meeting, Daily Standup, Review, Retrospective,
                                 //   1:1, Incident, Planning, Project, Task, Sprint
  "title": "MIST Project Kickoff",
  "summary": "…",
  "occurred_at": "2013-03-23T00:00:00Z",
  "occurred_until": null,
  "attributes": [ <attribute> ]  // e.g. planned_start_date, story_points, percent_complete
}
```

| Field | MaluDB mapping |
|---|---|
| `kind`,`title`,`summary`,`occurred_at`,`occurred_until` | `register_episode` |
| `attributes[]` | `attributes_apply('episode_object', episode_id, …)` |

Episodes are referable endpoints (`object_kind: "episode_object"`) so an edge can
say *person → attended → kickoff* or *document → generated_by → review*.

> ⚠ **DECISION E (episode idempotency):** episodes have no natural unique key.
> On re-ingest of the same object, do we (a) always create a new episode, or (b)
> dedup on `(kind, title, occurred_at)`? Proposal: **(b)**, upsert on that triple.

---

## 6. Edges (statements) and Relationships

### 6a. Edge = a verb-typed SVO statement

```json
{
  "subject": "oracle21c",        // a subject/episode key, or "$source"
  "subject_kind": "subject",     // subject | document | episode_object | …  (default "subject")
  "verb": "upgrade",
  "object": "$source",           // key or "$source"; if omitted -> "$source"
  "object_kind": "document",     // default inferred from the referenced item
  "attributes": [ <attribute> ], // EDGE attributes (the "predicate": status, event_at, …)
  "valid_from": "2026-03-30T23:00:00-05:00",
  "valid_to": null,
  "source_span": "We performed the Oracle 21c upgrade on Sunday March 30 at 11 pm",
  "confidence": 0.94
}
```

| Field | MaluDB mapping |
|---|---|
| endpoints + `verb` | `register_svpor_statement` (idempotent on the SVO identity) |
| `attributes[]` | `attributes_apply('svpor_statement', statement_id, …)` — **edge** attributes |
| `source_span`, `confidence`, provenance | carried in the statement `metadata_jsonb` / `confidence`; `source_span` is what the embedding worker uses later |

Valid endpoint kinds: `subject, verb, document, episode_object, memory,
source_package, claim, fact, memory_detail_object`.

### 6b. Relationship = subject↔subject typed temporal edge

For the directed, typed, valid-time subject relationship layer (distinct from
SVO statements):

```json
{ "from": "oracle21c", "to": "billing", "relationship_type": "depends_on",
  "valid_from": "2026-01-01T00:00:00Z", "valid_to": null }
```
→ the `malu$svpor_subject_relationship_edge` layer (exact writer wired at build).

---

## 7. Shared `<attribute>` object

Used by subjects, episodes, and edges. Exactly one `value_*` per attribute.

```json
{
  "attr_name": "event_at",
  "value_timestamp": "2026-03-30T23:00:00-05:00",
  "value_text": null, "value_numeric": null, "value_jsonb": null, "value_range": null,
  "unit": null,
  "confidence": null,
  "valid_from": null, "valid_to": null,
  "ref_source": null, "ref_entity": null, "ref_key": null
}
```
Maps 1:1 to a `attributes_apply` element (typed columns
`value_timestamp/value_text/value_numeric/value_jsonb/value_range`, `unit`,
`confidence`, valid-time, external `ref_*`).

---

## 8. Ingest semantics

- **Skip the bad item.** A malformed item, an edge referencing an unknown `key`,
  an unknown subject/episode type, etc. → that single item is skipped and
  recorded; the rest of the object still ingests. (Per-item subtransactions.)
- **Trust the names.** Resolve subject/verb by exact canonical name or alias;
  create only if absent. No fuzzy matching, no dedup beyond exact identity.
- **No review.** Everything lands live.
- **Order of operations:** document/source → subjects → verbs → episodes → edges
  → relationships → (claims → facts). So edges can resolve every `key`.
- **Idempotency:** subjects/verbs upsert by canonical name; statements upsert on
  SVO identity; attributes upsert on `(target, attr_name)`; episodes per
  DECISION E.
- **Embeddings:** never computed here (deferred worker).

### Return value (report)

```json
{
  "source": { "kind": "document", "id": 1234 },
  "created":  { "subjects": 2, "verbs": 1, "episodes": 1, "edges": 3, "relationships": 1,
                "node_attributes": 4, "edge_attributes": 5 },
  "resolved": { "subjects": 1, "verbs": 2 },
  "ids":      { "oracle21c": 44, "billing": 45, "kickoff": 12 },  // key -> created/resolved id
  "skipped":  [ { "section": "edges", "index": 2, "reason": "unknown object key 'foo'" } ]
}
```

---

## 9. Proposed ingest entry point (one call)

```
maludb_memory_ingest_extraction(
    p_extraction  jsonb,                       -- the object in this contract
    p_source_kind text   DEFAULT 'document',   -- used with p_source_id when no "document" block
    p_source_id   bigint DEFAULT NULL,
    p_provenance  text   DEFAULT 'provided'    -- ⚠ DECISION D: 'provided' vs 'accepted'
) RETURNS jsonb   -- the report in §8
```

Approach 1 (your API server) becomes: upload raw text (or pass the `document`
block) → call this once with the LLM's JSON → done. No project-side LLM.

---

## 10. Open decisions (need your call before I build)

- **C — claims/facts in v1, or fast-follow?** They're a heavier subsystem
  (`pending_claim` / `claim` / `fact`). Proposal: **v1 = the full core**
  (subjects, verbs, episodes, edges, node+edge attrs, relationships, external
  refs); **claims/facts as a fast-follow** once the core contract is proven.
- **D — provenance value** for these no-review edges: `provided` (proposed
  default) or `accepted` (matches the existing `zozocal` API hand-off doc)?
- **E — episode idempotency:** dedup on `(kind, title, occurred_at)` (proposed)
  or always create new?
- **Hints:** confirmed dropped as a DB concept — the external extractor bakes
  hint context into explicit subjects/edges in the object (e.g. *install episode
  → part_of → Drajeo project*). Say the word if you instead want a `context`
  block the DB auto-links.

---

## 11. Worked example

Raw text: *"We performed the Oracle 21c upgrade for the Drajeo project on Sunday
March 30 at 11 pm; it depends on the billing API."* (hint: project = Drajeo)

```json
{
  "document": { "title": "Sunday maintenance log", "content_text": "We performed the Oracle 21c upgrade …", "document_type": "log" },
  "subjects": [
    { "key": "oracle21c", "name": "Oracle Database 21c", "type": "software",
      "aliases": ["Oracle 21c"],
      "attributes": [ { "attr_name": "version", "value_text": "21c" } ] },
    { "key": "billing", "name": "Billing API", "type": "software" },
    { "key": "drajeo", "name": "Drajeo", "type": "project" }      // from the hint, as an explicit subject
  ],
  "episodes": [
    { "key": "upg", "kind": "Incident", "title": "Oracle 21c upgrade",
      "occurred_at": "2026-03-30T23:00:00-05:00" }
  ],
  "edges": [
    { "subject": "upg", "subject_kind": "episode_object", "verb": "upgrade",
      "object": "oracle21c", "object_kind": "subject",
      "attributes": [ { "attr_name": "status", "value_text": "completed" } ],
      "source_span": "We performed the Oracle 21c upgrade … 11 pm", "confidence": 0.94 },
    { "subject": "upg", "subject_kind": "episode_object", "verb": "part_of",
      "object": "drajeo", "object_kind": "subject" },             // the hint, as a real edge
    { "subject": "upg", "subject_kind": "episode_object", "verb": "generated_by",
      "object": "$source", "object_kind": "document" }
  ],
  "relationships": [
    { "from": "oracle21c", "to": "billing", "relationship_type": "depends_on" }
  ]
}
```
One call to `maludb_memory_ingest_extraction(…)` creates: the document, 3
subjects (+1 node attribute), 1 episode, the verbs `upgrade`/`part_of`/
`generated_by`, 3 edges (+1 edge attribute), and 1 subject relationship — and
returns the report in §8.
