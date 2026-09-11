// =============================================================================
// ShiftEase Time Engine — Core Implementation
// =============================================================================
//
// ARCHITECTURAL INVARIANTS (from plan1_final_v2.md §10):
//
// INVARIANT-002: Duration is always calculated from resolved UTC instants,
//                never from local-time subtraction (localEnd - localStart).
// INVARIANT-003: Local civil time is the basis of recurrence.
// INVARIANT-007: Existing occurrences keep their original timezone even if
//                the user's device timezone changes.
//
// Gate 0 contract (plan3_final.md + plan3_final_v2.md):
// - resolveUtcInstant enumerates candidate UTC instants from the Location's
//   own transition table (loc.zones + loc.lookupTimeZone). It NEVER uses the
//   ±1h heuristic and NEVER compares offset.inHours (wrong for 30-minute DST
//   zones such as Australia/Lord_Howe).
// - Input validation (M1) is strict: dates/times that would silently roll
//   over in DateTime.parse (2026-02-31 -> 2026-03-03) are rejected with
//   INVALID_DATE / INVALID_TIME before any timezone math runs.
// - INVALID_* is never merged into the DST classification (D7): DST gaps and
//   overlaps are reported via DstAmbiguityType, invalid input via
//   ResolveResult.errorCode.
//
// NEVER:
// - calculate overnight duration from local clock subtraction
// - change historical occurrence timezone
// - use ± Duration(hours: 1) or offset.inHours to derive DST candidates
// - classify INVALID_* input as a DST (non-)existence error
//
// =============================================================================

import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import 'time_types.dart';

/// Initialize timezone database. Must be called once at app startup.
void initializeTimezoneDatabase() {
  tz.initializeTimeZones();
}

