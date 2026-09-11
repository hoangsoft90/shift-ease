// =============================================================================
// Shared override actions — the ONLY place the M1 UI turns user intent into
// an Override written to the append-only log (through ScheduleService).
// OccurrenceSheet (full form) and QuickAddSheet (1-tap) both go through here,
// so the CREATE convention (patternId required), the id scheme and the
// createdAt handling can never drift apart between the two entry points.
//
// Each function returns null on success or a user-facing error message.
// Nothing here ever mutates a pattern (INVARIANT-001) and nothing guesses a
// value the engine should decide (no auto-DST, no silent pay).
// =============================================================================

import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/schedule_service.dart';

/// CREATE a shift on [date] (an OFF day or any empty slot) with [templateId]
/// at [start]–[end] local civil time. Attaches to the FIRST pattern active on
/// that date (official schema-v2 convention). When NO pattern version covers
/// [date] — an imported-only roster or a gap between versions — the CREATE
/// attaches to the job's effective schedule via the sentinel pattern id
/// (RC plan §A2, importedSchedulePatternId): a job-less schedule must still
/// support manual shifts, and a fake pattern is NEVER fabricated to pass
/// validation. Returns an error string only on genuinely invalid input.
String? createShiftOnDate(
  ScheduleService service, {
  required String jobId,
  required String date,
  required String templateId,
  required String start,
  required String end,
  String? timezone,

  /// RC plan §D — the DST interpretation the user EXPLICITLY picked for an
  /// ambiguous local time (UTC offset in minutes). Null = unambiguous time.
  /// Only ever alters a fall-back overlap inside the engine; never guessed.
  int? dstOffsetMinutes,
}) {
  final patterns = service.patterns(jobId);
  final pattern = patterns.where((p) => p.isActiveOn(date)).firstOrNull;
  final attachPatternId = pattern?.id ?? importedSchedulePatternId(jobId);
  final rootId = pattern == null ? '${jobId}_$date' : '${pattern.id}_$date';
  final override = Override(
    id: service.newOverrideId(rootId),
    occurrenceId: rootId, // audit trail (engine ignores for CREATE)
    operation: OverrideOperation.create,
    createPayload: CreatePayload(
      date: date,
      templateId: templateId,
      startTime: start,
      endTime: end,
      timezone: timezone ?? _jobTimezone(service, jobId),
      startOffsetMinutes: dstOffsetMinutes,
      endOffsetMinutes: dstOffsetMinutes,
    ),
    createdAt: ScheduleService.nowIso(),
  );
  service.applyOverride(override, jobId: jobId, patternId: attachPatternId);
  return null;
}

/// UPDATE an existing occurrence's times and/or template.
String? updateShift(
  ScheduleService service, {
  required String jobId,
  required ShiftOccurrence occurrence,
  required String? templateId,
  required String start,
  required String end,

  /// RC plan §D — explicit DST interpretation for an ambiguous start/end
  /// (UTC offset in minutes). Null = unambiguous time / not chosen.
  int? dstOffsetMinutes,
}) {
  final override = Override(
    id: service.newOverrideId(occurrence.id),
    occurrenceId: occurrence.id,
    operation: OverrideOperation.update,
    updatePayload: UpdatePayload(
      templateId: templateId ?? occurrence.templateId,
      startTime: start,
      endTime: end,
      startOffsetMinutes: dstOffsetMinutes,
      endOffsetMinutes: dstOffsetMinutes,
    ),
    createdAt: ScheduleService.nowIso(),
  );
  service.applyOverride(override, jobId: jobId);
  return null;
}

/// REPLACE the template of [occurrence] (engine default times of the new
/// template — an intentional "change type" action).
String? replaceShiftTemplate(
  ScheduleService service, {
  required String jobId,
  required ShiftOccurrence occurrence,
  required String newTemplateId,
}) {
  final override = Override(
    id: service.newOverrideId(occurrence.id),
    occurrenceId: occurrence.id,
    operation: OverrideOperation.replace,
    replacePayload: ReplacePayload(newTemplateId: newTemplateId),
    createdAt: ScheduleService.nowIso(),
  );
  service.applyOverride(override, jobId: jobId);
  return null;
}

/// DELETE [occurrence] (hard delete via append-only DELETE override).
String? deleteShift(
  ScheduleService service, {
  required String jobId,
  required ShiftOccurrence occurrence,
}) {
  final override = Override(
    id: service.newOverrideId(occurrence.id),
    occurrenceId: occurrence.id,
    operation: OverrideOperation.delete,
    createdAt: ScheduleService.nowIso(),
  );
  service.applyOverride(override, jobId: jobId);
  return null;
}

String _jobTimezone(ScheduleService service, String jobId) => service
    .jobs()
    .firstWhere((j) => j.id == jobId)
    .defaultTimezone;

// firstOrNull polyfill (Dart 3.0 iterable lacks it in this SDK pin).
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final e in this) {
      return e;
    }
    return null;
  }
}
