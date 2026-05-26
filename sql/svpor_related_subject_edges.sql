\set ECHO all
\pset format unaligned
SET client_min_messages = WARNING;
CREATE EXTENSION IF NOT EXISTS maludb_core CASCADE;

SET search_path TO maludb_core, public;

DROP SCHEMA IF EXISTS svpor_edge_a CASCADE;
DROP ROLE IF EXISTS svpor_edge_user;

CREATE ROLE svpor_edge_user NOLOGIN;
GRANT maludb_memory_executor TO svpor_edge_user;
GRANT USAGE ON SCHEMA maludb_core TO svpor_edge_user;
CREATE SCHEMA svpor_edge_a AUTHORIZATION svpor_edge_user;

SET ROLE svpor_edge_user;
SET search_path TO svpor_edge_a, maludb_core, public;
SET TIME ZONE 'UTC';

SELECT object_count > 0 AS enabled
FROM maludb_core.enable_memory_schema();

-- subjects ------------------------------------------------------------
INSERT INTO maludb_subject(subject_type, canonical_name)
VALUES ('person', 'Mary')
RETURNING subject_id AS mary_id \gset

INSERT INTO maludb_subject(subject_type, canonical_name)
VALUES ('project', 'Zozocal')
RETURNING subject_id AS zozocal_id \gset

INSERT INTO maludb_subject(subject_type, canonical_name)
VALUES ('person', 'Sam')
RETURNING subject_id AS sam_id \gset

-- relationship-type catalog (inverse target must exist first) --------
SELECT maludb_relationship_type_add('has project manager') AS t1;
SELECT maludb_relationship_type_add('project manager of', 'A manages project work for B', 'has project manager') AS t2;
SELECT maludb_relationship_type_add('advisor to', 'A advises B') AS t3;

SELECT relationship_type, inverse_relationship_type
FROM maludb_relationship_type
ORDER BY relationship_type;

-- Mary was 'project manager of' Zozocal for calendar 2025 ------------
SELECT edge_id AS pm_edge_id
FROM maludb_related_subject_edge_add(
    :mary_id, :zozocal_id, 'project manager of',
    '2025-01-01'::timestamptz, '2026-01-01'::timestamptz, 'Q1-Q4 engagement') \gset

SELECT from_subject_label, to_subject_label, relationship_type, valid_from, valid_to, label
FROM maludb_related_subject_edge
ORDER BY edge_id;

-- header is auto-synced: with no currently-valid edge it falls back to
-- the most recent edge's type.
SELECT subject_a_label, subject_b_label, relationship_type
FROM maludb_related_subject
ORDER BY subject_a_label, subject_b_label;

-- point-in-time reads -------------------------------------------------
\echo '-- as_of 2025-06-01 (inside window): present --'
SELECT from_subject_name, to_subject_name, relationship_type, is_current
FROM maludb_related_subject_edges(:mary_id, '2025-06-01'::timestamptz)
ORDER BY edge_id;

\echo '-- as_of 2024-06-01 (before window): empty --'
SELECT count(*) AS rows_before
FROM maludb_related_subject_edges(:mary_id, '2024-06-01'::timestamptz);

\echo '-- as_of 2026-06-01 (after window): empty --'
SELECT count(*) AS rows_after
FROM maludb_related_subject_edges(:mary_id, '2026-06-01'::timestamptz);

-- direction filter: Zozocal is the target of the PM edge -------------
\echo '-- zozocal as to-subject: one edge --'
SELECT from_subject_name, to_subject_name, relationship_type
FROM maludb_related_subject_edges(:zozocal_id, NULL, NULL, 'to')
ORDER BY edge_id;

\echo '-- zozocal as from-subject: none --'
SELECT count(*) AS zozocal_as_from
FROM maludb_related_subject_edges(:zozocal_id, NULL, NULL, 'from');

-- an ongoing relationship: advisor to, open-ended from 2026-02-01 ----
SELECT edge_id AS advisor_edge_id
FROM maludb_related_subject_edge_add(
    :mary_id, :zozocal_id, 'advisor to',
    '2026-02-01'::timestamptz, NULL, 'ongoing advisory') \gset

\echo '-- header now reflects the currently-valid advisor edge --'
SELECT subject_a_label, subject_b_label, relationship_type
FROM maludb_related_subject
ORDER BY subject_a_label, subject_b_label;

\echo '-- the open-ended advisor edge is currently valid --'
SELECT relationship_type, is_current
FROM maludb_related_subject_edges(:mary_id, NULL, 'advisor to')
ORDER BY edge_id;

-- closing an edge sets its end at a point in time --------------------
SELECT maludb_related_subject_edge_close(:advisor_edge_id, '2026-03-01'::timestamptz) AS closed;
SELECT maludb_related_subject_edge_close(:advisor_edge_id, '2026-03-01'::timestamptz) AS closed_again_idempotent;