/// Resolve a local civil time to UTC instant.
///
/// This is the core function that handles DST transitions:
/// - 1 candidate  -> RESOLVED (returns utcInstant + startOffset)
/// - 0 candidates -> NONEXISTENT_LOCAL_TIME (spring-forward gap)
/// - >=2 candidates -> AMBIGUOUS_LOCAL_TIME with all options (fall-back
///   overlap) — the engine NEVER auto-selects one (D4).
/// - Invalid input (date/time/timezone) -> errorCode INVALID_* with
///   ambiguity == none, so callers can distinguish "typed wrong" from
///   "clocks jumped" (P0-8).
///
/// RC plan §D — REAL DST resolution: when [preferOffsetMinutes] is given and
/// the local time is AMBIGUOUS, the candidate whose actual UTC offset equals
/// it is returned as RESOLVED (the user explicitly picked EDT vs EST). The
/// preference is applied ONLY to an ambiguous time — an unambiguous time is
/// never altered and a preference that matches no candidate keeps the
/// ambiguous error (no guessing).
///
/// INVARIANT-003: Uses local civil time as basis.
ResolveResult resolveUtcInstant({
  required String date,
  required String time,
  required String timezone,
  int? preferOffsetMinutes,
}) {
  // --- Step 0a: timezone — distinct failure (D7, P0-8) ---
  // Invalid timezone MUST NOT be reported as a DST non-existence error.
  final tz.Location location;
  try {
    location = tz.getLocation(timezone);
  } on tz.LocationNotFoundException {
    return const ResolveResult(errorCode: ErrorCodes.invalidTimezone);
  } catch (_) {
    // Defensive: never leak package exceptions as DST results.
    return const ResolveResult(errorCode: ErrorCodes.invalidTimezone);
  }

  // --- Step 0b: strict date parse + round-trip validation (M1) ---
  // DateTime.parse('2026-02-31') silently returns 2026-03-03 — a calendar
  // drift that must be caught BEFORE any timezone arithmetic (probe E9).
  final dateParsed = _parseStrictDate(date);
  if (dateParsed == null) {
    return const ResolveResult(errorCode: ErrorCodes.invalidDate);
  }
  final (year, month, day) = dateParsed;

  // --- Step 0c: strict time validation (M1) ---
  // '25:90' / '10:90' would roll over silently; reject with INVALID_TIME.
  final timeParsed = _parseStrictTime(time);
  if (timeParsed == null) {
    return const ResolveResult(errorCode: ErrorCodes.invalidTime);
  }
  final (hour, minute) = timeParsed;

  // --- Step 1: enumerate candidate UTC instants, DB-driven (plan3 §5.1) ---
  // naiveMs is the wall-clock carrier (as-if-UTC). For every zone in this
  // Location's transition table, candidate = naiveMs - zone.offset. The
  // candidate is real iff the zone's offset is actually in effect AT that
  // candidate instant (self-consistency check via lookupTimeZone).
  final naiveMs =
      DateTime.utc(year, month, day, hour, minute).millisecondsSinceEpoch;
  final seen = <int>{};
  final candidatesMs = <int>[];
  for (final zone in location.zones) {
    final candidate = naiveMs - zone.offset;
    if (!seen.add(candidate)) continue; // dedupe identical instants
    if (location.lookupTimeZone(candidate).timeZone.offset == zone.offset) {
      candidatesMs.add(candidate);
    }
  }
  candidatesMs.sort();

  // --- Step 2: classify ---
  if (candidatesMs.isEmpty) {
    // Spring-forward gap: the wall-clock time does not exist at all.
    return const ResolveResult(ambiguity: DstAmbiguityType.nonexistent);
  }

  if (candidatesMs.length == 1) {
    final ms = candidatesMs.first;
    final zone = location.lookupTimeZone(ms).timeZone;
    return ResolveResult(
      utcInstant: UtcInstant.fromEpoch(ms),
      startOffset: UtcOffset(
        hours: zone.offset / 3600000.0,
        formatted: _formatOffsetMs(zone.offset),
      ),
      ambiguity: DstAmbiguityType.none,
    );
  }

  // >=2 candidates: fall-back overlap. Return all of them, sorted; the
  // engine never picks one (D4). For Lord Howe this yields exactly two
  // candidates 30 minutes apart (probe E10) — impossible with the old ±1h.
  //
  // RC plan §D — an EXPLICIT user selection resolves the overlap: the
  // candidate whose real offset equals [preferOffsetMinutes] is returned as
  // the resolved instant. Anything else (no preference, no matching
  // candidate) stays ambiguous — never a guess.
  if (preferOffsetMinutes != null) {
    for (final ms in candidatesMs) {
      if (location.lookupTimeZone(ms).timeZone.offset ==
          preferOffsetMinutes * 60000) {
        final zone = location.lookupTimeZone(ms).timeZone;
        return ResolveResult(
          utcInstant: UtcInstant.fromEpoch(ms),
          startOffset: UtcOffset(
            hours: zone.offset / 3600000.0,
            formatted: _formatOffsetMs(zone.offset),
          ),
          ambiguity: DstAmbiguityType.none,
        );
      }
    }
  }
  return ResolveResult(
    ambiguity: DstAmbiguityType.ambiguous,
    options: [for (final ms in candidatesMs) UtcInstant.fromEpoch(ms)],
  );
}

/// Calculate duration from two UTC instants.
///
/// INVARIANT-002: Duration is ALWAYS calculated from UTC instants,
/// never from local-time subtraction.
///
/// This is critical for DST transitions where local subtraction
/// gives wrong results (e.g., 8h wall-clock but 7h actual during spring-forward).
ElapsedDuration calculateDuration({
  required UtcInstant utcStart,
  required UtcInstant utcEnd,
}) {
  final duration = utcStart.durationTo(utcEnd);
  return ElapsedDuration.fromDuration(duration);
}

