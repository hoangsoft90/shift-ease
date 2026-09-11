# Core Import Pipeline — Explanation (Gate 2)

## Purpose

Turns a roster document (pasted text or CSV today) into reviewable shift
candidates, then — only after explicit user confirmation — into UTC-resolved
committed shifts. The engine is pure and deterministic: it never touches the
calendar, pattern, or persistence layers, and it never resolves time itself.

## Architecture

```
rawText / rawCsv (+ job templates, user-chosen referenceDate, timezone)
        │  parseDocument(sourceType, ...)
        ▼
 RawExtraction (audit-faithful: one RawEntry per line, verbatim text)
        │  _interpret()  (date pinning + template suggestion + confidence)
        ▼
 ImportSession { state, candidates }        state: IDLE→PARSING→EXTRACTED
        │  applyReview / bulkAcceptHigh      (→ REVIEWING)
        ▼
 APPROVED/MODIFIED candidates only
        │  commitImport()  — atomic; resolveShift() per candidate (core/time)
        ▼
 CommitResult { shifts (UTC-resolved), session: COMMITTED }

 computeImportDiff(previous, next)   — "What changed?" for re-imports
```

## Locked semantics

### 1. State machine (plan2 §3.1)

`IDLE → PARSING → EXTRACTED → REVIEWING → COMMITTED`, with a recoverable
`ERROR` from PARSING or any illegal transition. The full transition path is
recorded on `ImportSession.history` (starts `[idle]`) — the audit trail behind
the golden `stateTransitions` assertions.

### 2. INVARIANT-004 — no auto-commit, ever

Every candidate starts `PENDING`. `parseDocument` never commits anything.
`bulkAcceptHigh` (the "Accept All High" button) approves ONLY `HIGH`
candidates — MEDIUM/LOW stay `PENDING` for the human. `commitImport` is a
separate, explicit step that only looks at APPROVED/MODIFIED candidates.

### 3. Commit is atomic and UTC-resolved (INVARIANT-002)

All approved shift candidates are validated first, then each is resolved with
`resolveShift()` from core/time (`shiftDate` + local start/end + job timezone).
If ANY approved candidate is unresolvable (missing date/time, DST gap/overlap,
end-before-start), the whole commit aborts with `COMMIT_UNRESOLVED` and zero
changes — the same fail-atomic discipline as override chains (P0-6).

The committed output is a `CommittedShift` (candidateId, deterministic
`occurrenceId = 'occ-<candidateId>'`, resolved `startDateTimeUtc`/
`endDateTimeUtc`, timezone). **Boundary:** materializing these into
`ShiftOccurrence` objects (which require a `patternId`) is the calendar
layer's job in the persistence gate — the import engine does not fabricate
occurrences.

### 4. Confidence scoring (plan2 §3.2 Bước 2 matrix)

Overall confidence = the **weakest** factor (low=2 > medium=1 > high=0):

| Factor | HIGH | MEDIUM | LOW |
|---|---|---|---|
| Date | pinned to a real calendar date vs the user-chosen `referenceDate` | — | not pinnable |
| Time | shift has both start+end (OFF lines don't need times) | — | missing |
| Type | label stated ("Day"/"Night"/"OFF") | inferred from an exact template time match | neither |

A missing type label demotes a perfectly clear date+time line to MEDIUM
(IMPORT-006); an unpinnable date demotes everything to LOW (IMPORT-002);
a line with uninterpretable tokens is LOW (never silently trusted).

### 5. Date resolution is anchored, never guessed

Ambiguous tokens ("Sep 03", "Mon 3rd", "03/09") resolve against the
`referenceDate` the user picks for the roster period. The engine never reads
the system clock (deterministic goldens), never reaches into a PAST month for
a weekday+day mismatch (that would silently rewrite history), and rejects
non-existent calendar dates (M1: "2026-02-31" is an error, not March 3).

### 6. OFF days and re-import diff

- An OFF line becomes an OFF candidate (no times, no template); committing an
  approved OFF records the rest day but creates no occurrence.
- `computeImportDiff` keys rosters by date; two dates that exchanged content
  between the old and new roster are reported as a symmetric SWAPPED pair, not
  two unrelated CHANGED entries (the shape real employer rosters produce when
  people trade days). Impact carries net signed hours + day counts; income
  impact is intentionally null here (needs the active PayRule, which the
  calendar layer computes on the real schedule).

### 7. OCR is gated behind the M4.5 spike test

`IMAGE`/`PDF` sources return a recoverable `OCR_PENDING_SPIKE` error. Per the
locked milestone (features.md M4.5: >=70% dates, >=60% shift types on 20-30
real rosters), no OCR architecture is built before real rosters prove the
pipeline. Paste-text and CSV — the goldens IMPORT-001..008 — are fully
implemented.

## Spec deviations (approved by Gate-2 review)

- **D-1 — template match is NOT a confidence driver.** plan2 §3.2's matrix lists
  "template match" as a factor (HIGH: one exact template; LOW: none). The
  engine deliberately treats the template as a *suggestion only*: a line with a
  stated type + clear date + clear times is HIGH-confidence DATA even when it
  matches no stored template (template libraries change, jobs get renamed,
  users map later). Template match still drives the inferred-type MEDIUM
  demotion when the line has no label at all (IMPORT-006) and always fills
  `templateId` for the review UI.
- **D-2 — `?` / unknown markers are never type labels** (fixed + tested): in
  both text and CSV parsing an explicit `?` means "uncertain", so the
  candidate stays LOW — it can never be auto-approved by bulk actions.

## Invariants honored

- **INVARIANT-004** — commit only after explicit user actions (section 2).
- **INVARIANT-002** — committed UTC comes from core/time `resolveShift()`
  (section 3); the diff's hours are wall-clock deltas on top of that.
- **INVARIANT-001** — sessions are immutable; every action returns a new
  session copy (no mutation of a parsed session).

## Golden authoring fixes (Gate 2, documented + verified)

- **IMPORT-002** — the input has 3 ambiguous lines; the audit-faithful parser
  emits one LOW candidate per line. Old expected listed 1 — fixed to 3 (all
  LOW, all PENDING).
- **IMPORT-003** — candidates carried no date/times, so the commit flow could
  not actually resolve UTC. Added real data (Day/Night/OFF) + `jobTimezone`.
- **IMPORT-001 / IMPORT-006** — expected candidates now carry stable ids
  (`cand-1..N`) matching the engine's deterministic ids.

## Files

| File | Content |
|---|---|
| `import_types.dart` | `ImportSession`, `ImportState`, `CandidateShift`, `Confidence`, `ReviewStatus`, `RawExtraction`, `CommittedShift`, `ImportError` (+`ImportErrorCodes`), `ImportDiff`/`DiffEntry` |
| `import_parser.dart` | `parseTextRoster`, `parseCsvRoster`, `resolveDateToken`, `normalizeTimePair` |
| `import_engine.dart` | `parseDocument`, interpretation + confidence, `applyReview`, `bulkAcceptHigh`, `commitImport`, `computeImportDiff` |

## Testing

`test/core/import/import_engine_test.dart` drives all 8 golden cases from
`test/golden/import_pipeline_cases.json` (IMPORT-001..008) plus unit tests for
the OCR gate, commit atomicity, user modify, illegal-state transitions, date
resolution rules and overnight time normalization. `scripts/verify_import_cases.mjs`
independently checks structural + arithmetic consistency (18 checks, Errors: 0).
CI runs the import suite in `.github/workflows/test.yml` (`import-tests` job).
