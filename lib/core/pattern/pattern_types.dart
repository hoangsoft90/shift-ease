// =============================================================================
// ShiftEase Pattern Engine — Core Types
// =============================================================================
//
// ARCHITECTURAL INVARIANTS:
//
// INVARIANT-001: Pattern never mutates because an occurrence is edited.
//   Pattern only changes via creating a new version (D1), never patch in place.
//
// INVARIANT-002: Duration is always calculated from resolved UTC instants —
//   delegated to core/time. Pattern code never does local-time subtraction.
//
// INVARIANT-003: Local civil time is the basis of recurrence.
//
// INVARIANT-007: timezone is fixed at creation time, never changes.
//
// D1: Pattern versioning — uses VersionedEntity { effectiveFrom, effectiveUntil }.
// D9: anchorDate is INVARIANT across pattern versions (phase continuity).
//
// D2: Override — every user edit to a baseline occurrence creates an Override
//   object with a clear operation (CREATE/UPDATE/DELETE/REPLACE/SPLIT/SWAP).
//
// Gate 0 (plan3_final_v2.md):
// - D1 "resolved-only domain": every ShiftOccurrence that exists in the domain
//   MUST carry valid UTC + timezone. Unresolvable days exist only as
//   RenderIssue entries inside ProjectionResult/ScheduleRenderResult — never
//   as occurrence objects with empty temporal fields.
// - P0-5: provenance is a first-class field. `source` (OccurrenceSource) is
//   assigned DIRECTLY where the operation runs; it is NEVER re-derived from
//   `sourceOverrideId` at render time. `sourceOverrideId` is audit trail only.
//
// =============================================================================

/// PatternId sentinel for a CREATE attached to a job's effective schedule
/// when NO pattern version covers the date (imported-only roster / version
/// gap — RC plan §A2). The job id is embedded so a sentinel CREATE can never
/// leak across jobs. A real pattern is NEVER fabricated just to pass the
/// CREATE validation — the sentinel is the official convention for
/// "this shift belongs to the job's effective schedule, not to any pattern".
const String importedSchedulePatternPrefix = '__imported__:';

/// The sentinel patternId a job-less CREATE carries: `__imported__:<jobId>`.
String importedSchedulePatternId(String jobId) =>
    '$importedSchedulePatternPrefix$jobId';

/// A shift template defines the time/UI semantics of a shift type.
/// INVARIANT-005: Contains time/UI only — no pay semantics.
class ShiftTemplate {
  final String id;
  final String jobId;
  final String name;
  final String code;
  final String color;
  final String startTime; // "07:00"
  final String endTime; // "19:00"
  final int breakDurationMinutes;

  const ShiftTemplate({
    required this.id,
    required this.jobId,
    required this.name,
    required this.code,
    required this.color,
    required this.startTime,
    required this.endTime,
    this.breakDurationMinutes = 0,
  });
}

/// VersionedEntity pattern — shared by ShiftPattern, PayRule.
/// Khi tạo bản mới: set effectiveUntil trên bản cũ = ngày trước effectiveFrom
/// của bản mới. Không bao giờ mutate bản cũ — luôn tạo bản mới.
/// Query version tại T: effectiveFrom <= T && (effectiveUntil == null || effectiveUntil >= T).
class VersionedEntity {
  final String effectiveFrom; // ISO date, inclusive
  final String? effectiveUntil; // null = đang active

  const VersionedEntity({
    required this.effectiveFrom,
    this.effectiveUntil,
  });

  /// Check if this version is active on a given date.
  bool isActiveOn(String date) {
    if (date.compareTo(effectiveFrom) < 0) return false;
    if (effectiveUntil != null && date.compareTo(effectiveUntil!) > 0) {
      return false;
    }
    return true;
  }
}

/// ShiftPattern defines a repeating cycle of shift templates.
/// Uses VersionedEntity for pattern versioning.
///
/// INVARIANT-001: Editing an occurrence (override) never mutates the pattern.
/// Pattern changes only via creating a new version (D1).
class ShiftPattern extends VersionedEntity {
  final String id;
  final String jobId;
  final String name;
  final String type; // 'FIXED_CYCLE' | 'ALTERNATING_WEEKS' | 'CUSTOM'
  final int cycleLengthDays;
  final List<String?> sequence; // templateId or null for OFF days
  final String anchorDate; // ISO date — determines which day in cycle is index 0.
  // BẤT BIẾN qua các version (D9): createNewVersion giữ nguyên anchorDate của
  // version gốc để cycle phase không bị reset. Đổi phase = tạo pattern mới.
  final String defaultTimezone; // IANA timezone for this pattern

  const ShiftPattern({
    required this.id,
    required this.jobId,
    required this.name,
    required this.type,
    required this.cycleLengthDays,
    required this.sequence,
    required this.anchorDate,
    required this.defaultTimezone,
    required super.effectiveFrom,
    super.effectiveUntil,
  }) : assert(sequence.length == cycleLengthDays);
}

