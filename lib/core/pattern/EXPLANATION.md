# Core Pattern Engine — Explanation (Gate 0)

## Purpose

The Pattern Engine converts a recurring shift pattern (template + cadence) into
concrete shift occurrences over a date range, then applies user overrides to
individual occurrences. It is a **render-time projection engine**: the pattern
plus the override log are the source of truth; the effective schedule is
computed on demand and never mutates its inputs (INVARIANT-001).

## Architecture (Gate 0 contract)

```
ShiftPattern (VersionedEntity: effectiveFrom/effectiveUntil)
    ↓
projectOccurrences(pattern, range, templates)
    → ProjectionResult { occurrences: 100% resolved ShiftOccurrence[],
                         issues: RenderIssue[] }
    ↓
applyOverride(occurrences, override, { templates })
    → OverrideResult { occurrences, issues }      // one override at a time
    ↓  (repeated over the override chain in list order)
renderEffectiveSchedule(pattern, overrides, range, templates)
    → ScheduleRenderResult { occurrences, issues }
```

Key type changes vs. the pre-Gate-0 API:

- `ResolvedOccurrence` (one object mixing success + error) is **removed** from
  the public API. `projectOccurrences` returns `ProjectionResult`; unresolved
  days live in `.issues` and never become occurrence objects (P0-3 / D1
  resolved-only domain).
- `EffectiveOccurrence` is **removed**: every `ShiftOccurrence` now carries its
  own `source` (OccurrenceSource) and `sourceOverrideId`, so no wrapper type or
  renderer-side guessing is needed (P0-5).
- `applyOverride` returns `OverrideResult` (P0-1) and receives the `templates`
  map so REPLACE/CREATE/SWAP can resolve times (D3).

## Key Functions

### 1. `projectOccurrences(...) -> ProjectionResult`

Walks the range day by day in UTC calendar arithmetic, maps each day to its
cycle position (anchored on `pattern.anchorDate`), and resolves the template's
local times through `core/time resolveShift()`.

- **Resolved-only (D1):** a successful resolution produces a
  `ShiftOccurrence` with `source: baseline`; any failure (DST gap/overlap,
  MISSING_TEMPLATE, invalid input) produces a `RenderIssue` — never a
  half-empty object.
- Overnight end-date handling (`+1` suffix / `endHour < startHour`) lives
  **only** in `core/time` (INVARIANT-002).
- Template ids the pattern references but the caller did not provide are
  surfaced as `MISSING_TEMPLATE` issues — never silently skipped days.

### 2. `applyOverride(occurrences, override, {templates}) -> OverrideResult`

Six operations. Every operation that changes time resolves through
`core/time` FIRST and only then builds new occurrences — no empty-UTC objects
exist even transiently (P0-1/P0-2 fixes).

| Operation | Behavior (Gate 0) |
|---|---|
| `create` | New occurrence resolved from `CreatePayload.date/startTime/endTime/timezone`; `source: created`; requires `CreatePayload.timezone` (D3). |
| `update` | >= 1 of {templateId, startTime, endTime}; missing fields keep current values derived from stored UTC via the occurrence's own timezone. **P0-2:** if civil time intent is unchanged, stored UTC is preserved bit-for-bit and the resolver is NOT called again (re-resolving an occurrence created inside a DST overlap would spuriously fail). |
| `replace` | Template switch; time = `overrideTime` or new template's default times (missing template -> `MISSING_TEMPLATE`). Same-time replace preserves UTC. |
| `split` | Parts resolved independently; **H-1 invariants** on resolved UTC (parts chronological, non-overlapping, inside the original envelope; midnight boundary between consecutive parts allowed). Any violation or resolution failure fails the WHOLE split atomically. Part ids: `{original}#p{i}`. |
| `swap` | Exchanges shiftDate + template + local civil intent between two occurrences; both must share job AND timezone (`SWAP_CROSS_JOB` otherwise, D5); each side re-resolves in its OWN timezone; ids/timezones never change (INVARIANT-007); atomic. |
| `delete` | Removes the occurrence from the view. **D6:** no soft-delete flag — the Override record itself is the audit trail and undo source. |

Error behavior (never a silent no-op):

- Any non-CREATE operation whose `occurrenceId`/`swapWithOccurrenceId` is
  missing -> `OCCURRENCE_NOT_FOUND`, input list returned unchanged (P0-4).
- Any DST / validation failure -> `OverrideResult(occurrences: input unchanged,
  issues: [...])`.
- After every successful operation, duplicate ids in the resulting list are
  reported as `DUPLICATE_OCCURRENCE_ID` warnings (M3).

### 3. `renderEffectiveSchedule(...) -> ScheduleRenderResult`

1. `projectOccurrences` (resolved-only).
2. Apply each override **in list order on the evolving state** (P0-6):
   a failure keeps the state from the previous override, contributes its
   issue, and does NOT roll back earlier successes or block later overrides.
   An override may target an occurrence created by an earlier override in the
   same chain (e.g. UPDATE of a SPLIT part id).
3. Whole-view duplicate-id scan (M3).
4. Deterministic sort by shiftDate, then id.

## Provenance (P0-5)

`OccurrenceSource` is a first-class field assigned **at the operation site**:

- `projectOccurrences` -> `baseline`
- `CREATE` -> `created`
- `UPDATE/REPLACE/SPLIT/SWAP` -> `modified` (chain rule: the last override to
  touch an occurrence wins; a `created` occurrence later updated becomes
  `modified`)

`sourceOverrideId` is audit trail only (which override touched it last) and is
NEVER used to derive `source`. Baseline occurrences carry `null`.

## Versioning (D1 + D9)

`VersionedEntity` gives `effectiveFrom`/`effectiveUntil`. `createNewVersion`
closes the old version (`effectiveUntil = day before the new effectiveFrom`)
and returns a fresh pattern.

**D9 — anchorDate phase continuity:** the new version KEEPS the original
version's `anchorDate`. Resetting it to `newEffectiveFrom` would silently
re-phase the cycle (e.g. a 4-on/4-off roster would restart on the wrong day).
Changing the actual phase requires a NEW pattern id, not a new version.

## Invariants

- **INVARIANT-001:** inputs are never mutated; every operation returns a new list.
- **INVARIANT-002:** all time math (duration, end-date) is delegated to
  `core/time`; never duplicated here.
- **INVARIANT-003:** recurrence is anchored on local civil dates.
- **INVARIANT-007:** timezone never changes after creation and is never copied
  between occurrences (SPLIT keeps the original's; SWAP keeps each side's own).

## Edge Cases

1. **DST day in a projected range:** the ambiguous/nonexistent day is a
   `RenderIssue`, not an occurrence — the schedule shows a gap with a reason.
2. **Override targeting a missing occurrence:** `OCCURRENCE_NOT_FOUND`.
3. **Occurrence created inside a DST overlap, then renamed:** metadata-only
   UPDATE preserves the stored UTC (P0-2) instead of failing on re-resolution.
4. **Overnight SPLIT across midnight:** two parts meeting at `00:00` local on
   consecutive days — a legal envelope boundary.
5. **Multiple overrides on one occurrence:** applied in chain order; last
   successful operation wins and becomes the `sourceOverrideId`.
