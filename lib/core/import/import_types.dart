// =============================================================================
// ShiftEase Import Pipeline — Core Types (plan2 §2.3 + §3)
// =============================================================================
//
// INVARIANT-004 (locked): imported data is NEVER committed without explicit
// user confirmation. Every candidate starts PENDING and stays that way until
// the user approves/modifies it; commit is a separate, explicit action.
//
// INVARIANT-002: a committed shift's UTC instants are resolved by core/time's
// resolveShift() from the local civil time + timezone — never computed here.
//
// Scope note (M4.5 gate): IMAGE/PDF sources need OCR, which is gated behind
// the OCR spike test on 20-30 real rosters (features.md M4.5: >=70% dates,
// >=60% shift types). Until that spike passes, parsing IMAGE/PDF returns a
// recoverable OCR_PENDING_SPIKE error — no speculative OCR architecture.
//
// =============================================================================

/// Where the roster data comes from.
enum ImportSourceType {
  pasteText,
  csv,
  image,
  pdf;

  static ImportSourceType fromName(String name) => ImportSourceType.values
      .firstWhere((s) => s.name.toUpperCase() == name.replaceAll('_', '').toUpperCase(),
          orElse: () => ImportSourceType.pasteText);
}

/// ImportSession lifecycle (plan2 §3.1).
enum ImportState {
  idle,
  parsing,
  extracted, // candidates generated, awaiting review
  reviewing, // user is approving/rejecting/modifying
  committed, // explicit commit happened (INVARIANT-004)
  error; // parse failed — recoverable, user may retry
}

/// Per-candidate confidence (plan2 §3.2 confidence scoring matrix).
enum Confidence {
  high,
  medium,
  low;

  static Confidence fromName(String name) => Confidence.values.firstWhere(
      (c) => c.name.toUpperCase() == name.toUpperCase(),
      orElse: () => Confidence.low);
}

/// Review state of one candidate. Nothing is ever auto-approved.
enum ReviewStatus {
  pending,
  approved,
  rejected,
  modified;

  static ReviewStatus fromName(String name) => ReviewStatus.values.firstWhere(
      (s) => s.name.toUpperCase() == name.toUpperCase(),
      orElse: () => ReviewStatus.pending);
}

/// User actions available during review.
enum ReviewAction {
  approve,
  reject,
  modify,
  bulkAcceptAllHigh;

  static ReviewAction fromName(String name) => ReviewAction.values.firstWhere(
      (a) => a.name.toUpperCase() == name.toUpperCase(),
      orElse: () => ReviewAction.approve);
}

/// What a roster line turned out to describe.
enum ShiftKind {
  shift, // a worked shift with start/end times
  off, // an explicit OFF / rest day
  unknown, // line recognized but not resolvable to a shift or off day
}

/// Normalized data of one candidate shift (plan2 §2.3 CandidateShift.data).
///
/// [shiftType] is a human label ("Day", "Night", "Off", "?") — display and
/// template-suggestion input, not a pay/template authority.
class CandidateData {
  final String? date; // ISO date once resolved, else null (commit-impossible)
  final String? templateId; // suggested template, never forced
  final String? startTime; // "HH:mm" (end carries "+1" when overnight)
  final String? endTime;
  final String? shiftType; // "Day" | "Night" | "Off" | "?" ...
  final ShiftKind kind;

  const CandidateData({
    this.date,
    this.templateId,
    this.startTime,
    this.endTime,
    this.shiftType,
    this.kind = ShiftKind.unknown,
  });

  bool get resolvable =>
      date != null &&
      (kind == ShiftKind.off ||
          (kind == ShiftKind.shift && startTime != null && endTime != null));

  CandidateData copyWith({
    String? date,
    String? templateId,
    String? startTime,
    String? endTime,
    String? shiftType,
    ShiftKind? kind,
  }) =>
      CandidateData(
        date: date ?? this.date,
        templateId: templateId ?? this.templateId,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        shiftType: shiftType ?? this.shiftType,
        kind: kind ?? this.kind,
      );
}

/// One import candidate awaiting (or having received) user review.
class CandidateShift {
  final String id;
  final CandidateData data;
  final Confidence confidence;

  /// Why this confidence — surfaced to the user in the review UI.
  final String? note;
  final ReviewStatus reviewStatus;

  const CandidateShift({
    required this.id,
    required this.data,
    required this.confidence,
    this.note,
    this.reviewStatus = ReviewStatus.pending,
  });

  CandidateShift copyWith({
    CandidateData? data,
    Confidence? confidence,
    String? note,
    ReviewStatus? reviewStatus,
  }) =>
      CandidateShift(
        id: id,
        data: data ?? this.data,
        confidence: confidence ?? this.confidence,
        note: note ?? this.note,
        reviewStatus: reviewStatus ?? this.reviewStatus,
      );
}

