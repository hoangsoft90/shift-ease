// =============================================================================
// RC plan §C1/C2 — pure-module tests: CSV mapping validation (import_validation)
// and re-import diff (import_diff). Engine-free, in-memory.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftease/core/import/import_diff.dart';
import 'package:shiftease/core/import/import_parser.dart' show parseCsvRoster;
import 'package:shiftease/core/import/import_validation.dart';
import 'package:shiftease/core/time/time_engine.dart' show initializeTimezoneDatabase;

void main() {
  setUpAll(initializeTimezoneDatabase);

  group('RC C1 — validateCsvMapping', () {
    test('unmapped required columns are reported before review', () {
      // Header 'when'/'who' matches no known synonym → engine-level failure
      // handled elsewhere; here simulate an explicit mapping missing 'date'.
      final parsed = parseCsvRoster(
        'date,start,end,type\n2026-09-03,07:00,19:00,Day\n',
        columnMapping: {'shiftType': 'type', 'startTime': 'start', 'endTime': 'end'},
      );
      expect(parsed.isSuccess, isTrue);
      final issues = validateCsvMapping(parsed.extraction!,
          mapping: {'shiftType': 'type', 'startTime': 'start', 'endTime': 'end'},
          timezone: 'UTC');
      expect(
          issues.any((i) =>
              i.severity == ValidationSeverity.error &&
              i.message.contains('Date column is not mapped')),
          isTrue);
    });

    test('duplicate rows and missing shift times are flagged', () {
      final parsed = parseCsvRoster(
        'date,start,end\n'
        '2026-09-03,07:00,19:00\n'
        '2026-09-03,07:00,19:00\n'
        '2026-09-04,,\n',
        columnMapping: const {'date': 'date', 'startTime': 'start', 'endTime': 'end'},
      );
      expect(parsed.isSuccess, isTrue);
      final issues = validateCsvMapping(parsed.extraction!,
          mapping: const {'date': 'date', 'startTime': 'start', 'endTime': 'end'},
          timezone: 'UTC');
      expect(issues.any((i) => i.message.contains('duplicate')), isTrue,
          reason: 'identical date+times twice must be reported');
      expect(issues.any((i) => i.message.contains('cannot resolve')), isTrue,
          reason: 'row with no times stays unresolvable');
    });

    test('DST gap rows are surfaced with the job timezone', () {
      final parsed = parseCsvRoster(
        'date,start,end,type\n'
        '2026-03-08,02:30,10:30,Day\n', // spring-forward gap America/New_York
        columnMapping: const {'date': 'date', 'startTime': 'start', 'endTime': 'end', 'shiftType': 'type'},
      );
      expect(parsed.isSuccess, isTrue);
      final issues = validateCsvMapping(parsed.extraction!,
          mapping: const {'date': 'date', 'startTime': 'start', 'endTime': 'end', 'shiftType': 'type'},
          timezone: 'America/New_York');
      expect(issues.any((i) => i.message.contains('DST gap/overlap')), isTrue);
    });

    test('clean CSV reports ready, no issues of severity > info', () {
      final parsed = parseCsvRoster(
        'date,start,end,type\n'
        '2026-09-03,07:00,19:00,Day\n'
        '2026-09-04,,,OFF\n',
        columnMapping: const {'date': 'date', 'startTime': 'start', 'endTime': 'end', 'shiftType': 'type'},
      );
      expect(parsed.isSuccess, isTrue);
      final issues = validateCsvMapping(parsed.extraction!,
          mapping: const {'date': 'date', 'startTime': 'start', 'endTime': 'end', 'shiftType': 'type'},
          timezone: 'UTC');
      expect(issues.where((i) => i.severity != ValidationSeverity.info), isEmpty);
      expect(issues.any((i) => i.message.contains('ready to review')), isTrue);
    });
  });

  group('RC C2 — computeRosterDiff', () {
    test('added / removed / modified / unchanged buckets with old→new', () {
      final diff = computeRosterDiff(
        committed: const [
          (date: '2026-09-01', start: '07:00', end: '19:00'),
          (date: '2026-09-02', start: '19:00', end: '07:00'), // removed
          (date: '2026-09-03', start: '07:00', end: '19:00'), // modified → OFF
          (date: '2026-09-04', start: '07:00', end: '19:00'), // unchanged
        ],
        incoming: const [
          (date: '2026-09-01', start: '07:00', end: '19:00'), // unchanged
          (date: '2026-09-03', start: null, end: null), // shift → OFF (modified)
          (date: '2026-09-04', start: '07:00', end: '19:00'), // unchanged
          (date: '2026-09-05', start: '07:00', end: '15:00'), // added
        ],
      );
      expect(diff.added, 1);
      expect(diff.removed, 1);
      expect(diff.modified, 1);
      expect(diff.unchanged, 2);

      final modified = diff.items.firstWhere((i) => i.kind == 'modified');
      expect(modified.oldLabel, '07:00–19:00');
      expect(modified.newLabel, 'OFF');
      final added = diff.items.firstWhere((i) => i.kind == 'added');
      expect(added.date, '2026-09-05');
    });

    test('hours delta is signed: longer added shift minus removed shift', () {
      final diff = computeRosterDiff(
        committed: const [
          (date: '2026-09-01', start: '19:00', end: '07:00'), // 12h removed
          (date: '2026-09-02', start: '07:00', end: '19:00'), // 12h → 8h: −4
        ],
        incoming: const [
          (date: '2026-09-02', start: '07:00', end: '15:00'), // modified
          (date: '2026-09-03', start: '07:00', end: '23:00'), // 16h added
        ],
      );
      // −12 (removed) − 4 (modified) + 16 (added) = 0h net
      expect(diff.hoursDelta, closeTo(0, 0.001));
    });

    test('empty committed roster = every incoming row added', () {
      final diff = computeRosterDiff(
        committed: const [],
        incoming: const [(date: '2026-09-01', start: '07:00', end: '19:00')],
      );
      expect(diff.added, 1);
      expect(diff.hoursDelta, closeTo(12, 0.001));
    });

    test('L2: equal start/end is a zero-length row (0h), never 24h', () {
      final diff = computeRosterDiff(
        committed: const [],
        incoming: const [(date: '2026-09-01', start: '07:00', end: '07:00')],
      );
      expect(diff.added, 1);
      expect(diff.hoursDelta, closeTo(0, 0.001),
          reason: '07:00–07:00 is 0h — only end < start wraps to +24h');
    });

    test('L2: overnight wrap still counts from the NEXT day (end < start)', () {
      final diff = computeRosterDiff(
        committed: const [],
        incoming: const [(date: '2026-09-01', start: '19:00', end: '07:00')],
      );
      expect(diff.hoursDelta, closeTo(12, 0.001),
          reason: '19:00→07:00+1 stays a 12h overnight shift');
    });
  });
}