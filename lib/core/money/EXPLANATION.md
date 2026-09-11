# Core Money Engine — Explanation (Gate 1)

## Purpose

The Money Engine turns a worked shift (its duration plus calendar qualifiers)
into an itemized pay breakdown under a versioned `PayRule`. It is deliberately
pure: timezone/date derivation and work-week grouping happen upstream (the
calendar layer); the engine receives resolved hours and qualifiers through
`PayInput` and never reaches into time/pattern internals for money math.

## Architecture

```
PayInput (shiftHours, dailyHours, weeklyHours, qualifiers, window times)
        + PayRule (versioned: baseHourlyRate, differentials, overtimeRules)
                        ↓
      calculatePayBreakdown(input, rule) → PayBreakdown { lines, total }

getActivePayRule(rules, jobId, date)   // INVARIANT-006 — rule active at date
allocateWeeklyOvertime(shifts, threshold)  // LIFO — Map<id, otHours> (PAY-014)
```

## Locked calculation semantics

### 1. Method B — regular and overtime separated (no double-counting)

- `overtimeHours` comes from the rules (or a pre-assigned LIFO allocation).
- `regularHours = shiftHours − overtimeHours`.
- Regular line: `regularHours × baseRate`.
- Overtime line: `overtimeHours × baseRate × multiplier` — the overtime hours
  are paid once, at the overtime rate. They are NOT in the regular line too
  (that would be the (1 + multiplier)x double-count bug fixed in plan2 review).

### 2. Multi-rule overtime — max(), never the sum (plan2 §5.4)

For every overtime rule evaluate its own trigger:

| Period | Trigger hours |
|---|---|
| SHIFT | `shiftHours − threshold` |
| DAY | `dailyHours − threshold` (attributed to the shift being evaluated) |
| WEEK | `weeklyHours − threshold` (attributed to the shift being evaluated) |

`overtimeHours = max(...)` across the applicable components — the same hours
must not be paid twice when a shift trips both a SHIFT and a WEEK rule. When
two components tie on OT hours, the higher multiplier wins (plan2 §5.4
example: a x1.0 shift rule and a x1.5 week rule both yielding 2h → paid at
x1.5).

WEEK overage attributed to the evaluated shift is capped at the shift's own
duration. For a REAL multi-shift week, use `allocateWeeklyOvertime` first and
pass each shift its LIFO share through `PayInput.assignedOvertimeHours` (see
PAY-014).

### 2b. Composition — MAX over two independent components (no double-count, no under-count)

Per-shift overtime is the MAX of two components, never their sum and never a
replace-one-by-the-other either:

| Component | Source |
|---|---|
| SHIFT/DAY | evaluated on this shift's own context (its hours / its day totals) |
| WEEK | the share attributable to THIS shift: the LIFO allocation when
`assignedOvertimeHours` is provided (authoritative, 0 means this shift absorbs
none of the week's overage), else the WEEK overage directly (single-shift
context, PAY-005) |

Why this matters: with a CA-style rule set (SHIFT>8h AND WEEK>40h) in a real
multi-shift week, the LIFO share often sits BELOW a shift's own daily OT (e.g.
3x14h week: 6h daily OT per shift vs a 2h weekly share on the absorbing
shift). Treating the assigned share as a replacement would silently drop the
daily OT (underpay); summing would pay the overlapping hours twice. Taking the
MAX prices each hour exactly once at the winning basis. Locked by unit tests
(`assigned WEEK share composes with SHIFT rule via MAX`) and by the
pattern→money integration CA scenario (3x14h week → $1785).

### 3. Differentials apply to REGULAR hours only

A differential never multiplies overtime hours (locked in plan2 §5.2/5.7 and
asserted by every golden case that combines diffs with OT, e.g. PAY-007/012).
Applicable hours for `ALL_HOURS_IN_SHIFT` = regular hours when the shift
qualifies (night/weekend/holiday/tag). For `HOURS_IN_WINDOW` the hours are the
wall-clock overlap between the shift and a possibly-midnight-wrapping window
(e.g. 22:00 → 06:00), capped at regular hours.