/// One raw line parsed out of the source document (audit-grade: the parser
/// output is stored verbatim on the session so "why is Sep 03 a Night shift?"
/// is answerable later — plan2 §3.3).
class RawEntry {
  final int lineNumber;
  final String original;

  /// Date token exactly as written ("Sep 03", "Mon 3rd", "2026-09-03") or
  /// null when the line carries no date-like token.
  final String? dateToken;
  final String? startTime; // normalized "HH:mm" or null
  final String? endTime; // normalized, "+1" when overnight, or null
  final String? shiftTypeLabel; // explicit label ("Day"/"Night"/"Off") or null
  final bool hasGarbage; // line contained uninterpretable tokens (e.g. "Wed??")

  const RawEntry({
    required this.lineNumber,
    required this.original,
    this.dateToken,
    this.startTime,
    this.endTime,
    this.shiftTypeLabel,
    this.hasGarbage = false,
  });
}

/// Raw extraction stored on the ImportSession for audit + re-import diff.
class RawExtraction {
  final ImportSourceType sourceType;
  final List<RawEntry> entries;

  const RawExtraction({required this.sourceType, required this.entries});
}

/// Import error codes — the single source of error strings for this module
/// (Gate-0 discipline: tests reference codes, never literals).
class ImportErrorCodes {
  static const String parseFailed = 'PARSE_FAILED';
  static const String ocrPendingSpike = 'OCR_PENDING_SPIKE';
  static const String illegalState = 'ILLEGAL_STATE';
  static const String commitUnresolved = 'COMMIT_UNRESOLVED';
  static const String candidateNotFound = 'CANDIDATE_NOT_FOUND';
  static const String invalidPayload = 'INVALID_PAYLOAD';

  /// Approved candidates contradict each other (OFF + SHIFT on the same
  /// date, or two identical shifts on the same date) — RC plan §A5. The
  /// engine refuses to guess which one wins; the user must resolve it.
  static const String conflict = 'CONFLICT';
}

/// An import failure that is recoverable (the user can retry with different
/// input or fix the file) — plan2 §3.1 ERROR state.
class ImportError {
  final String code;
  final String message;
  final bool recoverable;
  final List<String>? candidateIds; // e.g. which approved candidates blocked

  const ImportError({
    required this.code,
    required this.message,
    this.recoverable = true,
    this.candidateIds,
  });
}

/// One shift successfully committed (UTC resolved by core/time). This is the
/// import engine's OUTPUT boundary: materializing these into ShiftOccurrence
/// objects (which require a patternId) is the calendar layer's job.
class CommittedShift {
  final String candidateId;
  final String occurrenceId; // deterministic: 'occ-<candidateId>'
  final String shiftDate;
  final String? templateId;
  final String startDateTimeUtc; // INVARIANT-002 — resolved, never empty
  final String endDateTimeUtc;
  final String timezone;

  const CommittedShift({
    required this.candidateId,
    required this.occurrenceId,
    required this.shiftDate,
    this.templateId,
    required this.startDateTimeUtc,
    required this.endDateTimeUtc,
    required this.timezone,
  });
}

/// Result of commitImport: the new session state plus resolved shifts.
class CommitResult {
  final ImportSession session; // state == committed on success
  final List<CommittedShift> shifts; // only for approved, resolvable shift-kind
  final List<String> committedOffDates; // approved OFF days (no occurrence)
  final ImportError? error; // set => nothing committed (atomic)

  const CommitResult({
    required this.session,
    this.shifts = const [],
    this.committedOffDates = const [],
    this.error,
  });
}

/// A shift's worth of data used by the re-import diff (plan2 §3.4). Entries
/// are keyed by [date] — one entry per date in a roster.
class DiffEntry {
  final String date; // ISO
  final String shiftType; // "Day" | "Night" | "Off" | "?"
  final String? start;
  final String? end;

  const DiffEntry({
    required this.date,
    required this.shiftType,
    this.start,
    this.end,
  });
}

/// Why an entry changed between the previous roster and the new one.
enum DiffChangeType {
  added,
  removed,
  changed, // same date, different content (not part of a swap pair)
  swapped, // two dates exchanged their content between old and new
  unchanged;

  static DiffChangeType fromName(String name) => DiffChangeType.values
      .firstWhere((t) => t.name.toUpperCase() == name.toUpperCase(),
          orElse: () => DiffChangeType.changed);
}

class DiffItem {
  final String date;
  final DiffChangeType changeType;
  final String? from; // previous content ("Day"/"Off"/...), for modified
  final String? to; // new content, for modified/added

  const DiffItem({
    required this.date,
    required this.changeType,
    this.from,
    this.to,
  });
}

