// =============================================================================
// ShiftEase Time Engine — Core Time Types
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
// NEVER:
// - calculate overnight duration from local clock subtraction
// - change historical occurrence timezone
//
// =============================================================================

/// Local civil time (wall-clock) — the basis of recurrence and user intent.
/// Example: "22:00 America/New_York"
class CivilTime {
  /// ISO date string (e.g., "2026-03-07")
  final String date;

  /// Time of day in HH:mm format (e.g., "22:00")
  final String time;

  /// IANA timezone identifier (e.g., "America/New_York")
  final String timezone;

  const CivilTime({
    required this.date,
    required this.time,
    required this.timezone,
  });

  @override
  String toString() => '$date $time $timezone';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CivilTime &&
          date == other.date &&
          time == other.time &&
          timezone == other.timezone;

  @override
  int get hashCode => Object.hash(date, time, timezone);
}

/// UTC instant — used for ordering, comparisons, and duration calculation.
class UtcInstant {
  /// ISO 8601 UTC datetime string (e.g., "2026-03-08T03:00:00.000Z")
  final String isoString;

  /// Milliseconds since Unix epoch
  final int millisecondsSinceEpoch;

  const UtcInstant({
    required this.isoString,
    required this.millisecondsSinceEpoch,
  });

  /// Create from ISO string
  factory UtcInstant.parse(String isoString) {
    final date = DateTime.parse(isoString).toUtc();
    return UtcInstant(
      isoString: date.toIso8601String(),
      millisecondsSinceEpoch: date.millisecondsSinceEpoch,
    );
  }

  /// Create from milliseconds
  factory UtcInstant.fromEpoch(int millisecondsSinceEpoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpoch,
      isUtc: true,
    );
    return UtcInstant(
      isoString: date.toIso8601String(),
      millisecondsSinceEpoch: millisecondsSinceEpoch,
    );
  }

  /// Calculate duration to another UtcInstant
  Duration durationTo(UtcInstant other) {
    return Duration(
      milliseconds: other.millisecondsSinceEpoch - millisecondsSinceEpoch,
    );
  }

  @override
  String toString() => isoString;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UtcInstant &&
          millisecondsSinceEpoch == other.millisecondsSinceEpoch;

  @override
  int get hashCode => millisecondsSinceEpoch.hashCode;

  int compareTo(UtcInstant other) =>
      millisecondsSinceEpoch.compareTo(other.millisecondsSinceEpoch);
}

/// Elapsed duration — used for pay calculations and display.
class ElapsedDuration {
  /// Total hours (can be fractional, e.g., 7.0, 9.0, 0.0333)
  final double hours;

  /// Total minutes
  final double minutes;

  /// Total seconds
  final int seconds;

  const ElapsedDuration({
    required this.hours,
    required this.minutes,
    required this.seconds,
  });

  /// Create from seconds
  factory ElapsedDuration.fromSeconds(int seconds) {
    return ElapsedDuration(
      hours: seconds / 3600.0,
      minutes: seconds / 60.0,
      seconds: seconds,
    );
  }

  /// Create from Duration
  factory ElapsedDuration.fromDuration(Duration duration) {
    return ElapsedDuration(
      hours: duration.inMilliseconds / 3600000.0,
      minutes: duration.inMilliseconds / 60000.0,
      seconds: duration.inSeconds,
    );
  }

  @override
  String toString() => '${hours.toStringAsFixed(1)}h';
}

/// Centralized error codes (D7 + H-2 in plan3_final_v2.md).
///
/// Single source of truth shared by engine code (which MUST reference these
/// constants — bare string literals are forbidden) and by the golden JSON
/// files (which keep plain strings for compatibility).
///
/// D7: INVALID_* errors are input validation failures and MUST NOT be
/// classified as DST errors (never merge into NONEXISTENT_LOCAL_TIME).
abstract final class ErrorCodes {
  /// Date cannot be parsed OR silently rolled over (e.g. 2026-02-31).
  static const invalidDate = 'INVALID_DATE';

  /// Hour > 23, minute > 59, malformed, or silently rolled over ("10:90").
  static const invalidTime = 'INVALID_TIME';

