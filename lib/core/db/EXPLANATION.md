# Persistence layer (Gate 3) — EXPLANATION

Scope: local SQLite persistence for every entity that already has a domain
model in `lib/core/` (plan4_gate3_persistence.md). The DB **never fabricates
domain results** — every read path re-derives through the pure engines.

## Architecture

- **Driver**: `package:sqlite3` (FFI) — no codegen, no drift. Migration via
  `PRAGMA user_version` (`lib/core/db/db.dart`, `migrate()`). Schema v2 adds
  `overrides.patternId` (a v1 DB upgrades in place — upgrade-path tested).
- **Seam**: `DatabaseOpener` typedef + `defaultOpener(path, key)`. Production
  on-disk encryption is SQLCipher (plan2 §6.1, INVARIANT-008); the opener
  runs `PRAGMA key` when a `key` is supplied. Tests/CI use plain `:memory:` —
  we do not fake encryption.
- **Repositories** (all take `Database`; one tx per write):
  - `PatternRepository` — jobs, shift templates, shift patterns + sequence
    (child rows, not JSON blobs).
  - `ScheduleRepository` — occurrences, append-only override log, pay
    snapshots, `renderJobSchedule`.
  - `PayRuleRepository` — versioned pay rules + differential/OT children.
  - `ImportRepository` — import sessions + candidates (audit trail).

## Locked rules

- **Append-only history** (plan3_final Gate 2): the override log is never
  edited or deleted. `saveOverride` is idempotent by deterministic id; a
  *different* override reusing an id is rejected loudly. Occurrences are
  upserted on re-render (temporal refresh) but historical pay snapshots are
  never touched by that path.
- **INVARIANT-006**: `setPayEstimateSnapshot` writes `actualPayEstimate` +
  `payEstimateFrom` once; rewriting to a different amount throws
  `ImmutableHistoryError`. Re-render refreshes temporal fields only.
- **Identity**: every table has a `uuid` PK plus the domain `id` as a
  UNIQUE deterministic column (plan4 §Identity), so replay is idempotent and
  imports/overrides keep stable references.
- **No fabrication**: `renderJobSchedule` loads the active pattern version +
  the stored override log and runs the *pure* `projectOccurrences` /
  `applyOverride` engine; whatever the engine returns is what gets persisted.
- **No UPDATE/DELETE of the past**: changing a schedule means writing a new
  override (audit trail), never editing an old row.

## Override replay

`OverridePayloadCodec` (override_codec.dart) maps the 6 typed payloads
(create/update/delete/replace/split/swap) to/from JSON 1:1 with
`pattern_types.dart` — replaying a stored override log through the pure
engine reproduces the same schedule as the in-memory chain (parity tested).

## CREATE convention (official, schema v2)

A CREATE override produces an occurrence whose id IS the override id — it is
NOT rooted to any baseline occurrence, so the render-time log filter cannot
scope it by baseline occurrence root (an OFF-day create has no root at all,
and anchoring it to a nearby baseline id made survival depend on which
baseline occurrences share the render range — silently lost otherwise).

- `saveOverride(override, patternId: ...)` REQUIRES `patternId` for CREATE
  (thrown loudly otherwise) and records it on the row.
- The render admits a CREATE iff its pattern is rendered in the range AND its
  payload date falls inside the range (`_createInRender`); an admitted
  CREATE's id joins the allowed-root set so later overrides can chain onto
  the created occurrence.
- Targeted ops (update/delete/replace/split/swap) are still admitted by
  baseline occurrence root (split parts `<root>#pN`, chains included);
  overrides of other patterns/jobs are excluded; an admitted override that
  finds no target at apply time surfaces as an engine issue — never silent.

## Test strategy

## Snapshot provenance

`ShiftOccurrence.payEstimateFrom` (new optional field) records which pay-rule
version produced `actualPayEstimate`, loaded from the DB `payEstimateFrom`
column. Pure renderers ignore it (they never see snapshots unless set);
persistence is the only writer, enforcing INVARIANT-006.

## Out of scope (backlog)

- CalendarEvent model (no domain model yet) — no table until the model lands.
- Incremental materialized view / cache-view layer.
- Backup/restore UI.
- SQLCipher native verification (needs a SQLCipher-linked lib; the seam is in
  place and CI/tests run plain SQLite — no fake encryption).

## Test strategy

`test/core/db/db_test.dart` (12 tests): migration idempotence + FK
enforcement + v1→v2 upgrade path; repo round-trips (template/pattern/
sequence/occurrences keep resolved UTC); versioned pay-rule lookup at a date
(INVARIANT-006); override persistence + replay parity; chained overrides
(split → update part) survive re-render; pay-snapshot immutability across a
re-render; import session audit reload; job isolation (no leakage between
jobs). All in-memory, no native deps beyond libsqlite3. The db↔pattern
integration suite covers version-boundary renders (D9 anchor continuity) and
a full 6-op replay including the official CREATE convention (OFF-day create
survives any range containing its date; job isolation for CREATE; missing
patternId refused).
