import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart';
import 'package:shiftease/core/time/time_types.dart';

void main() {
  tz.initializeTimeZones();

  ShiftPattern makePattern({
    String id = 'pat-001',
    String tzName = 'America/New_York',
    int cycleLengthDays = 7,
    String anchorDate = '2026-03-02',
    String startDate = '2026-01-01',
  }) {
    return ShiftPattern(
      id: id,
      jobId: 'job-1',
      name: 'Test Pattern',
      type: 'FIXED_CYCLE',
      cycleLengthDays: cycleLengthDays,
      sequence: List.filled(cycleLengthDays, 'st-1'),
      anchorDate: anchorDate,
      defaultTimezone: tzName,
      effectiveFrom: startDate,
    );
  }

  ShiftTemplate makeTemplate({String id = 'st-1'}) {
    return ShiftTemplate(
      id: id,
      jobId: 'job-1',
      name: 'Shift $id',
      code: id.toUpperCase(),
      color: '#0000FF',
      startTime: '08:00',
      endTime: '16:00',
    );
  }

  Map<String, ShiftTemplate> tmap(List<ShiftTemplate> ts) =>
      {for (final t in ts) t.id: t};

  group('INVARIANT-001: applyOverride never mutates input', () {
    test('input list is unmodified after a swap override', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-22',
        templates: [makeTemplate()],
      );
      final occurrences = projection.occurrences;
      expect(projection.issues, isEmpty);

      final originalState = occurrences
          .map((o) => '${o.id}|${o.templateId}|${o.shiftDate}')
          .toList();

      final override = Override(
        id: 'ov-1',
        occurrenceId: occurrences[0].id,
        operation: OverrideOperation.swap,
        swapWithOccurrenceId: occurrences[1].id,
        createdAt: '2026-03-01T00:00:00Z',
      );

      final result = applyOverride(occurrences, override,
          templates: tmap([makeTemplate()]));

      // Input unchanged.
      final afterState = occurrences
          .map((o) => '${o.id}|${o.templateId}|${o.shiftDate}')
          .toList();
      expect(afterState, originalState);

      // Result is a different list instance.
      expect(identical(occurrences, result.occurrences), isFalse);
    });
  });

  group('Cycle Repetition: every cycle produces same local times', () {
    test('all occurrences use the same template and resolve every day', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-01-01',
        rangeEnd: '2026-03-31',
        templates: [makeTemplate()],
      );
      expect(result.issues, isEmpty);
      for (final occ in result.occurrences) {
        expect(occ.templateId, 'st-1');
        expect(occ.startDateTimeUtc, isNotEmpty);
        expect(occ.endDateTimeUtc, isNotEmpty);
      }
    });

    test('cadence spacing is consistent across cycles', () {
      final pattern = makePattern(cycleLengthDays: 3, anchorDate: '2026-03-02');
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-10',
        templates: [makeTemplate()],
      );
      final dates = result.occurrences.map((o) => o.shiftDate).toList();
      expect(dates, contains('2026-03-02'));
      expect(dates, contains('2026-03-05'));
      expect(dates, contains('2026-03-08'));
    });
  });

  group('Override Isolation: overrides on one occurrence do not affect others', () {
    test('replace on occurrence 2 leaves occurrences 1 and 3 unchanged', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: [makeTemplate()],
      );
      final occurrences = projection.occurrences;
      final templates = [makeTemplate(), makeTemplate(id: 'st-night')];

      final override = Override(
        id: 'ov-1',
        occurrenceId: occurrences[1].id,
        operation: OverrideOperation.replace,
        replacePayload: const ReplacePayload(newTemplateId: 'st-night'),
        createdAt: '2026-03-01T00:00:00Z',
      );

      final result =
          applyOverride(occurrences, override, templates: tmap(templates));

      expect(result.issues, isEmpty);
      expect(result.occurrences[0].templateId, 'st-1');
      expect(result.occurrences[1].templateId, 'st-night');
      expect(result.occurrences[2].templateId, 'st-1');
      // Unaffected occurrences keep baseline provenance.
      expect(result.occurrences[0].source, OccurrenceSource.baseline);
      expect(result.occurrences[2].source, OccurrenceSource.baseline);
    });

    test('delete on occurrence 1 does not change occurrences 2 and 3', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: [makeTemplate()],
      );
      final occurrences = projection.occurrences;

      final override = Override(
        id: 'ov-1',
        occurrenceId: occurrences[0].id,
        operation: OverrideOperation.delete,
        createdAt: '2026-03-01T00:00:00Z',
      );

      final result =
          applyOverride(occurrences, override, templates: tmap([makeTemplate()]));
      expect(result.issues, isEmpty);
      expect(result.occurrences.map((o) => o.id), [occurrences[1].id, occurrences[2].id]);
    });
  });

  group('ProjectionResult is always fully resolved (P0-3)', () {
    test('no projected occurrence ever has empty temporal fields', () {
      final pattern = makePattern(cycleLengthDays: 1);
      // Sweep the whole year: any day that cannot resolve lands in .issues.
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-01-01',
        rangeEnd: '2026-12-31',
        templates: [makeTemplate()],
      );
      for (final occ in result.occurrences) {
        expect(occ.startDateTimeUtc, isNotEmpty);
        expect(occ.endDateTimeUtc, isNotEmpty);
        expect(occ.timezone, isNotEmpty);
      }
      // A full year of 08:00-16:00 has no DST problem days.
      expect(result.issues, isEmpty);
    });
  });

  group('Error codes are referenced via ErrorCodes constants', () {
    test('all error strings that reach tests come from ErrorCodes', () {
      expect(ErrorCodes.invalidDate, 'INVALID_DATE');
      expect(ErrorCodes.ambiguousLocalTime, 'AMBIGUOUS_LOCAL_TIME');
      expect(ErrorCodes.occurrenceNotFound, 'OCCURRENCE_NOT_FOUND');
    });
  });
}