/// Business classification of how an occurrence came to exist (P0-5).
///
/// Assigned DIRECTLY where the operation runs — never guessed at render time
/// and never derived from [ShiftOccurrence.sourceOverrideId].
enum OccurrenceSource {
  /// Projected straight from a pattern (projectOccurrences).
  baseline,

  /// Created manually through a CREATE override.
  created,

  /// Produced/modified by UPDATE/REPLACE/SPLIT/SWAP (or a created occurrence
  /// that a later override touched — the latest operation wins).
  modified,
}

/// A single occurrence projected from a pattern (or created via override).
///
/// D1 (resolved-only): startDateTimeUtc / endDateTimeUtc / timezone are
/// ALWAYS valid. An occurrence whose local time cannot be resolved exists
/// only as a [RenderIssue] — NEVER as an object with empty temporal fields.
///
/// INVARIANT-007: timezone is fixed at creation time, never changes.
class ShiftOccurrence {
  final String id;
  final String patternId;

  /// ISO date — the day the shift starts (local civil date).
  final String shiftDate;
  final String templateId;
  final String startDateTimeUtc; // ISO 8601 UTC — resolved, never empty
  final String endDateTimeUtc; // ISO 8601 UTC — resolved, never empty
  final String timezone; // fixed at creation time

  /// How this occurrence entered the domain (P0-5). Set at operation time.
  final OccurrenceSource source;

  /// Audit trail: id of the LAST override that created/modified this
  /// occurrence, or null for untouched baseline. NEVER used to derive
  /// [source].
  final String? sourceOverrideId;

  final double? actualPayEstimate; // snapshot, immutable (INVARIANT-006)

  /// Pay-rule version whose [actualPayEstimate] was computed (snapshot
  /// provenance). Persisted alongside the amount; never derived (INVARIANT-006).
  final String? payEstimateFrom;

  /// Owning job for schedule rows that carry NO pattern — COMMITTED-IMPORT
  /// rows (M2, plan7 D-M2-1). Null for pattern-derived and override-derived
  /// rows (their job is reachable through [patternId]). Persistence-only.
  final String? jobId;

  /// True when this row is an APPROVED IMPORT COMMIT (plan7 D-M2-1), not a
  /// pattern projection. Imported rows are the authoritative roster for
  /// their date; rendering suppresses pattern days they cover.
  /// Persistence-only.
  final bool isImported;

  const ShiftOccurrence({
    required this.id,
    required this.patternId,
    required this.shiftDate,
    required this.templateId,
    required this.startDateTimeUtc,
    required this.endDateTimeUtc,
    required this.timezone,
    required this.source,
    this.sourceOverrideId,
    this.actualPayEstimate,
    this.payEstimateFrom,
    this.jobId,
    this.isImported = false,
  });

  ShiftOccurrence copyWith({
    String? id,
    String? patternId,
    String? shiftDate,
    String? templateId,
    String? startDateTimeUtc,
    String? endDateTimeUtc,
    String? timezone,
    OccurrenceSource? source,
    String? sourceOverrideId,
    double? actualPayEstimate,
    String? payEstimateFrom,
    String? jobId,
    bool? isImported,
  }) {
    return ShiftOccurrence(
      id: id ?? this.id,
      patternId: patternId ?? this.patternId,
      shiftDate: shiftDate ?? this.shiftDate,
      templateId: templateId ?? this.templateId,
      startDateTimeUtc: startDateTimeUtc ?? this.startDateTimeUtc,
      endDateTimeUtc: endDateTimeUtc ?? this.endDateTimeUtc,
      timezone: timezone ?? this.timezone,
      source: source ?? this.source,
      sourceOverrideId: sourceOverrideId ?? this.sourceOverrideId,
      actualPayEstimate: actualPayEstimate ?? this.actualPayEstimate,
      payEstimateFrom: payEstimateFrom ?? this.payEstimateFrom,
      jobId: jobId ?? this.jobId,
      isImported: isImported ?? this.isImported,
    );
  }
}

// =============================================================================
// Override types (D2)
// =============================================================================

/// Override operation type.
enum OverrideOperation {
  create,
  update,
  delete,
  replace,
  split,
  swap,
}

/// Override reason.
enum OverrideReason {
  swap,
  overtime,
  leave,
  custom,
}

/// Payload for CREATE operation.
/// D3: timezone is REQUIRED — CREATE has no source occurrence to inherit one.
///
/// RC plan §D — DST interpretation: when the local start/end falls inside a
/// fall-back overlap and the user EXPLICITLY picked one of the two instants
/// (e.g. 01:30 EDT vs 01:30 EST), the chosen UTC offset in MINUTES is stored
/// here so the write carries the user's interpretation. Null = the time was
/// not ambiguous (or the user has not chosen — the UI refuses to persist an
/// unresolved ambiguous time, D-C5).
class CreatePayload {
  final String date;
  final String templateId;
  final String startTime;
  final String endTime;
  final String timezone; // IANA timezone — required (D3)
  final int? startOffsetMinutes; // explicit DST interpretation (RC §D)
  final int? endOffsetMinutes;

  const CreatePayload({
    required this.date,
    required this.templateId,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    this.startOffsetMinutes,
    this.endOffsetMinutes,
  });
}