/// Resolve a shift (local start/end times) to UTC and calculate duration.
///
/// This is the main entry point for the Time Engine.
/// Returns the resolved UTC instants, duration, and DST information.
///
/// Error precedence (D7): INVALID_* (from resolveUtcInstant) propagates
/// first, then DST non-existence/ambiguity for start, then end, and finally
/// END_BEFORE_START checked on the RESOLVED UTC instants (M2 — never on
/// local-time subtraction, INVARIANT-002).
ShiftResolution resolveShift({
  required String shiftDate,
  required String startTime,
  required String endTime,
  required String timezone,
  int? preferStartOffsetMinutes,
  int? preferEndOffsetMinutes,
}) {
  // Resolve start time. resolveUtcInstant runs strict date/time/timezone
  // validation (step 0) — an invalid shiftDate or startTime is reported as
  // INVALID_* here, never as a DST outcome (P0-8).
  final startResult = resolveUtcInstant(
    date: shiftDate,
    time: startTime,
    timezone: timezone,
    preferOffsetMinutes: preferStartOffsetMinutes,
  );

  if (startResult.isInvalidInput) {
    return ShiftResolution(
      error: startResult.errorCode,
      note: 'Invalid start input for $shiftDate $startTime in $timezone: '
          '${startResult.errorCode}',
    );
  }

  if (startResult.ambiguity == DstAmbiguityType.nonexistent) {
    return ShiftResolution(
      error: ErrorCodes.nonexistentLocalTime,
      note: '$startTime on $shiftDate does not exist in $timezone '
          '(clocks jump forward). Prompt user to choose interpretation.',
    );
  }

  if (startResult.ambiguity == DstAmbiguityType.ambiguous) {
    return ShiftResolution(
      error: ErrorCodes.ambiguousLocalTime,
      options: startResult.options,
      note: '$startTime on $shiftDate occurs twice in $timezone '
          '(clocks fall back). Prompt user to choose interpretation.',
    );
  }

  // Start is resolved. Both times are now known-valid (startTime passed
  // strict parsing inside resolveUtcInstant; a malformed startTime would
  // have returned INVALID_TIME above).
  final startParsed = _parseStrictTime(startTime)!;
  final startHour = startParsed.$1;

  // Determine end date — overnight semantics preserved unchanged:
  //   - explicit '+1' suffix  -> next calendar day
  //   - endHour < startHour   -> next calendar day
  // This logic lives ONLY here (INVARIANT-002); it is never duplicated in
  // the pattern engine.
  final cleanEndTime = endTime.replaceAll('+1', '');
  final endParsed = _parseStrictTime(cleanEndTime);

  var endDate = shiftDate;
  if (endTime.contains('+1')) {
    endDate = _nextDay(shiftDate);
  } else if (endParsed != null && endParsed.$1 < startHour) {
    endDate = _nextDay(shiftDate);
  }

  // Resolve end time. An explicit end-offset preference resolves an
  // ambiguous END the same way the start preference resolves the start
  // (RC plan §D — both boundaries must be resolvable, never guessed).
  final endResult = resolveUtcInstant(
    date: endDate,
    time: cleanEndTime,
    timezone: timezone,
    preferOffsetMinutes: preferEndOffsetMinutes,
  );

  if (endResult.isInvalidInput) {
    return ShiftResolution(
      error: endResult.errorCode,
      note: 'Invalid end input for $cleanEndTime on $endDate in $timezone: '
          '${endResult.errorCode}',
    );
  }

  if (endResult.ambiguity == DstAmbiguityType.nonexistent) {
    return ShiftResolution(
      error: ErrorCodes.nonexistentLocalTime,
      note: 'End time $cleanEndTime on $endDate does not exist in $timezone.',
    );
  }

  if (endResult.ambiguity == DstAmbiguityType.ambiguous) {
    // D4: Do NOT auto-resolve ambiguous times — return error with options
    // for both start and end time, identical behavior.
    return ShiftResolution(
      error: ErrorCodes.ambiguousLocalTime,
      options: endResult.options,
      note: 'End time $cleanEndTime on $endDate is ambiguous in $timezone '
          '(clocks fall back). Prompt user to choose interpretation.',
    );
  }

  // M2 / END_BEFORE_START: compare on RESOLVED UTC instants only.
  final utcStartMs = startResult.utcInstant!.millisecondsSinceEpoch;
  final utcEndMs = endResult.utcInstant!.millisecondsSinceEpoch;
  if (utcEndMs <= utcStartMs) {
    return ShiftResolution(
      error: ErrorCodes.endBeforeStart,
      note: 'Resolved end (${endResult.utcInstant!.isoString}) is not after '
          'resolved start (${startResult.utcInstant!.isoString}) in $timezone '
          '— shift would have zero or negative duration.',
    );
  }

  // Calculate duration
  final duration = calculateDuration(
    utcStart: startResult.utcInstant!,
    utcEnd: endResult.utcInstant!,
  );

  return ShiftResolution(
    utcStart: startResult.utcInstant!,
    utcEnd: endResult.utcInstant!,
    duration: duration,
    startOffset: startResult.startOffset!,
    endOffset: endResult.startOffset!,
  );
}