### 4. Window overlap is half-open wall-clock arithmetic (PAY-013)

`windowOverlapHours` anchors both the shift and the window at the shift's
local midnight and computes `max(0, min(shiftEnd, winEnd) − max(shiftStart,
winStart))` in absolute minutes. Ends no later than their start (an explicit
`+1` marker, or 06:00 after 22:00) wrap past midnight. PAY-013: shift
15:00→03:00+1 vs window 22:00→06:00 → overlap 5h (22:00–03:00). *(The golden
file originally said 6h — an authoring error confirmed by independent
computation and approved by the user to fix to 5h.)*

### 5. LIFO weekly allocation (plan2 §5.7)

When a week exceeds the WEEK threshold, overtime is attributed to the
chronologically LAST shift first, walking backwards; a shift too short to
absorb the remainder rolls the overflow to the previous shift. Deterministic,
no proportional splitting. PAY-014: 3×14h = 42h vs 40h → 2h on Friday; unit
test covers the 14/14/14/1 overflow case (1h shift absorbs 1h, previous
shift absorbs the remaining 2h).

## Invariants

- **INVARIANT-005:** money semantics live ONLY on `PayRule` — `ShiftTemplate`
  is never consulted for pay. Templates (`PayRuleTemplate`) carry pay-rule
  material only.
- **INVARIANT-006:** pay is resolved from the `PayRule` active at the
  occurrence's date (`getActivePayRule`); a newer version never re-prices the
  past (PAY-011: v1 date always yields $385 even after v2 exists).
- Display principle (plan1 §7): every `PayBreakdown` carries the disclaimer
  "Estimate — not official payroll".

## Files

| File | Content |
|---|---|
| `money_types.dart` | enums + `PayDifferential`, `OvertimeRule`, `PayRule` (versioned), `PayInput`, `PayLine`, `PayBreakdown` |
| `money_engine.dart` | `calculatePayBreakdown`, window overlap, `getActivePayRule`, `allocateWeeklyOvertime` (+ decoupled hours core `allocateWeeklyOvertimeHours`) |
| `payrule_templates.dart` | `PayRuleTemplate` seed library (US-CA/NY/TX, UK NHS, DE) |

## Testing

`test/core/money/money_engine_test.dart` drives all 14 golden cases from
`test/golden/money_engine_cases.json` (PAY-001..014) plus unit tests for DAY
rules, higher-multiplier tie-breaking, the MAX composition of assigned WEEK
shares with SHIFT rules, window overlap, LIFO overflow and the no-double-count
arithmetic identity. `scripts/verify_money_cases.mjs` independently checks
every case's arithmetic consistency (15 checks, Errors: 0).

`test/core/integration/pattern_money_integration_test.dart` exercises the full
seam pattern → money: occurrences rendered by `projectOccurrences`, durations
derived from resolved UTC instants (INVARIANT-002), LIFO WEEK distribution
across the real week, per-shift breakdowns, and pay snapshots on occurrence
copies (`actualPayEstimate`) that never mutate the projected occurrences
(INVARIANT-001/006). Scenarios: WEEK-only 3x14h week → $1505 (mirrors
PAY-014), CA double-trigger 3x14h week → $1785 (composition), and a 22:00→06:00
night-window differential priced from template local times (7 x $308).

`test/core/integration/import_money_integration_test.dart` exercises the other
entry: a pasted roster → import COMMIT (UTC via core/time) → WEEK LIFO → pay.
It uses `allocateWeeklyOvertimeHours`, the decoupled hours-based allocation
core that both `allocateWeeklyOvertime` (pattern occurrences) and the import
output (`CommittedShift`) delegate to — no layer fabricates another layer's
types to reach the allocation. Scenarios: WEEK-only imported 3x14h → $1505,
CA composition → $1785, and INVARIANT-006 across a v1→v2 rate bump
(Aug week stays $1505; Sep week prices at $40 → $1720).