/// Payload for UPDATE operation.
/// D3: startTime/endTime/templateId optional BUT >= 1 field must be present
/// (validated by the engine — an empty payload is INVALID_PAYLOAD). An absent
/// field keeps the current value: current local civil time is derived from
/// the occurrence's stored UTC via its own timezone.
class UpdatePayload {
  final String? startTime;
  final String? endTime;
  final String? templateId;

  /// RC plan §D — explicit DST interpretation for an ambiguous start/end
  /// (UTC offset in minutes). Null = unambiguous time / not chosen.
  final int? startOffsetMinutes;
  final int? endOffsetMinutes;

  const UpdatePayload({
    this.startTime,
    this.endTime,
    this.templateId,
    this.startOffsetMinutes,
    this.endOffsetMinutes,
  });
}

/// Payload for REPLACE operation.
class ReplacePayload {
  final String newTemplateId;

  /// When present, replaces the occurrence's times. When absent, the new
  /// template's default start/end times (from the templates map) are used.
  final ReplaceTime? overrideTime;

  const ReplacePayload({required this.newTemplateId, this.overrideTime});
}

class ReplaceTime {
  final String startTime;
  final String endTime;

  const ReplaceTime({required this.startTime, required this.endTime});
}

/// One part of a SPLIT operation.
class SplitPart {
  final String startTime;
  final String endTime;
  final String templateId;

  /// Calendar-day offset of this part's START date relative to the original
  /// occurrence's shiftDate. 0 = same day, 1 = next day (overnight tail,
  /// e.g. a part starting 00:00 the morning after). Required by D3.
  final int dateOffsetDays;

  const SplitPart({
    required this.startTime,
    required this.endTime,
    required this.templateId,
    required this.dateOffsetDays,
  });
}

/// Payload for SPLIT operation.
class SplitPayload {
  final List<SplitPart> parts;

  const SplitPayload({required this.parts});
}

/// An Override represents a user edit to a baseline occurrence.
/// INVARIANT-001: Applying an override never mutates the original pattern.
class Override {
  final String id;
  final String occurrenceId; // occurrence being overridden
  final OverrideOperation operation;
  final CreatePayload? createPayload;
  final UpdatePayload? updatePayload;
  final ReplacePayload? replacePayload;
  final SplitPayload? splitPayload;
  final String? swapWithOccurrenceId; // only for SWAP
  final String createdAt;
  final OverrideReason? reason;

  const Override({
    required this.id,
    required this.occurrenceId,
    required this.operation,
    this.createPayload,
    this.updatePayload,
    this.replacePayload,
    this.splitPayload,
    this.swapWithOccurrenceId,
    required this.createdAt,
    this.reason,
  });
}

// =============================================================================
// Gate 0 result/issue types (D8, P0-1, P0-3)
// =============================================================================

/// A single issue discovered while projecting or rendering a schedule.
class RenderIssue {
  /// One of [ErrorCodes] (see D7) — machine-readable, stable contract.
  final String code;

  /// ISO date the issue relates to, when applicable.
  final String? shiftDate;

  /// Id of the occurrence the issue relates to, when applicable.
  final String? occurrenceId;

  /// Diagnostic fallback for log/debug — NOT a UI localization contract
  /// (H-3). The UI layer (Gate 4+) is free to map [code] to its own
  /// display copy per language/tone; it must not depend on this text.
  final String message;

  const RenderIssue({
    required this.code,
    this.shiftDate,
    this.occurrenceId,
    required this.message,
  });
}

/// Result of projecting baseline occurrences from a pattern (P0-3).
///
/// D1 resolved-only: [occurrences] contains 100% resolved occurrences — no
/// empty startDateTimeUtc/endDateTimeUtc/timezone anywhere. Every day that
/// failed to resolve (DST gap/overlap, MISSING_TEMPLATE, invalid input)
/// appears ONLY as a [RenderIssue]; no phantom occurrence object exists.
class ProjectionResult {
  final List<ShiftOccurrence> occurrences;
  final List<RenderIssue> issues;

  const ProjectionResult({
    required this.occurrences,
    required this.issues,
  });
}

/// Result of applying ONE override (P0-1).
///
/// Command-level atomicity (P0-6): on success, [occurrences] is the new list
/// and [issues] is empty. On failure, [occurrences] is the input list
/// UNCHANGED and [issues] carries the failure — never a silent no-op, never
/// a half-applied mutation.
class OverrideResult {
  final List<ShiftOccurrence> occurrences;
  final List<RenderIssue> issues;

  const OverrideResult({
    required this.occurrences,
    required this.issues,
  });

  bool get isSuccess => issues.isEmpty;
}

/// Result of rendering the full effective schedule (baseline + all overrides).
class ScheduleRenderResult {
  /// Occurrences that resolved validly (baseline + post-override state).
  final List<ShiftOccurrence> occurrences;

  /// Aggregated issues from projection and from every override in the chain.
  /// D8: nothing is ever silently dropped — each unresolved day/override
  /// failure is represented here.
  final List<RenderIssue> issues;

  const ScheduleRenderResult({
    required this.occurrences,
    required this.issues,
  });
}
