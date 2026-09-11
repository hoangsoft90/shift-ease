// =============================================================================
// ShiftEase Pattern Engine — Unit Tests (Gate 0 API)
// =============================================================================
//
// Covers plan3_final_v2.md §5.2 and plan3_final.md §6.2:
//   - UPDATE preserve-UTC (P0-2): template/metadata-only update must not
//     re-resolve and must not change stored UTC bit-for-bit.
//   - OCCURRENCE_NOT_FOUND (P0-4) for all 5 non-CREATE operations.
//   - Override chain atomicity + ordering (P0-6).
//   - SPLIT invariants: envelope / overlap / order (H-1), atomic failure.
//   - Provenance (P0-5): source assigned at operation time, chain rule
//     created -> modified; baseline never guessed.
//   - ProjectionResult resolved-only (P0-3): failing days live in .issues,
//     never as empty-UTC occurrences.
//   - Duplicate-id detection (M3) and D9 anchorDate phase continuity.
//
// =============================================================================

import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart';
import 'package:shiftease/core/time/time_types.dart';

void main() {
  tz.initializeTimeZones();

  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------
  ShiftTemplate makeTemplate({
    String id = 'st-1',
    String jobId = 'job-1',
    String startTime = '08:00',
    String endTime = '16:00',
  }) {
    return ShiftTemplate(
      id: id,
      jobId: jobId,
      name: 'Shift $id',
      code: id.toUpperCase(),
      color: '#0000FF',
      startTime: startTime,
      endTime: endTime,
    );
  }

  ShiftPattern makePattern({
    String id = 'pat-001',
    String tzName = 'America/New_York',
    List<String?>? sequence,
    int cycleLengthDays = 7,
    String anchorDate = '2026-03-02', // Monday
    String startDate = '2026-01-01',
    String? endDate,
  }) {
    final seq = sequence ?? List<String?>.filled(cycleLengthDays, 'st-1');
    return ShiftPattern(
      id: id,
      jobId: 'job-1',
      name: 'Test Pattern',
      type: 'FIXED_CYCLE',
      cycleLengthDays: cycleLengthDays,
      sequence: seq,
      anchorDate: anchorDate,
      defaultTimezone: tzName,
      effectiveFrom: startDate,
      effectiveUntil: endDate,
    );
  }

  ShiftOccurrence makeOccurrence({
    String id = 'occ-1',
    String templateId = 'st-1',
    String shiftDate = '2026-03-02',
    String startUtc = '2026-03-02T13:00:00.000Z',
    String endUtc = '2026-03-02T21:00:00.000Z',
    String timezone = 'America/New_York',
    OccurrenceSource source = OccurrenceSource.baseline,
    String? sourceOverrideId,
  }) {
    return ShiftOccurrence(
      id: id,
      patternId: 'pat-001',
      shiftDate: shiftDate,
      templateId: templateId,
      startDateTimeUtc: startUtc,
      endDateTimeUtc: endUtc,
      timezone: timezone,
      source: source,
      sourceOverrideId: sourceOverrideId,
    );
  }

  Map<String, ShiftTemplate> tmap(List<ShiftTemplate> ts) =>
      {for (final t in ts) t.id: t};

  final dayTemplates = [
    makeTemplate(id: 'st-1'),
    makeTemplate(id: 'st-day2'), // same time window — template rename
  ];

  Override overrideWith(
    String id,
    String occurrenceId,
    OverrideOperation op, {
    CreatePayload? createPayload,
    UpdatePayload? updatePayload,
    ReplacePayload? replacePayload,
    SplitPayload? splitPayload,
    String? swapWithOccurrenceId,
  }) {
    return Override(
      id: id,
      occurrenceId: occurrenceId,
      operation: op,
      createPayload: createPayload,
      updatePayload: updatePayload,
      replacePayload: replacePayload,
      splitPayload: splitPayload,
      swapWithOccurrenceId: swapWithOccurrenceId,
      createdAt: '2026-03-01T00:00:00Z',
    );
  }

  // ---------------------------------------------------------------------------
  // projectOccurrences — ProjectionResult (resolved-only, P0-3)
  // ---------------------------------------------------------------------------
  group('projectOccurrences', () {
    test('generates one occurrence per scheduled day in range', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-15',
        templates: dayTemplates,
      );
      expect(result.issues, isEmpty);
      // cycle length 1 -> every day is st-1: Mar 2..15 inclusive = 14 days
      expect(result.occurrences.length, 14);
    });

    test('every projected occurrence is resolved and baseline', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-05',
        templates: dayTemplates,
      );
      for (final occ in result.occurrences) {
        expect(occ.startDateTimeUtc, isNotEmpty);
        expect(occ.endDateTimeUtc, isNotEmpty);
        expect(occ.timezone, 'America/New_York');
        expect(occ.source, OccurrenceSource.baseline);
        expect(occ.sourceOverrideId, isNull);
      }
      final ids = result.occurrences.map((o) => o.id).toSet();
      expect(ids.length, result.occurrences.length); // unique ids
    });

    test('empty range returns empty projection', () {
      final pattern = makePattern();
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-10',
        rangeEnd: '2026-03-07', // end before start
        templates: dayTemplates,
      );
      expect(result.occurrences, isEmpty);
      expect(result.issues, isEmpty);
    });

    test('DST ambiguous day is an issue, NOT an occurrence (P0-3)', () {
      // Template 01:30-09:30; Nov 1 2026 01:30 is ambiguous in NY.
      final pattern = makePattern(
        cycleLengthDays: 1,
        anchorDate: '2026-10-31',
        startDate: '2026-10-01',
      );
      final templates = [makeTemplate(startTime: '01:30', endTime: '09:30')];
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-10-31',
        rangeEnd: '2026-11-02',
        templates: templates,
      );

      // Oct 31 (EDT) and Nov 2 (EST) resolve; Nov 1 is ambiguous.
      final dates = result.occurrences.map((o) => o.shiftDate).toSet();
      expect(dates, {'2026-10-31', '2026-11-02'});
      expect(dates.contains('2026-11-01'), isFalse);

      expect(result.issues.length, 1);
      expect(result.issues.single.code, ErrorCodes.ambiguousLocalTime);
      expect(result.issues.single.shiftDate, '2026-11-01');
      // No phantom occurrence for the failing day:
      expect(
        result.occurrences.any((o) => o.shiftDate == '2026-11-01'),
        isFalse,
      );
    });

    test('missing template surfaces MISSING_TEMPLATE issue, not silent skip', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-02',
        templates: const <ShiftTemplate>[], // st-1 missing
      );
      expect(result.occurrences, isEmpty);
      expect(result.issues.single.code, ErrorCodes.missingTemplate);
      expect(result.issues.single.message, contains('st-1'));
    });

    test('missing template on one day does not suppress other days', () {
      final pattern = makePattern(
        cycleLengthDays: 3,
        sequence: ['st-1', 'st-missing', 'st-1'],
        anchorDate: '2026-03-02',
      );
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates, // only st-1, st-day2
      );
      expect(result.occurrences.length, 2); // Mar 2, Mar 4
      expect(result.occurrences[0].shiftDate, '2026-03-02');
      expect(result.occurrences[1].shiftDate, '2026-03-04');
      expect(result.issues.single.code, ErrorCodes.missingTemplate);
      expect(result.issues.single.shiftDate, '2026-03-03');
    });

    test('OFF days (null in sequence) generate no occurrences', () {
      final pattern = makePattern(
        cycleLengthDays: 7,
        sequence: ['st-1', 'st-1', 'st-1', 'st-1', 'st-1', null, null],
        anchorDate: '2026-03-02',
      );
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-08',
        templates: dayTemplates,
      );
      expect(result.occurrences.length, 5); // Mon-Fri only
    });

    test('DST spring-forward week resolves fully (01:30 valid pre-gap)', () {
      final pattern = makePattern(
        cycleLengthDays: 1,
        anchorDate: '2026-03-02',
        startDate: '2026-01-01',
      );
      final templates = [makeTemplate(startTime: '01:30', endTime: '09:30')];
      final result = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-09',
        templates: templates,
      );
      // 8 days; Mar 8 01:30 is before the 02:00 gap so it still resolves.
      expect(result.occurrences.length, 8);
      expect(result.issues, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // applyOverride — CREATE
  // ---------------------------------------------------------------------------
  group('applyOverride CREATE', () {
    test('creates a fully-resolved occurrence (P0-1 fix: no empty UTC)', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-new',
        'occ-1', // reference, unused for CREATE
        OverrideOperation.create,
        createPayload: const CreatePayload(
          date: '2026-03-10', // EDT already (after Mar 8)
          templateId: 'st-1',
          startTime: '08:00',
          endTime: '16:00',
          timezone: 'America/New_York',
        ),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues, isEmpty);
      expect(result.occurrences.length, 2);

      final created = result.occurrences.last;
      expect(created.id, 'ov-new');
      expect(created.shiftDate, '2026-03-10');
      expect(created.startDateTimeUtc, '2026-03-10T12:00:00.000Z'); // 08:00 EDT
      expect(created.endDateTimeUtc, '2026-03-10T20:00:00.000Z'); // 16:00 EDT
      expect(created.timezone, 'America/New_York');
      expect(created.source, OccurrenceSource.created);
      expect(created.sourceOverrideId, 'ov-new');
    });

    test('CREATE into ambiguous time fails with issue, list unchanged', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-bad',
        'occ-1',
        OverrideOperation.create,
        createPayload: const CreatePayload(
          date: '2026-11-01',
          templateId: 'st-1',
          startTime: '01:30',
          endTime: '09:00',
          timezone: 'America/New_York',
        ),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.ambiguousLocalTime);
      expect(identical(result.occurrences, base), isTrue); // unchanged
    });
  });

  // ---------------------------------------------------------------------------
  // applyOverride — UPDATE (P0-2 preserve-UTC + D3 validation)
  // ---------------------------------------------------------------------------
  group('applyOverride UPDATE', () {
    test('time change re-resolves UTC (07:00-like shift to 09:00-17:00)', () {
      // st-1 08:00-16:00 EST Mar 2 = 13:00Z-21:00Z. Move to 09:00-17:00.
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '09:00', endTime: '17:00'),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues, isEmpty);
      final updated = result.occurrences.single;
      expect(updated.startDateTimeUtc, '2026-03-02T14:00:00.000Z'); // 09:00 EST
      expect(updated.endDateTimeUtc, '2026-03-02T22:00:00.000Z'); // 17:00 EST
      expect(updated.templateId, 'st-1'); // template untouched
      expect(updated.source, OccurrenceSource.modified);
      expect(updated.sourceOverrideId, 'ov-1');
    });

    test('P0-2: template-only update preserves UTC bit-for-bit', () {
      // Occurrence deliberately created at an AMBIGUOUS wall-clock instant
      // (01:30 Nov 1, user picked the EDT option = 05:30Z).
      final ambiguousInstant = makeOccurrence(
        id: 'occ-amb',
        shiftDate: '2026-11-01',
        startUtc: '2026-11-01T05:30:00.000Z', // 01:30 EDT
        endUtc: '2026-11-01T07:30:00.000Z', // 02:30 EST (after fall-back)
      );
      final override = overrideWith(
        'ov-rename',
        'occ-amb',
        OverrideOperation.update,
        updatePayload: const UpdatePayload(templateId: 'st-day2'),
      );
      final result = applyOverride(
        [ambiguousInstant],
        override,
        templates: tmap(dayTemplates),
      );
      expect(result.issues, isEmpty);
      final updated = result.occurrences.single;
      // Bit-for-bit UTC preservation — re-resolving 01:30 would have returned
      // AMBIGUOUS_LOCAL_TIME and broken this legitimate rename.
      expect(updated.startDateTimeUtc, '2026-11-01T05:30:00.000Z');
      expect(updated.endDateTimeUtc, '2026-11-01T07:30:00.000Z');
      expect(updated.templateId, 'st-day2');
      expect(updated.source, OccurrenceSource.modified);
    });

    test('P0-2: re-sending identical times also preserves UTC', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.update,
        updatePayload: const UpdatePayload(
          startTime: '08:00',
          endTime: '16:00',
          templateId: 'st-day2',
        ),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues, isEmpty);
      final updated = result.occurrences.single;
      expect(updated.startDateTimeUtc, '2026-03-02T13:00:00.000Z');
      expect(updated.endDateTimeUtc, '2026-03-02T21:00:00.000Z');
      expect(updated.templateId, 'st-day2');
    });

    test('empty payload is INVALID_PAYLOAD, list unchanged', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.update,
        updatePayload: const UpdatePayload(), // all three null
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.invalidPayload);
      expect(identical(result.occurrences, base), isTrue);
    });

    test('update to ambiguous time on the occurrence date fails cleanly', () {
      // Occurrence sits on Nov 1 (fall-back day). Updating start to 01:30
      // cannot resolve without user input.
      final base = [
        makeOccurrence(
          id: 'occ-nov1',
          shiftDate: '2026-11-01',
          startUtc: '2026-11-01T13:00:00.000Z', // 08:00 EST
          endUtc: '2026-11-01T21:00:00.000Z', // 16:00 EST
        ),
      ];
      final override = overrideWith(
        'ov-1',
        'occ-nov1',
        OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '01:30'),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.ambiguousLocalTime);
      expect(identical(result.occurrences, base), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // applyOverride — REPLACE
  // ---------------------------------------------------------------------------
  group('applyOverride REPLACE', () {
    test('replace with template default times re-resolves UTC', () {
      final base = [makeOccurrence()]; // st-1 08:00-16:00
      final templates = [
        ...dayTemplates,
        makeTemplate(id: 'st-night', startTime: '22:00', endTime: '06:00'),
      ];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.replace,
        replacePayload: const ReplacePayload(newTemplateId: 'st-night'),
      );
      final result = applyOverride(base, override, templates: tmap(templates));
      expect(result.issues, isEmpty);
      final updated = result.occurrences.single;
      expect(updated.templateId, 'st-night');
      // 22:00 EST Mar 2 -> Mar 3 03:00Z; 06:00 EST Mar 3 -> 11:00Z.
      expect(updated.startDateTimeUtc, '2026-03-03T03:00:00.000Z');
      expect(updated.endDateTimeUtc, '2026-03-03T11:00:00.000Z');
      expect(updated.source, OccurrenceSource.modified);
    });

    test('replace with overrideTime applies given times', () {
      final base = [makeOccurrence()];
      final templates = [makeTemplate(id: 'st-night', startTime: '22:00', endTime: '06:00')];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.replace,
        replacePayload: const ReplacePayload(
          newTemplateId: 'st-night',
          overrideTime: ReplaceTime(startTime: '07:00', endTime: '15:00'),
        ),
      );
      final result = applyOverride(base, override, templates: tmap(templates));
      expect(result.issues, isEmpty);
      final updated = result.occurrences.single;
      expect(updated.templateId, 'st-night');
      expect(updated.startDateTimeUtc, '2026-03-02T12:00:00.000Z'); // 07:00 EST
      expect(updated.endDateTimeUtc, '2026-03-02T20:00:00.000Z'); // 15:00 EST
    });

    test('replace to same-time template preserves UTC (rename)', () {
      final base = [makeOccurrence()]; // st-1 and st-day2 share 08:00-16:00
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.replace,
        replacePayload: const ReplacePayload(newTemplateId: 'st-day2'),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues, isEmpty);
      final updated = result.occurrences.single;
      expect(updated.templateId, 'st-day2');
      expect(updated.startDateTimeUtc, '2026-03-02T13:00:00.000Z');
      expect(updated.endDateTimeUtc, '2026-03-02T21:00:00.000Z');
    });

    test('replace onto missing template -> MISSING_TEMPLATE, unchanged', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.replace,
        replacePayload: const ReplacePayload(newTemplateId: 'st-ghost'),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.missingTemplate);
      expect(identical(result.occurrences, base), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // applyOverride — SPLIT (H-1 invariants)
  // ---------------------------------------------------------------------------
  group('applyOverride SPLIT', () {
    test('splits a day shift into ordered non-overlapping parts', () {
      final base = [makeOccurrence()]; // 08:00-16:00 EST = 13:00Z-21:00Z
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '08:00',
              endTime: '12:00',
              templateId: 'st-morning',
              dateOffsetDays: 0),
          SplitPart(
              startTime: '12:00',
              endTime: '16:00',
              templateId: 'st-afternoon',
              dateOffsetDays: 0),
        ]),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues, isEmpty);
      expect(result.occurrences.length, 2);
      expect(result.occurrences[0].id, 'occ-1#p0');
      expect(result.occurrences[1].id, 'occ-1#p1');
      expect(result.occurrences[0].startDateTimeUtc, '2026-03-02T13:00:00.000Z');
      expect(result.occurrences[0].endDateTimeUtc, '2026-03-02T17:00:00.000Z');
      expect(result.occurrences[1].startDateTimeUtc, '2026-03-02T17:00:00.000Z');
      expect(result.occurrences[1].endDateTimeUtc, '2026-03-02T21:00:00.000Z');
      for (final part in result.occurrences) {
        expect(part.source, OccurrenceSource.modified);
        expect(part.sourceOverrideId, 'ov-1');
        expect(part.timezone, 'America/New_York');
      }
    });

    test('splits an overnight shift across the midnight boundary', () {
      // 19:00 Jan 15 EST -> 07:00 Jan 16 = Jan 16 00:00Z - 12:00Z.
      final base = [
        makeOccurrence(
          id: 'occ-overnight',
          shiftDate: '2026-01-15',
          startUtc: '2026-01-16T00:00:00.000Z',
          endUtc: '2026-01-16T12:00:00.000Z',
          templateId: 'st-night',
        ),
      ];
      final override = overrideWith(
        'ov-1',
        'occ-overnight',
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '19:00',
              endTime: '00:00',
              templateId: 'st-evening',
              dateOffsetDays: 0),
          SplitPart(
              startTime: '00:00',
              endTime: '07:00',
              templateId: 'st-early',
              dateOffsetDays: 1),
        ]),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues, isEmpty,
          reason: result.issues.map((i) => i.message).join('; '));
      expect(result.occurrences.length, 2);
      expect(result.occurrences[0].shiftDate, '2026-01-15');
      expect(result.occurrences[1].shiftDate, '2026-01-16');
      // Boundary at 00:00 Jan 16 EST = 05:00Z, shared between both parts.
      expect(result.occurrences[0].endDateTimeUtc, '2026-01-16T05:00:00.000Z');
      expect(result.occurrences[1].startDateTimeUtc, '2026-01-16T05:00:00.000Z');
      expect(result.occurrences[1].endDateTimeUtc, '2026-01-16T12:00:00.000Z');
    });

    test('overlapping parts fail atomically (H-1)', () {
      final base = [makeOccurrence()]; // 08:00-16:00
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '08:00',
              endTime: '12:00',
              templateId: 'st-1',
              dateOffsetDays: 0),
          SplitPart(
              startTime: '11:00', // overlaps 11:00-12:00 with part 0
              endTime: '16:00',
              templateId: 'st-1',
              dateOffsetDays: 0),
        ]),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.splitInvalidParts);
      expect(identical(result.occurrences, base), isTrue); // nothing created
    });

    test('part outside original envelope fails atomically (H-1)', () {
      final base = [makeOccurrence()]; // envelope ends 16:00
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '13:00',
              endTime: '17:00', // extends past 16:00 envelope
              templateId: 'st-1',
              dateOffsetDays: 0),
        ]),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.splitInvalidParts);
      expect(identical(result.occurrences, base), isTrue);
    });

    test('out-of-order parts fail atomically (H-1)', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '12:00',
              endTime: '16:00',
              templateId: 'st-1',
              dateOffsetDays: 0),
          SplitPart(
              startTime: '08:00', // earlier than previous part end
              endTime: '12:00',
              templateId: 'st-1',
              dateOffsetDays: 0),
        ]),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.splitInvalidParts);
      expect(identical(result.occurrences, base), isTrue);
    });

    test('part with invalid dateOffsetDays fails atomically', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-1',
        'occ-1',
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '08:00',
              endTime: '12:00',
              templateId: 'st-1',
              dateOffsetDays: 2), // only 0 or 1 allowed
        ]),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.splitInvalidParts);
      expect(identical(result.occurrences, base), isTrue);
    });

    test('part landing in ambiguous local time fails whole split atomically', () {
      final base = [
        makeOccurrence(
          id: 'occ-nov1',
          shiftDate: '2026-11-01',
          startUtc: '2026-11-01T13:00:00.000Z',
          endUtc: '2026-11-01T21:00:00.000Z',
        ),
      ];
      final override = overrideWith(
        'ov-1',
        'occ-nov1',
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '01:30', // ambiguous on Nov 1
              endTime: '02:30',
              templateId: 'st-1',
              dateOffsetDays: 0),
          SplitPart(
              startTime: '02:30',
              endTime: '16:00',
              templateId: 'st-1',
              dateOffsetDays: 0),
        ]),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.ambiguousLocalTime);
      expect(identical(result.occurrences, base), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // applyOverride — SWAP (D5)
  // ---------------------------------------------------------------------------
  group('applyOverride SWAP', () {
    final templates = [
      makeTemplate(id: 'st-1'), // 08:00-16:00
      makeTemplate(id: 'st-night', startTime: '22:00', endTime: '06:00'),
    ];

    test('swaps civil intent between two same-job occurrences', () {
      final occA = makeOccurrence(id: 'occ-a'); // st-1, Mar 2, 13:00Z-21:00Z
      final occB = makeOccurrence(
        id: 'occ-b',
        templateId: 'st-night',
        shiftDate: '2026-03-03',
        startUtc: '2026-03-04T03:00:00.000Z', // 22:00 EST Mar 3
        endUtc: '2026-03-04T11:00:00.000Z', // 06:00 EST Mar 4
      );
      final override = overrideWith(
        'ov-1',
        'occ-a',
        OverrideOperation.swap,
        swapWithOccurrenceId: 'occ-b',
      );
      final result = applyOverride([occA, occB], override, templates: tmap(templates));
      expect(result.issues, isEmpty);

      final newA = result.occurrences.firstWhere((o) => o.id == 'occ-a');
      final newB = result.occurrences.firstWhere((o) => o.id == 'occ-b');

      // A now carries B's template on B's day, re-resolved in A's timezone.
      expect(newA.shiftDate, '2026-03-03');
      expect(newA.templateId, 'st-night');
      expect(newA.startDateTimeUtc, '2026-03-04T03:00:00.000Z');
      expect(newA.endDateTimeUtc, '2026-03-04T11:00:00.000Z');
      // ids and timezones are preserved (D5 / INVARIANT-007).
      expect(newA.id, 'occ-a');
      expect(newA.timezone, 'America/New_York');

      // B now carries A's template on A's day.
      expect(newB.shiftDate, '2026-03-02');
      expect(newB.templateId, 'st-1');
      expect(newB.startDateTimeUtc, '2026-03-02T13:00:00.000Z');
      expect(newB.endDateTimeUtc, '2026-03-02T21:00:00.000Z');
      expect(newB.id, 'occ-b');
      expect(newB.timezone, 'America/New_York');

      for (final o in [newA, newB]) {
        expect(o.source, OccurrenceSource.modified);
        expect(o.sourceOverrideId, 'ov-1');
      }
    });

    test('cross-job swap -> SWAP_CROSS_JOB, unchanged', () {
      final otherJobTemplate = makeTemplate(id: 'st-other', jobId: 'job-2');
      final occA = makeOccurrence(id: 'occ-a');
      final occB = makeOccurrence(
        id: 'occ-b',
        templateId: 'st-other',
        shiftDate: '2026-03-03',
        startUtc: '2026-03-03T13:00:00.000Z',
        endUtc: '2026-03-03T21:00:00.000Z',
      );
      final override = overrideWith(
        'ov-1',
        'occ-a',
        OverrideOperation.swap,
        swapWithOccurrenceId: 'occ-b',
      );
      final result = applyOverride(
        [occA, occB],
        override,
        templates: tmap([...templates, otherJobTemplate]),
      );
      expect(result.issues.single.code, ErrorCodes.swapCrossJob);
      expect(identical(result.occurrences, [occA, occB]), isFalse);
      expect(result.occurrences, [occA, occB]); // deep-equal, unchanged
    });

    test('missing swap partner -> OCCURRENCE_NOT_FOUND', () {
      final base = [makeOccurrence(id: 'occ-a')];
      final override = overrideWith(
        'ov-1',
        'occ-a',
        OverrideOperation.swap,
        swapWithOccurrenceId: 'occ-ghost',
      );
      final result = applyOverride(base, override, templates: tmap(templates));
      expect(result.issues.single.code, ErrorCodes.occurrenceNotFound);
      expect(identical(result.occurrences, base), isTrue);
    });

    test('imported occurrences swap using their OWN jobId even with no '
        'template to fall back on (Gate A §A4)', () {
      // Committed-import rows carry patternId '' + templateId '' (no
      // template) — their job lives on the occurrence itself and is
      // authoritative. effectiveJobId must use it, not a missing template.
      final occA = makeOccurrence(id: 'occ-a', templateId: '')
          .copyWith(patternId: '', jobId: 'job-1', isImported: true);
      final occB = makeOccurrence(
              id: 'occ-b',
              templateId: '',
              shiftDate: '2026-03-03',
              startUtc: '2026-03-03T13:00:00.000Z',
              endUtc: '2026-03-03T21:00:00.000Z')
          .copyWith(patternId: '', jobId: 'job-1', isImported: true);
      final result = applyOverride(
        [occA, occB],
        overrideWith('ov-imp', 'occ-a', OverrideOperation.swap,
            swapWithOccurrenceId: 'occ-b'),
        templates: const {}, // empty map — the jobId must suffice
      );
      expect(result.issues, isEmpty,
          reason: 'both sides know job-1 via occurrence.jobId');
      expect(result.occurrences.firstWhere((o) => o.id == 'occ-a').shiftDate,
          '2026-03-03');
      expect(result.occurrences.firstWhere((o) => o.id == 'occ-b').shiftDate,
          '2026-03-02');
    });

    test('SWAP with an unknown effective job on one side is rejected hard '
        'with INCOMPLETE_SWAP (Gate A §A4)', () {
      // occ-a's template is NOT in the templates map and the occurrence has
      // no own jobId → effectiveJobId('') → the swap must be refused with a
      // clear error, never silently assumed safe.
      final occA = makeOccurrence(id: 'occ-a', templateId: 'st-ghost');
      final occB = makeOccurrence(id: 'occ-b'); // st-1 → job-1 via template
      final result = applyOverride(
        [occA, occB],
        overrideWith('ov-empty', 'occ-a', OverrideOperation.swap,
            swapWithOccurrenceId: 'occ-b'),
        templates: tmap(templates), // has st-1 + st-night, never st-ghost
      );
      expect(result.issues.single.code, ErrorCodes.incompleteSwap,
          reason: 'empty effectiveJobId on one side → hard rejection');
      expect(result.occurrences, [occA, occB], reason: 'refused — unchanged');
    });
  });

  // ---------------------------------------------------------------------------
  // applyOverride — DELETE
  // ---------------------------------------------------------------------------
  group('applyOverride DELETE', () {
    test('removes the targeted occurrence', () {
      final base = [
        makeOccurrence(id: 'occ-a'),
        makeOccurrence(id: 'occ-b', shiftDate: '2026-03-03'),
      ];
      final override = overrideWith(
        'ov-1',
        'occ-a',
        OverrideOperation.delete,
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues, isEmpty);
      expect(result.occurrences.map((o) => o.id), ['occ-b']);
    });

    test('DELETE of missing occurrence -> OCCURRENCE_NOT_FOUND, unchanged', () {
      final base = [makeOccurrence()];
      final override = overrideWith(
        'ov-1',
        'occ-ghost',
        OverrideOperation.delete,
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.issues.single.code, ErrorCodes.occurrenceNotFound);
      expect(identical(result.occurrences, base), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // P0-4: OCCURRENCE_NOT_FOUND for UPDATE/REPLACE/SPLIT/SWAP
  // ---------------------------------------------------------------------------
  group('OCCURRENCE_NOT_FOUND (P0-4)', () {
    test('every non-CREATE operation reports the missing target', () {
      final base = [makeOccurrence()];
      final ops = <Override>[
        overrideWith('ov-u', 'ghost', OverrideOperation.update,
            updatePayload: const UpdatePayload(templateId: 'st-day2')),
        overrideWith('ov-d', 'ghost', OverrideOperation.delete),
        overrideWith('ov-r', 'ghost', OverrideOperation.replace,
            replacePayload: const ReplacePayload(newTemplateId: 'st-day2')),
        overrideWith('ov-s', 'ghost', OverrideOperation.split,
            splitPayload: const SplitPayload(parts: [
              SplitPart(
                  startTime: '08:00',
                  endTime: '12:00',
                  templateId: 'st-1',
                  dateOffsetDays: 0),
            ])),
        overrideWith('ov-w', 'ghost', OverrideOperation.swap,
            swapWithOccurrenceId: 'occ-1'),
      ];

      for (final override in ops) {
        final result =
            applyOverride(base, override, templates: tmap(dayTemplates));
        expect(result.issues.single.code, ErrorCodes.occurrenceNotFound,
            reason: '${override.operation} must report OCCURRENCE_NOT_FOUND');
        // Same list instance returned — literally nothing changed.
        expect(identical(result.occurrences, base), isTrue,
            reason: '${override.operation} must return the input list unchanged');
        // Deep equality as well.
        expect(result.occurrences, base);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Provenance (P0-5)
  // ---------------------------------------------------------------------------
  group('Provenance (P0-5)', () {
    test('CREATE -> created; later UPDATE -> modified; baseline untouched', () {
      // Daily pattern Mar 2..Mar 6.
      final pattern = makePattern(cycleLengthDays: 1);
      final createOverride = overrideWith(
        'ov-create',
        'unused',
        OverrideOperation.create,
        createPayload: const CreatePayload(
          date: '2026-03-10',
          templateId: 'st-1',
          startTime: '08:00',
          endTime: '16:00',
          timezone: 'America/New_York',
        ),
      );
      final updateOverride = overrideWith(
        'ov-update',
        'ov-create', // targets the occurrence CREATE just made
        OverrideOperation.update,
        updatePayload: const UpdatePayload(templateId: 'st-day2'),
      );

      final schedule = renderEffectiveSchedule(
        pattern: pattern,
        overrides: [createOverride, updateOverride],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-10',
        templates: dayTemplates,
      );

      expect(schedule.issues, isEmpty);
      final created = schedule.occurrences.firstWhere((o) => o.id == 'ov-create');
      // Chain rule: a created occurrence that a later override touches
      // becomes modified (the last operation wins).
      expect(created.source, OccurrenceSource.modified);
      expect(created.sourceOverrideId, 'ov-update');
      expect(created.templateId, 'st-day2');
      // Baseline occurrences keep sourceOverrideId == null.
      for (final occ in schedule.occurrences) {
        if (occ.id == 'ov-create') continue;
        expect(occ.source, OccurrenceSource.baseline);
        expect(occ.sourceOverrideId, isNull);
      }
    });

    test('SPLIT parts are modified, original disappears', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-02',
        templates: dayTemplates,
      );
      final original = projection.occurrences.single;
      final splitOverride = overrideWith(
        'ov-split',
        original.id,
        OverrideOperation.split,
        splitPayload: const SplitPayload(parts: [
          SplitPart(
              startTime: '08:00',
              endTime: '12:00',
              templateId: 'st-1',
              dateOffsetDays: 0),
          SplitPart(
              startTime: '12:00',
              endTime: '16:00',
              templateId: 'st-1',
              dateOffsetDays: 0),
        ]),
      );
      final schedule = renderEffectiveSchedule(
        pattern: pattern,
        overrides: [splitOverride],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-02',
        templates: dayTemplates,
      );
      expect(schedule.issues, isEmpty);
      final ids = schedule.occurrences.map((o) => o.id).toSet();
      expect(ids, {'${original.id}#p0', '${original.id}#p1'});
      for (final part in schedule.occurrences) {
        expect(part.source, OccurrenceSource.modified);
        expect(part.sourceOverrideId, 'ov-split');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Override chain: atomicity + ordering (P0-6)
  // ---------------------------------------------------------------------------
  group('Override chain (P0-6)', () {
    test('a failing override does not roll back earlier successes nor block later ones',
        () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );
      final [occ1, occ2, occ3] = projection.occurrences;

      final good1 = overrideWith('ov-1', occ1.id, OverrideOperation.update,
          updatePayload: const UpdatePayload(templateId: 'st-day2'));
      final bad = overrideWith('ov-2', 'does-not-exist', OverrideOperation.update,
          updatePayload: const UpdatePayload(templateId: 'st-day2'));
      final good3 = overrideWith('ov-3', occ3.id, OverrideOperation.update,
          updatePayload: const UpdatePayload(templateId: 'st-day2'));

      final schedule = renderEffectiveSchedule(
        pattern: pattern,
        overrides: [good1, bad, good3],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );

      // Override #1 and #3 both applied; #2 only produced an issue.
      expect(schedule.occurrences.length, 3);
      expect(schedule.occurrences[0].templateId, 'st-day2');
      expect(schedule.occurrences[2].templateId, 'st-day2');
      // #2's target is untouched baseline (occ2 was never updated).
      expect(schedule.occurrences[1].templateId, 'st-1');
      expect(schedule.issues.single.code, ErrorCodes.occurrenceNotFound);
      expect(occ2.source, OccurrenceSource.baseline);
    });

    test('SPLIT then UPDATE targets the new part id, not the original (ordering)', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-02',
        templates: dayTemplates,
      );
      final original = projection.occurrences.single;

      final splitOv = overrideWith('ov-split', original.id, OverrideOperation.split,
          splitPayload: const SplitPayload(parts: [
            SplitPart(
                startTime: '08:00',
                endTime: '12:00',
                templateId: 'st-1',
                dateOffsetDays: 0),
            SplitPart(
                startTime: '12:00',
                endTime: '16:00',
                templateId: 'st-1',
                dateOffsetDays: 0),
          ]));
      final updateOv = overrideWith(
        'ov-update-part',
        '${original.id}#p0', // the id created by the SPLIT above
        OverrideOperation.update,
        updatePayload: const UpdatePayload(startTime: '09:00', endTime: '12:00'),
      );

      final schedule = renderEffectiveSchedule(
        pattern: pattern,
        overrides: [splitOv, updateOv],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-02',
        templates: dayTemplates,
      );

      expect(schedule.issues, isEmpty);
      final p0 = schedule.occurrences.firstWhere((o) => o.id == '${original.id}#p0');
      final p1 = schedule.occurrences.firstWhere((o) => o.id == '${original.id}#p1');
      // The UPDATE applied to the SPLIT part, not to the original (gone).
      expect(p0.startDateTimeUtc, '2026-03-02T14:00:00.000Z'); // 09:00 EST
      expect(p0.endDateTimeUtc, '2026-03-02T17:00:00.000Z'); // 12:00 EST
      expect(p0.source, OccurrenceSource.modified);
      expect(p0.sourceOverrideId, 'ov-update-part');
      expect(p1.startDateTimeUtc, '2026-03-02T17:00:00.000Z');
      expect(p1.sourceOverrideId, 'ov-split');
      expect(schedule.occurrences.any((o) => o.id == original.id), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Duplicate-id detection (M3)
  // ---------------------------------------------------------------------------
  group('Duplicate id detection (M3)', () {
    test('CREATE with an id colliding with a baseline id is reported', () {
      final base = [makeOccurrence(id: 'occ-1')];
      final override = overrideWith(
        'occ-1', // collides with the existing occurrence id
        'occ-1',
        OverrideOperation.create,
        createPayload: const CreatePayload(
          date: '2026-03-10',
          templateId: 'st-1',
          startTime: '08:00',
          endTime: '16:00',
          timezone: 'America/New_York',
        ),
      );
      final result = applyOverride(base, override, templates: tmap(dayTemplates));
      expect(result.occurrences.length, 2);
      expect(result.issues.single.code, ErrorCodes.duplicateOccurrenceId);
      expect(result.issues.single.occurrenceId, 'occ-1');
    });

    test('renderEffectiveSchedule reports whole-view duplicates', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-02',
        templates: dayTemplates,
      );
      final original = projection.occurrences.single;
      final createOv = overrideWith(
        original.id, // duplicate of baseline id
        original.id,
        OverrideOperation.create,
        createPayload: const CreatePayload(
          date: '2026-03-10',
          templateId: 'st-1',
          startTime: '08:00',
          endTime: '16:00',
          timezone: 'America/New_York',
        ),
      );
      final schedule = renderEffectiveSchedule(
        pattern: pattern,
        overrides: [createOv],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-10',
        templates: dayTemplates,
      );
      expect(
        schedule.issues.any((i) => i.code == ErrorCodes.duplicateOccurrenceId),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // renderEffectiveSchedule (D8)
  // ---------------------------------------------------------------------------
  group('renderEffectiveSchedule', () {
    test('baseline + overrides, sorted, with provenance', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );
      final middle = projection.occurrences[1];
      final replaceOv = overrideWith(
        'ov-1',
        middle.id,
        OverrideOperation.replace,
        replacePayload: const ReplacePayload(newTemplateId: 'st-day2'),
      );
      final schedule = renderEffectiveSchedule(
        pattern: pattern,
        overrides: [replaceOv],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );
      expect(schedule.issues, isEmpty);
      expect(schedule.occurrences.length, 3);
      expect(schedule.occurrences.map((o) => o.shiftDate).toList(),
          ['2026-03-02', '2026-03-03', '2026-03-04']);
      expect(schedule.occurrences[0].source, OccurrenceSource.baseline);
      expect(schedule.occurrences[1].source, OccurrenceSource.modified);
      expect(schedule.occurrences[1].sourceOverrideId, 'ov-1');
      expect(schedule.occurrences[1].templateId, 'st-day2');
      expect(schedule.occurrences[2].source, OccurrenceSource.baseline);
    });

    test('DELETE removes the day from view (override record still exists)', () {
      final pattern = makePattern(cycleLengthDays: 1);
      // Render WITHOUT the delete: 3 occurrences.
      final without = renderEffectiveSchedule(
        pattern: pattern,
        overrides: const [],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );
      expect(without.occurrences.length, 3);

      final target = without.occurrences[1].id;
      final deleteOv = overrideWith('ov-del', target, OverrideOperation.delete);
      // Render WITH the delete: 2 occurrences; the Override record (not a
      // soft-delete flag on the occurrence) is what removes it (D6).
      final withDelete = renderEffectiveSchedule(
        pattern: pattern,
        overrides: [deleteOv],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );
      expect(withDelete.occurrences.length, 2);
      expect(withDelete.occurrences.any((o) => o.id == target), isFalse);
      expect(withDelete.issues, isEmpty);
    });

    test('DST gap day in range: no occurrence, issue present (anti-silent-drop)', () {
      final pattern = makePattern(
        cycleLengthDays: 1,
        anchorDate: '2026-10-31',
        startDate: '2026-10-01',
      );
      final templates = [makeTemplate(startTime: '01:30', endTime: '09:30')];
      final schedule = renderEffectiveSchedule(
        pattern: pattern,
        overrides: const [],
        rangeStart: '2026-10-31',
        rangeEnd: '2026-11-02',
        templates: templates,
      );
      expect(schedule.occurrences.map((o) => o.shiftDate).toList(),
          ['2026-10-31', '2026-11-02']);
      expect(schedule.issues.single.code, ErrorCodes.ambiguousLocalTime);
      expect(schedule.issues.single.shiftDate, '2026-11-01');
    });

    test('render never mutates its inputs (INVARIANT-001)', () {
      final pattern = makePattern(cycleLengthDays: 1);
      final projection = projectOccurrences(
        pattern: pattern,
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );
      final before = projection.occurrences
          .map((o) => '${o.id}|${o.templateId}|${o.startDateTimeUtc}')
          .toList();

      final override = overrideWith(
        'ov-1',
        projection.occurrences[0].id,
        OverrideOperation.delete,
      );
      renderEffectiveSchedule(
        pattern: pattern,
        overrides: [override],
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-04',
        templates: dayTemplates,
      );

      final after = projection.occurrences
          .map((o) => '${o.id}|${o.templateId}|${o.startDateTimeUtc}')
          .toList();
      expect(after, before);
    });
  });

  // ---------------------------------------------------------------------------
  // VersionedEntity + D9 phase continuity
  // ---------------------------------------------------------------------------
  group('VersionedEntity', () {
    test('isActiveOn checks date range correctly', () {
      final v1 = VersionedEntity(
        effectiveFrom: '2026-01-01',
        effectiveUntil: '2026-06-30',
      );
      expect(v1.isActiveOn('2026-03-15'), isTrue);
      expect(v1.isActiveOn('2026-01-01'), isTrue);
      expect(v1.isActiveOn('2026-06-30'), isTrue);
      expect(v1.isActiveOn('2026-07-01'), isFalse);
      expect(v1.isActiveOn('2025-12-31'), isFalse);
    });

    test('getActivePattern finds the correct version', () {
      final pat1 = makePattern(id: 'pat-v1', anchorDate: '2026-01-01');
      final pat1closed = ShiftPattern(
        id: 'pat-v1',
        jobId: 'job-1',
        name: 'V1',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-1'),
        anchorDate: '2026-01-01',
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-01-01',
        effectiveUntil: '2026-06-30',
      );
      final pat2 = ShiftPattern(
        id: 'pat-v2',
        jobId: 'job-1',
        name: 'V2',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-2'),
        anchorDate: '2026-07-01',
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-07-01',
        effectiveUntil: null,
      );
      expect(getActivePattern(versions: [pat1, pat2], date: '2026-03-15')?.id,
          'pat-v1');
      expect(pat1closed.isActiveOn('2026-03-15'), isTrue);
      expect(getActivePattern(versions: [pat1closed, pat2], date: '2026-08-01')?.id,
          'pat-v2');
    });
  });

  group('createNewVersion (D9)', () {
    test('new version keeps the ORIGINAL anchorDate (phase continuity)', () {
      // 4-on/4-off anchored 2026-01-01 (a Thursday->... 4 work days then 4 off).
      final original = ShiftPattern(
        id: 'pat-4on4off',
        jobId: 'job-1',
        name: '4on/4off',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 8,
        sequence: ['DAY', 'DAY', 'DAY', 'DAY', 'OFF', 'OFF', 'OFF', 'OFF'],
        anchorDate: '2026-01-01',
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-01-01',
        effectiveUntil: null,
      );
      final dayTemplate = makeTemplate(id: 'DAY');

      final (_, newVersion) = createNewVersion(
        currentPattern: original,
        newEffectiveFrom: '2026-06-15',
        newName: '4on/4off (updated)',
        newCycleLengthDays: 8,
        newSequence: ['DAY', 'DAY', 'DAY', 'DAY', 'OFF', 'OFF', 'OFF', 'OFF'],
      );

      // D9: anchorDate must be carried over, NOT reset to newEffectiveFrom.
      expect(newVersion.anchorDate, '2026-01-01');

      // 2026-01-01 -> 2026-06-15 is 165 days; 165 % 8 = 5 -> sequence[5] = OFF.
      // If the anchor had been reset to 2026-06-15, day 0 would be DAY.
      // With the anchor preserved, the first occurrence after the version
      // switch is 2026-06-18 (index 0 of the next cycle).
      final projection = projectOccurrences(
        pattern: newVersion,
        rangeStart: '2026-06-15',
        rangeEnd: '2026-06-22',
        templates: [dayTemplate],
      );
      final dates = projection.occurrences.map((o) => o.shiftDate).toList();
      expect(dates, ['2026-06-18', '2026-06-19', '2026-06-20', '2026-06-21']);
    });

    test('old pattern is closed but never mutated', () {
      final original = makePattern(id: 'pat-old', cycleLengthDays: 7);
      final (oldClosed, _) = createNewVersion(
        currentPattern: original,
        newEffectiveFrom: '2026-07-01',
        newName: 'V2',
        newCycleLengthDays: 7,
        newSequence: List.filled(7, 'st-1'),
      );
      expect(oldClosed.id, 'pat-old');
      expect(oldClosed.effectiveUntil, '2026-06-30');
      expect(oldClosed.anchorDate, original.anchorDate);
      // Original untouched.
      expect(original.effectiveUntil, isNull);
    });
  });
}