/// Check if an occurrence retains its original timezone (INVARIANT-007).
///
/// When a user changes device timezone, existing occurrences must keep
/// their original timezone. New occurrences use the new timezone.
bool checkTimezoneRetention({
  required String originalTimezone,
  required String currentTimezone,
  required String occurrenceTimezone,
}) {
  // The occurrence should keep its original timezone
  return occurrenceTimezone == originalTimezone;
}

/// Check if recurrence uses local civil time (INVARIANT-003).
///
/// Pattern anchored at a local time must always produce shifts at that
/// local time, regardless of timezone changes.
bool checkRecurrenceBasis({
  required String patternTimezone,
  required String patternLocalTime,
  required String occurrenceLocalTime,
  required String occurrenceTimezone,
}) {
  // Occurrence must be at the same local time in the pattern's timezone
  return occurrenceLocalTime == patternLocalTime &&
      occurrenceTimezone == patternTimezone;
}

// =============================================================================
// Strict-validation helpers (M1 — silent rollover guard)
// =============================================================================

/// Parse "YYYY-MM-DD" and verify it is a REAL calendar date via round-trip.
///
/// Returns (year, month, day) or null when unparseable or when constructing
/// DateTime.utc(year, month, day) rolls over (e.g. 2026-02-31 -> Mar 3).
(int, int, int)? _parseStrictDate(String date) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;

  final probe = DateTime.utc(year, month, day);
  if (probe.year != year || probe.month != month || probe.day != day) {
    return null; // rolled over — NOT a real date (M1)
  }
  return (year, month, day);
}

/// Parse "HH:mm" and range-check hour/minute (rollover guard for "10:90").
(int, int)? _parseStrictTime(String time) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return (hour, minute);
}

/// ISO date of the next calendar day after [date] (date is known-valid).
String _nextDay(String date) {
  final parsed = _parseStrictDate(date)!;
  final (year, month, day) = parsed;
  final next = DateTime.utc(year, month, day + 1);
  return '${next.year.toString().padLeft(4, '0')}-'
      '${next.month.toString().padLeft(2, '0')}-'
      '${next.day.toString().padLeft(2, '0')}';
}

/// Format a zone offset given in MILLISECONDS (e.g. -18000000 -> "-05:00",
/// 37800000 -> "+10:30"). Never derived from Duration.inHours — that would
/// drop the 30-minute precision of zones like Australia/Lord_Howe.
String _formatOffsetMs(int offsetMs) {
  final totalMinutes = offsetMs ~/ 60000;
  final sign = totalMinutes >= 0 ? '+' : '-';
  final absMinutes = totalMinutes.abs();
  final hours = absMinutes ~/ 60;
  final minutes = absMinutes % 60;
  return '$sign${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

/// Result of resolving a shift.
class ShiftResolution {
  final UtcInstant? utcStart;
  final UtcInstant? utcEnd;
  final ElapsedDuration? duration;
  final UtcOffset? startOffset;
  final UtcOffset? endOffset;

  /// Error code — one of [ErrorCodes] (INVALID_*, NONEXISTENT_LOCAL_TIME,
  /// AMBIGUOUS_LOCAL_TIME, END_BEFORE_START).
  final String? error;
  final List<UtcInstant>? options;
  final String? note;

  const ShiftResolution({
    this.utcStart,
    this.utcEnd,
    this.duration,
    this.startOffset,
    this.endOffset,
    this.error,
    this.options,
    this.note,
  });

  bool get isSuccess => error == null && utcStart != null && utcEnd != null;
}