\echo '-- advisor edge no longer valid as of 2026-04-01 --'
SELECT count(*) AS advisor_after_close
FROM maludb_related_subject_edges(:mary_id, '2026-04-01'::timestamptz, 'advisor to');

-- overlap is rejected for the same directed, typed relationship ------
DO $$
DECLARE
    v_mary    bigint := (SELECT subject_id FROM maludb_subject WHERE canonical_name = 'Mary');
    v_zozocal bigint := (SELECT subject_id FROM maludb_subject WHERE canonical_name = 'Zozocal');
BEGIN
    PERFORM maludb_related_subject_edge_add(
        v_mary, v_zozocal, 'project manager of',
        '2025-06-01'::timestamptz, '2025-09-01'::timestamptz);
    RAISE EXCEPTION 'overlapping edge was not rejected';
EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'OK: overlapping edge rejected';
END;
$$;

-- self-link rejected --------------------------------------------------
DO $$
DECLARE
    v_mary bigint := (SELECT subject_id FROM maludb_subject WHERE canonical_name = 'Mary');
BEGIN
    PERFORM maludb_related_subject_edge_add(v_mary, v_mary, 'advisor to');
    RAISE EXCEPTION 'self-link was not rejected';
EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE 'OK: self-link rejected';
END;
$$;

-- unknown relationship_type rejected by the catalog FK ---------------
DO $$
DECLARE
    v_mary    bigint := (SELECT subject_id FROM maludb_subject WHERE canonical_name = 'Mary');
    v_zozocal bigint := (SELECT subject_id FROM maludb_subject WHERE canonical_name = 'Zozocal');
BEGIN
    PERFORM maludb_related_subject_edge_add(v_mary, v_zozocal, 'no_such_type');
    RAISE EXCEPTION 'unknown relationship_type was not rejected';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK: unknown relationship_type rejected';
END;
$$;

-- missing subject rejected -------------------------------------------
DO $$
DECLARE
    v_mary bigint := (SELECT subject_id FROM maludb_subject WHERE canonical_name = 'Mary');
BEGIN
    PERFORM maludb_related_subject_edge_add(v_mary, 999999999, 'advisor to');
    RAISE EXCEPTION 'missing subject was not rejected';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK: missing subject rejected';
END;
$$;

-- renaming a subject refreshes denormalized edge labels --------------
UPDATE maludb_subject SET canonical_name = 'Zozocal Inc' WHERE subject_id = :zozocal_id;

\echo '-- edge labels follow the rename --'
SELECT from_subject_label, to_subject_label, relationship_type
FROM maludb_related_subject_edge
ORDER BY edge_id;

-- deleting an edge re-syncs the header -------------------------------
SELECT maludb_related_subject_edge_delete(:advisor_edge_id) AS advisor_deleted;

\echo '-- header falls back to the remaining PM edge --'
SELECT subject_a_label, subject_b_label, relationship_type
FROM maludb_related_subject
ORDER BY subject_a_label, subject_b_label;

SELECT maludb_related_subject_edge_delete(:pm_edge_id) AS pm_deleted;

\echo '-- no edges remain: header type is cleared but the pair stays --'
SELECT subject_a_label, subject_b_label, relationship_type
FROM maludb_related_subject
ORDER BY subject_a_label, subject_b_label;

\echo '-- deleting a subject cascades to its edges --'
SELECT count(*) AS created_mary_sam_edge
FROM maludb_related_subject_edge_add(
    :mary_id, :sam_id, 'advisor to',
    '2026-01-01'::timestamptz, NULL);

DELETE FROM maludb_subject WHERE subject_id = :sam_id;

SELECT count(*) AS edges_touching_sam
FROM maludb_related_subject_edge
WHERE from_subject_id = :sam_id OR to_subject_id = :sam_id;

-- cleanup -------------------------------------------------------------
RESET ROLE;
SET search_path TO maludb_core, public;

DELETE FROM malu$svpor_subject_relationship_edge WHERE owner_schema = 'svpor_edge_a';
DELETE FROM malu$svpor_subject_relationship WHERE owner_schema = 'svpor_edge_a';
DELETE FROM malu$svpor_relationship_type WHERE owner_schema = 'svpor_edge_a';
DELETE FROM malu$svpor_subject WHERE owner_schema = 'svpor_edge_a';
DELETE FROM malu$enabled_schema_object WHERE schema_name = 'svpor_edge_a';
DELETE FROM malu$enabled_schema WHERE schema_name = 'svpor_edge_a';
DROP SCHEMA svpor_edge_a CASCADE;
DROP OWNED BY svpor_edge_user;
DROP ROLE svpor_edge_user;
