# Time Engine — Architecture & Design Explanation

## Overview

The Time Engine is the foundation of ShiftEase. It handles the conversion between **local civil time** (what users see and think about) and **UTC instants** (what computers use for ordering and comparison). This separation is critical for correctly handling DST transitions, overnight shifts, and timezone changes.

## Core Concepts

### 1. Civil Time (Wall-Clock)

**What it is:** The time as displayed on a clock in a specific timezone.  
**Example:** `22:00 America/New_York`  
**Used for:** Recurrence, user intent, UI display.

Civil time is the basis of recurrence (INVARIANT-003). When a user says "I work 22:00 to 06:00", they mean 22:00 local time, regardless of DST or timezone. The pattern must always generate shifts at 22:00 local time.

### 2. UTC Instant

**What it is:** A specific point in time, independent of timezone.  
**Example:** `2026-03-08T03:00:00.000Z`  
**Used for:** Ordering events, calculating duration, triggering reminders.

UTC instants are the only reliable way to calculate duration (INVARIANT-002). Local time subtraction fails during DST transitions because the clock jumps forward or backward.

### 3. Elapsed Duration

**What it is:** The actual time that passed between two UTC instants.  
**Example:** `7.0 hours`  
**Used for:** Pay calculations, shift length display.

Duration is always calculated from UTC instants, never from local time subtraction. This is the most critical invariant in the Time Engine.

## DST Handling

### Spring-Forward (Clocks Jump Forward)

**Example:** US Eastern, March 8, 2026  
- Clocks jump from 2:00 AM EST to 3:00 AM EDT
- The hour from 2:00-3:00 AM **does not exist**

**Effect on shifts:**
- A shift from 22:00 Mar 7 to 06:00 Mar 8 (8h wall-clock) becomes **7h actual**
- The missing hour reduces the shift length

**Code behavior:**
- `resolveShift()` returns `duration.hours = 7.0`
- `startOffset` is EST (UTC-5), `endOffset` is EDT (UTC-4)

### Fall-Back (Clocks Repeat)

**Example:** US Eastern, November 1, 2026  
- Clocks repeat from 2:00 AM EDT back to 1:00 AM EST
- The hour from 1:00-2:00 AM **occurs twice**

**Effect on shifts:**
- A shift from 22:00 Oct 31 to 06:00 Nov 1 (8h wall-clock) becomes **9h actual**
- The repeated hour adds to the shift length

**Code behavior:**
- `resolveShift()` returns `duration.hours = 9.0`
- `startOffset` is EDT (UTC-4), `endOffset` is EST (UTC-5)

### Ambiguous Times

When a local time occurs twice (fall-back), the user must choose which interpretation they mean:
- **First occurrence:** Before the clock falls back (e.g., EDT)
- **Second occurrence:** After the clock falls back (e.g., EST)

**D4 compliance:** The Time Engine returns an error with both options for BOTH start time and end time ambiguity. It never auto-resolves — the user must always explicitly choose. This prevents silent errors where a shift is resolved to the wrong interpretation.

### Non-Existent Times

When a local time doesn't exist (spring-forward gap), the Time Engine returns an error and prompts the user to choose a nearby valid time.

## Resolution Algorithm (Gate 0 — DB-driven, no ±1h heuristic)

`resolveUtcInstant` classifies a local civil time by enumerating candidate UTC
instants from the `Location`'s OWN transition table (the `timezone` package):

1. **Validate first (M1):** timezone lookup failure -> `INVALID_TIMEZONE`;
   date must round-trip (`2026-02-31` -> `INVALID_DATE`, never silent
   rollover to Mar 3); hour/minute range-checked (`25:90` -> `INVALID_TIME`).
2. **Enumerate:** for every `zone` in `loc.zones`, candidate = naive wall-clock
   ms − `zone.offset` (offsets are in **milliseconds**). A candidate is real iff
   `loc.lookupTimeZone(candidate).timeZone.offset == zone.offset`
   (self-consistency: that offset is actually in effect at that instant).
3. **Classify:** 0 candidates -> `NONEXISTENT_LOCAL_TIME` (gap); 1 candidate ->
   resolved; >= 2 -> `AMBIGUOUS_LOCAL_TIME` with every candidate, sorted.

Why this matters:

- **Lord Howe (Australia/Lord_Howe) has 30-minute DST.** The old ±1h heuristic
  reported its fall-back options 60 minutes apart; this algorithm reports the
  correct 30-minute pair (`2026-04-04T14:45:00Z` and `...T15:15:00Z`). Golden
  case DST-009 locks this.
- `offset.inHours` would truncate +10:30 to +10; offsets are carried in ms
  and formatted as `+10:30` (LH-001 locks this).
- Validation happens BEFORE any timezone arithmetic, so a bad date can never
  be silently reinterpreted as a different valid day (M1).

### Error taxonomy (D7)

`ResolveResult.errorCode` is set ONLY for INVALID_* input failures
(INVALID_DATE / INVALID_TIME / INVALID_TIMEZONE). DST outcomes are expressed
through `ambiguity` (nonexistent/ambiguous), so "typed wrong" is never
confused with "clocks jumped" (P0-8).

## Invariant Compliance

### INVARIANT-002: Duration from UTC

```dart
// WRONG (violates INVARIANT-002):
final duration = localEndHour - localStartHour; // 8h during spring-forward

// CORRECT:
final duration = utcEnd.difference(utcStart); // 7h during spring-forward
```

### INVARIANT-003: Recurrence Basis

```dart
// WRONG:
// Pattern generates shifts based on device timezone

// CORRECT:
// Pattern generates shifts based on pattern's own timezone
// User in London with pattern in New York still gets 19:00 NY shifts
```

### INVARIANT-007: Timezone Retention

```dart
// WRONG:
// When user changes device TZ, update all occurrences

// CORRECT:
// Existing occurrences keep their original timezone
// Only new occurrences use the new timezone
```

## API Reference

### `resolveShift()`

Main entry point for the Time Engine.

```dart
ShiftResolution resolveShift({
  required String shiftDate,    // "2026-03-07"
  required String startTime,    // "22:00"
  required String endTime,      // "06:00+1" (+1 = next day)
  required String timezone,     // "America/New_York"
});
```

**Returns:**
- `utcStart`: UTC instant of shift start
- `utcEnd`: UTC instant of shift end
- `duration`: Elapsed duration in hours
- `startOffset`: UTC offset at start
- `endOffset`: UTC offset at end
- `error`: Error code if resolution fails
- `options`: Multiple UTC options if time is ambiguous

### `calculateDuration()`

Calculate duration from two UTC instants.

```dart
ElapsedDuration calculateDuration({
  required UtcInstant utcStart,
  required UtcInstant utcEnd,
});
```

### `checkTimezoneRetention()`

Verify INVARIANT-007 compliance.

```dart
bool checkTimezoneRetention({
  required String originalTimezone,
  required String currentTimezone,
  required String occurrenceTimezone,
});
```

## Testing

The Time Engine is tested against 28 golden cases in
`test/golden/time_engine_cases.json` (driven by the JSON — no hard-coded
values) plus explicit unit/invariant tests, including:

1. **DST Transitions:** US Eastern, UK, Germany, Australia spring-forward and fall-back
2. **DST Ambiguity:** DST-003/004/008 (NY), DST-009/010 (Lord Howe 30-min zone)
3. **Validation (VALID-001..004):** INVALID_DATE / INVALID_TIME /
   END_BEFORE_START / INVALID_TIMEZONE — each distinct from DST outcomes
4. **Lord Howe:** DST-009 (ambiguous 30' apart), DST-010 (gap), LH-001
   (+10:30 half-hour offset resolution)
5. **Invariant tests:** INVARIANT-002/003/007 (explicit Dart tests)
6. **Round-trip property (H-4):** every hour of 2026 x NY/Berlin/Lord Howe —
   any RESOLVED candidate must render back to the exact wall-clock input

`scripts/verify_all_cases.mjs` verifies the JSON's UTC/duration consistency
independently (`Errors: 0`).

## Dependencies

- **timezone package:** Provides IANA timezone database access
- **Intl API:** Used for verification of UTC values

## Future Considerations

1. **Caching:** UTC resolutions can be cached for performance
2. **Precomputation:** For recurring shifts, precompute UTC for the next N occurrences
3. **Offline support:** Timezone database is bundled with the app (INVARIANT-008)
