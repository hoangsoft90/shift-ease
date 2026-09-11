// =============================================================================
// RC plan §C1 — CSV mapping validation (pure).
//
// Validation runs BEFORE the session enters review: unmapped required
// column, invalid/missing date/time, duplicate rows, malformed row counts
// and DST ambiguity are each reported with a severity + human message. The
// engine's confidence scoring already LOWs unresolvable rows — this module
// makes the REASONS visible up-front instead of a wall of LOW candidates.
// =============================================================================

import 'package:shiftease/core/import/import_types.dart' show RawExtraction;
import 'package:shiftease/core/time/time_engine.dart' show resolveShift;
import 'package:shiftease/core/time/time_types.dart' show ErrorCodes;

enum ValidationSeverity { error, warning, info }

class CsvIssue {
  final ValidationSeverity severity;
  final String message;
  const CsvIssue(this.severity, this.message);
}

/// [mapping] is the user's column mapping (logical field -> header name);
/// null means engine auto-detect was used. [timezone] resolves DST checks.
List<CsvIssue> validateCsvMapping(
  RawExtraction extraction, {
  Map<String, String>? mapping,
  required String timezone,
}) {
  final issues = <CsvIssue>[];
  final fields = mapping?.keys ?? const <String>[];

  // -- unmapped required columns -------------------------------------------
  if (!fields.contains('date')) {
    issues.add(const CsvIssue(ValidationSeverity.error,
        'Date column is not mapped — no row can resolve to a calendar day.'));
  }
  if (!fields.contains('startTime') || !fields.contains('endTime')) {
    issues.add(const CsvIssue(ValidationSeverity.warning,
        'Start or End column is not mapped — shift rows without times will '
        'stay unresolvable (LOW).'));
  }

  // -- row-level checks -----------------------------------------------------
  var unresolvable = 0;
  var duplicates = 0;
  var dstIssues = 0;
  final seen = <String>{};

  for (final e in extraction.entries) {
    final isOff = e.shiftTypeLabel == 'OFF';
    final hasDate = e.dateToken != null;
    final hasTimes = e.startTime != null && e.endTime != null;
    if (!hasDate || (!isOff && !hasTimes)) {
      unresolvable++;
    }
    if (hasDate) {
      final key = isOff
          ? '${e.dateToken}|OFF'
          : '${e.dateToken}|${e.startTime}|${e.endTime}';
      if (!seen.add(key)) duplicates++;
    }
    // DST: a resolvable date+times may still hit a gap/overlap in the job's
    // timezone — commit would fail loudly, so surface it during validation.
    if (hasDate && (isOff || hasTimes)) {
      final r = resolveShift(
        shiftDate: e.dateToken!,
        startTime: isOff ? '00:00' : e.startTime!,
        endTime: isOff ? '00:00' : e.endTime!,
        timezone: timezone,
      );
      if (!r.isSuccess &&
          (r.error == ErrorCodes.nonexistentLocalTime ||
              r.error == ErrorCodes.ambiguousLocalTime)) {
        dstIssues++;
      }
    }
  }

  if (unresolvable > 0) {
    issues.add(CsvIssue(ValidationSeverity.warning,
        '$unresolvable row(s) cannot resolve (missing date or shift times) — '
        'they will enter review as LOW and block commit until fixed.'));
  }
  if (duplicates > 0) {
    issues.add(CsvIssue(ValidationSeverity.error,
        '$duplicates duplicate row(s) — the same date+times appears more than '
        'once.'));
  }
  if (dstIssues > 0) {
    issues.add(CsvIssue(ValidationSeverity.error,
        '$dstIssues row(s) fall in a DST gap/overlap in $timezone — commit '
        'would fail. Fix those times first.'));
  }
  if (issues.isEmpty) {
    issues.add(const CsvIssue(ValidationSeverity.info,
        'All rows resolve cleanly — ready to review.'));
  }
  return issues;
}