/// Impact summary of a re-import diff (plan2 §3.4). Income impact is left
/// null — it needs PayRule + the active-rule lookup, which the calendar layer
/// performs on the real schedule, not on a raw roster diff.
class ImportImpact {
  final double totalHoursChanged; // net signed hours across modified entries
  final int daysChanged;
  final int daysAdded;
  final int daysRemoved;

  const ImportImpact({
    required this.totalHoursChanged,
    required this.daysChanged,
    required this.daysAdded,
    required this.daysRemoved,
  });
}

class ImportDiff {
  final List<DiffItem> added;
  final List<DiffItem> removed;
  final List<DiffItem> modified;
  final List<DiffItem> unchanged;
  final ImportImpact impact;

  const ImportDiff({
    required this.added,
    required this.removed,
    required this.modified,
    required this.unchanged,
    required this.impact,
  });
}

/// The import session: full history of one import (plan2 §2.3).
class ImportSession {
  final String id;
  final String createdAt; // ISO datetime
  final ImportSourceType sourceType;
  final ImportState state;

  /// Reference date the user picks for the roster period — anchors ambiguous
  /// dates ("Sep 03" -> which year; weekdays). Never auto-guessed.
  final String referenceDate;
  final String timezone; // job timezone for commit resolution
  final RawExtraction rawExtraction;
  final List<CandidateShift> candidates;
  final List<String> committedOccurrenceIds; // audit: committed ids

  /// Date window this session governs — set when the session is COMMITTED
  /// (Gate A, plan4 review1/3/4 / prompt_gate_a_b.md §A3). Any later
  /// re-import whose window overlaps this one REPLACES it for the overlap;
  /// outside the window the previous committed session keeps effect. A
  /// committed session whose window is [windowStart..windowEnd] (inclusive)
  /// is authoritative for those dates even when [committedOffDates] is [].
  /// A non-committed session has no window yet (both null). Required (not
  /// nullable) once committed — the persistence layer throws if otherwise.
  final String? windowStart;
  final String? windowEnd;

  /// Dates committed as APPROVED OFF days (no occurrence created). Stored on
  /// the session so re-import diff and the calendar layer know which days the
  /// approved roster said “no shift” (plan7 D-M2-1 suppression).
  final List<String> committedOffDates;
  final ImportError? error;

  /// State transition history (always starts [ImportState.idle]) — the audit
  /// trail behind the golden "stateTransitions" expectations, e.g.
  /// [idle, parsing, extracted, reviewing, committed].
  final List<ImportState> history;

  const ImportSession({
    required this.id,
    required this.createdAt,
    required this.sourceType,
    required this.state,
    required this.referenceDate,
    required this.timezone,
    required this.rawExtraction,
    required this.candidates,
    required this.committedOccurrenceIds,
    this.committedOffDates = const [],
    this.error,
    this.history = const [ImportState.idle],
    this.windowStart,
    this.windowEnd,
  });

  /// Copy with [state] set and the transition appended to [history].
  ImportSession transitionTo(ImportState next) =>
      copyWith(state: next, history: [...history, next]);

  /// Audit query (plan2 §3.3): find the candidate that produced a given
  /// committed occurrence, if any.
  CandidateShift? candidateForOccurrenceId(String occurrenceId) {
    final idx =
        committedOccurrenceIds.indexOf(occurrenceId);
    if (idx < 0 || idx >= candidates.length) return null;
    return candidates[idx];
  }

  /// Compute this session's window from the committed shifts + OFF dates.
  /// Callers set [windowStart]/[windowEnd] from this at commit time (Gate A
  /// §A3) — the window covers the FULL date range of the committed roster,
  /// not just approved days.
  ImportSession withWindow(List<String> allCommitDates) {
    if (allCommitDates.isEmpty) return this;
    final sorted = allCommitDates.toList()..sort();
    return copyWith(
      windowStart: sorted.first,
      windowEnd: sorted.last,
    );
  }

  ImportSession copyWith({
    ImportState? state,
    RawExtraction? rawExtraction,
    List<CandidateShift>? candidates,
    List<String>? committedOccurrenceIds,
    List<String>? committedOffDates,
    ImportError? error,
    List<ImportState>? history,
    String? windowStart,
    String? windowEnd,
  }) =>
      ImportSession(
        id: id,
        createdAt: createdAt,
        sourceType: sourceType,
        state: state ?? this.state,
        referenceDate: referenceDate,
        timezone: timezone,
        rawExtraction: rawExtraction ?? this.rawExtraction,
        candidates: candidates ?? this.candidates,
        committedOccurrenceIds:
            committedOccurrenceIds ?? this.committedOccurrenceIds,
        committedOffDates: committedOffDates ?? this.committedOffDates,
        error: error ?? this.error,
        history: history ?? this.history,
        windowStart: windowStart ?? this.windowStart,
        windowEnd: windowEnd ?? this.windowEnd,
      );
}