  /// IANA timezone name not found in the timezone database.
  static const invalidTimezone = 'INVALID_TIMEZONE';

  /// Override payload is semantically empty / malformed (D3: >= 1 field).
  static const invalidPayload = 'INVALID_PAYLOAD';

  /// Local wall-clock time falls in a DST spring-forward gap (0 candidates).
  static const nonexistentLocalTime = 'NONEXISTENT_LOCAL_TIME';

  /// Local wall-clock time occurs twice in a DST fall-back overlap
  /// (>= 2 candidates — caller must pick, engine never auto-selects, D4).
  static const ambiguousLocalTime = 'AMBIGUOUS_LOCAL_TIME';

  /// Resolved utcEnd <= utcStart (INVARIANT-002: checked on UTC, never on
  /// local-time subtraction).
  static const endBeforeStart = 'END_BEFORE_START';

  /// Pattern references a template id absent from the provided templates map.
  static const missingTemplate = 'MISSING_TEMPLATE';

  /// Two occurrences in the same view share one id — override targeting is
  /// ambiguous (M3). View-level warning, not an atomic failure.
  static const duplicateOccurrenceId = 'DUPLICATE_OCCURRENCE_ID';

  /// SWAP attempted between occurrences of different jobs/timezones (D5).
  static const swapCrossJob = 'SWAP_CROSS_JOB';

  /// Override (UPDATE/DELETE/REPLACE/SPLIT/SWAP) targets an occurrenceId that
  /// does not exist in the current list (P0-4). Never a silent no-op.
  static const occurrenceNotFound = 'OCCURRENCE_NOT_FOUND';

  /// SPLIT payload violates an invariant from H-1: parts out of chronological
  /// order, overlapping each other, or outside the original occurrence's UTC
  /// envelope (except a valid midnight boundary between consecutive parts).
  static const splitInvalidParts = 'SPLIT_INVALID_PARTS';

  /// SWAP cannot proceed because the effective job id is unknown on one or
  /// both sides (Gate A §A4 — imported occurrences without jobId, or
  /// occurrences whose template is missing from the templates map and which
  /// carry no occurrence.jobId). This is a hard rejection: the system never
  /// guesses a "safe" job.
  static const incompleteSwap = 'INCOMPLETE_SWAP';
}

/// UTC offset information for a specific instant.
class UtcOffset {
  /// Offset in hours from UTC (e.g., -5 for EST, +1 for CET)
  final double hours;

  /// Offset as string (e.g., "-05:00", "+01:00")
  final String formatted;

  const UtcOffset({required this.hours, required this.formatted});

  @override
  String toString() => formatted;
}

/// DST ambiguity type.
enum DstAmbiguityType {
  /// Time does not exist (spring-forward gap)
  nonexistent,

  /// Time occurs twice (fall-back overlap)
  ambiguous,

  /// No ambiguity
  none,
}

/// Result of resolving a local time to UTC.
class ResolveResult {
  /// The resolved UTC instant (null if ambiguous/nonexistent/invalid)
  final UtcInstant? utcInstant;

  /// The UTC offset at the start
  final UtcOffset? startOffset;

  /// DST ambiguity type
  final DstAmbiguityType ambiguity;

  /// For ambiguous times: list of possible UTC instants
  final List<UtcInstant>? options;

  /// Error code from [ErrorCodes]. Set ONLY for INVALID_* input failures
  /// (D7): invalid timezone/date/time. DST outcomes (nonexistent/ambiguous)
  /// are expressed through [ambiguity], NOT through this field — this is what
  /// keeps invalid input distinct from DST gaps/overlaps (P0-8 in
  /// plan3_final.md). Null on success.
  final String? errorCode;

  const ResolveResult({
    this.utcInstant,
    this.startOffset,
    this.ambiguity = DstAmbiguityType.none,
    this.options,
    this.errorCode,
  });

  /// True when the input itself was invalid (never a DST outcome).
  bool get isInvalidInput => errorCode != null && ambiguity == DstAmbiguityType.none;
}
