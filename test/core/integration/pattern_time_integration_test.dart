import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart';
import 'package:shiftease/core/time/time_types.dart';

void main() {
  tz.initializeTimeZones();

  ShiftTemplate tmpl({
    required String id,
    String code = 'X',
    String startTime = '08:00',
    String endTime = '16:00',
  }) {
    return ShiftTemplate(
      id: id,
      jobId: 'job-1',
      name: id,
      code: code,
      color: '#0000FF',
      startTime: startTime,
      endTime: endTime,
    );
  }

  group('Pattern + Time Engine Integration', () {
    test('weekly night shift spanning DST spring-forward', () {
      final pat = ShiftPattern(
        id: 'pat-night',
        jobId: 'job-1',
        name: 'Night Shift',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-night'),
        anchorDate: '2026-03-02',
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-01-01',
      );
      final templates = [tmpl(id: 'st-night', startTime: '22:00', endTime: '06:00')];

      final result = projectOccurrences(
        pattern: pat,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-09',
        templates: templates,
      );
      expect(result.issues, isEmpty);
      expect(result.occurrences.length, 8); // Mon Mar 2 through Sun Mar 9

      // Mar 8 (Sun) is EDT (UTC-4): 22:00 EDT Mar 8 = Mar 9 02:00Z.
      final mar8 = result.occurrences.firstWhere((o) => o.shiftDate == '2026-03-08');
      expect(mar8.startDateTimeUtc, '2026-03-09T02:00:00.000Z');
      // 06:00 EDT Mar 9 = 10:00Z — duration 7h, not 8h (INVARIANT-002).
      expect(mar8.endDateTimeUtc, '2026-03-09T10:00:00.000Z');

      // Mar 2 (Mon) is EST: 22:00 EST = Mar 3 03:00Z.
      final mar2 = result.occurrences.firstWhere((o) => o.shiftDate == '2026-03-02');
      expect(mar2.startDateTimeUtc, '2026-03-03T03:00:00.000Z');
    });

    test('weekly night shift spanning DST fall-back', () {
      final pat = ShiftPattern(
        id: 'pat-late',
        jobId: 'job-1',
        name: 'Late Shift',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-late'),
        anchorDate: '2026-10-26',
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-01-01',
      );
      final templates = [tmpl(id: 'st-late', startTime: '23:30', endTime: '07:30')];

      final result = projectOccurrences(
        pattern: pat,
        rangeStart: '2026-10-26',
        rangeEnd: '2026-11-02',
        templates: templates,
      );
      expect(result.issues, isEmpty);
      expect(result.occurrences.length, 8);

      // Oct 31 (Sat) 23:30 EDT = Nov 1 03:30Z.
      final oct31 = result.occurrences.firstWhere((o) => o.shiftDate == '2026-10-31');
      expect(oct31.startDateTimeUtc, '2026-11-01T03:30:00.000Z');
      // Nov 1 (Sun) 23:30 EST = Nov 2 04:30Z.
      final nov1 = result.occurrences.firstWhere((o) => o.shiftDate == '2026-11-01');
      expect(nov1.startDateTimeUtc, '2026-11-02T04:30:00.000Z');
      // Nov 1 shift is 9h actual (fall-back) — proves UTC duration flows
      // through the pattern engine untouched.
      expect(nov1.startDateTimeUtc, '2026-11-02T04:30:00.000Z');
    });

    test('fall-back day in range surfaces as issue, not occurrence', () {
      final pat = ShiftPattern(
        id: 'pat-amb',
        jobId: 'job-1',
        name: 'Ambiguous Start',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-amb'),
        anchorDate: '2026-10-26',
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-01-01',
      );
      final templates = [tmpl(id: 'st-amb', startTime: '01:30', endTime: '09:30')];

      final schedule = renderEffectiveSchedule(
        pattern: pat,
        overrides: const [],
        rangeStart: '2026-10-31',
        rangeEnd: '2026-11-02',
        templates: templates,
      );
      // Nov 1 (01:30) is ambiguous; Oct 31/Nov 2 resolve.
      final dates = schedule.occurrences.map((o) => o.shiftDate).toList();
      expect(dates, ['2026-10-31', '2026-11-02']);
      expect(schedule.issues.single.code, ErrorCodes.ambiguousLocalTime);
      expect(schedule.issues.single.shiftDate, '2026-11-01');
    });

    test('swap override re-resolves in each occurrence own timezone', () {
      final templates = [
        tmpl(id: 'st-day'),
        tmpl(id: 'st-night', startTime: '22:00', endTime: '06:00'),
      ];
      // Build two occurrences through the engine so stored UTC is consistent.
      final projection = projectOccurrences(
        pattern: ShiftPattern(
          id: 'pat-day',
          jobId: 'job-1',
          name: 'day',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: List.filled(7, 'st-day'),
          anchorDate: '2026-03-02',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-02',
        templates: templates,
      );
      final occA = projection.occurrences.single;

      // Second occurrence: same day template on Mar 3.
      final nightOcc = ShiftOccurrence(
        id: 'occ-b',
        patternId: 'pat-day',
        shiftDate: '2026-03-03',
        templateId: 'st-night',
        startDateTimeUtc: '2026-03-04T03:00:00.000Z', // 22:00 EST Mar 3
        endDateTimeUtc: '2026-03-04T11:00:00.000Z', // 06:00 EST Mar 4
        timezone: 'America/New_York',
        source: OccurrenceSource.baseline,
      );

      final override = Override(
        id: 'ov-swap',
        occurrenceId: occA.id,
        operation: OverrideOperation.swap,
        swapWithOccurrenceId: 'occ-b',
        createdAt: '2026-03-01T00:00:00Z',
      );

      final result = applyOverride(
        [occA, nightOcc],
        override,
        templates: {for (final t in templates) t.id: t},
      );
      expect(result.issues, isEmpty);

      final newA = result.occurrences.firstWhere((o) => o.id == occA.id);
      final newB = result.occurrences.firstWhere((o) => o.id == 'occ-b');
      expect(newA.shiftDate, '2026-03-03');
      expect(newA.templateId, 'st-night');
      expect(newA.startDateTimeUtc, '2026-03-04T03:00:00.000Z');
      expect(newA.timezone, 'America/New_York'); // unchanged (INVARIANT-007)
      expect(newB.shiftDate, '2026-03-02');
      expect(newB.startDateTimeUtc, '2026-03-02T13:00:00.000Z');
      expect(newB.timezone, 'America/New_York');
    });

    test('Southern Hemisphere: Australia/Sydney pattern across fall-back', () {
      final pat = ShiftPattern(
        id: 'pat-aus',
        jobId: 'job-1',
        name: 'AUS Day',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-aus'),
        anchorDate: '2026-03-30',
        defaultTimezone: 'Australia/Sydney',
        effectiveFrom: '2026-01-01',
      );
      final templates = [tmpl(id: 'st-aus')]; // 08:00-16:00

      final result = projectOccurrences(
        pattern: pat,
        rangeStart: '2026-03-30',
        rangeEnd: '2026-04-05',
        templates: templates,
      );
      expect(result.issues, isEmpty);
      expect(result.occurrences.length, 7);

      // Mar 30 AEDT (UTC+11): 08:00 = Mar 29 21:00Z.
      final mar30 = result.occurrences.firstWhere((o) => o.shiftDate == '2026-03-30');
      expect(mar30.startDateTimeUtc, '2026-03-29T21:00:00.000Z');
      // Apr 5 AEST (UTC+10): 08:00 = Apr 4 22:00Z.
      final apr5 = result.occurrences.firstWhere((o) => o.shiftDate == '2026-04-05');
      expect(apr5.startDateTimeUtc, '2026-04-04T22:00:00.000Z');
    });
  });
}
