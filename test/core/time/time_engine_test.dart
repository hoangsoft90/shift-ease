// =============================================================================
// ShiftEase Time Engine — Golden Test Suite Runner
// =============================================================================
//
// Reads ALL test cases from test/golden/time_engine_cases.json and runs them
// against resolveShift(). No hard-coded values — single source of truth.
//
// Grouping is driven by EXPECTED SHAPE, not by case id/type prefixes:
//   - case with expected.utcStart  -> full UTC/duration/offset resolution
//   - case with expected.error     -> error code (+ ambiguous options)
// Behavioral/invariant PROPERTY_TEST / INVARIANT_TEST entries carry no
// direct assertion here — they are implemented as explicit Dart tests below
// (Invariant Tests group) or in the pattern/property suites.
//
// Gate 0 additions (plan3_final.md + plan3_final_v2.md):
//   - H-4 round-trip property: every RESOLVED candidate must map back to the
//     exact wall-clock input, over 1 full year x every hour x NY/Berlin/Lord
//     Howe (the 30-minute DST zone that kills the old ±1h heuristic).
//   - DST-009/010 (Lord Howe 30'), VALID-001..004 (INVALID_* distinct from
//     DST outcomes), LH-001 (+10:30 half-hour offset) — all in the JSON.
//
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/core/time/time_types.dart';

/// Load golden test cases from JSON file.
List<Map<String, dynamic>> loadGoldenCases() {
  final candidates = [
    'test/golden/time_engine_cases.json',
    '../test/golden/time_engine_cases.json',
    '../../test/golden/time_engine_cases.json',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return (data['cases'] as List)
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
    }
  }

  throw FileSystemException(
    'Could not find time_engine_cases.json in any of: $candidates',
  );
}

/// Case expects resolved UTC values.
bool hasUtcExpected(Map<String, dynamic> testCase) {
  final expected = testCase['expected'] as Map<String, dynamic>?;
  return expected != null && expected.containsKey('utcStart');
}

/// Case expects an error outcome.
bool isErrorCase(Map<String, dynamic> testCase) {
  final expected = testCase['expected'] as Map<String, dynamic>?;
  return expected != null && expected.containsKey('error');
}

void main() {
  setUpAll(() {
    initializeTimezoneDatabase();
  });

  final goldenCases = loadGoldenCases();

  final utcCases = goldenCases.where(hasUtcExpected).length;
  final errorCases = goldenCases.where(isErrorCase).length;

  print('Golden test suite: ${goldenCases.length} total cases');
  print('  UTC-verified: $utcCases');
  print('  Error cases: $errorCases');

  // =========================================================================
  // Group 1: every case with expected.utcStart — resolved fully.
  // =========================================================================
  group('UTC-Verified Cases', () {
    for (final testCase in goldenCases.where(hasUtcExpected)) {
      final id = testCase['id'] as String;
      final name = testCase['name'] as String;
      final tzName = testCase['timezone'] as String;
      final shiftDate = testCase['shiftDate'] as String;
      final startTime = testCase['startTime'] as String;
      final endTime = testCase['endTime'] as String;
      final expected = testCase['expected'] as Map<String, dynamic>;

      test('$id: $name', () {
        final result = resolveShift(
          shiftDate: shiftDate,
          startTime: startTime,
          endTime: endTime,
          timezone: tzName,
        );

        expect(result.isSuccess, true,
            reason: 'Expected success but got error: ${result.error}');
        expect(result.utcStart!.isoString, expected['utcStart']);
        expect(result.utcEnd!.isoString, expected['utcEnd']);

        final expectedDuration = expected['durationHours'] as num;
        // Fractional durations (e.g. MIDNIGHT-001 0.0333h) need closeTo.
        expect(result.duration!.hours, closeTo(expectedDuration.toDouble(), 0.01),
            reason: 'durationHours mismatch for $id');

        expect(result.startOffset!.hours,
            (expected['startOffset'] as num).toDouble());
        expect(result.endOffset!.hours, (expected['endOffset'] as num).toDouble());
      });
    }
  });

  // =========================================================================
  // Group 2: every case with expected.error — including INVALID_* (D7) and
  // ambiguous options (D4: engine returns options, never auto-selects).
  // =========================================================================
  group('Error Cases', () {
    for (final testCase in goldenCases.where(isErrorCase)) {
      final id = testCase['id'] as String;
      final name = testCase['name'] as String;
      final tzName = testCase['timezone'] as String;
      final shiftDate = testCase['shiftDate'] as String;
      final startTime = testCase['startTime'] as String;
      final endTime = testCase['endTime'] as String;
      final expected = testCase['expected'] as Map<String, dynamic>;
      final expectedError = expected['error'] as String;

      test('$id: $name', () {
        final result = resolveShift(
          shiftDate: shiftDate,
          startTime: startTime,
          endTime: endTime,
          timezone: tzName,
        );

        expect(result.isSuccess, false);
        expect(result.error, expectedError,
            reason: 'Expected error "$expectedError" but got "${result.error}"');

        if (expected.containsKey('options')) {
          final expectedOptions =
              (expected['options'] as List).cast<Map<String, dynamic>>();
          expect(result.options, isNotNull,
              reason: 'Expected options but got null');
          expect(result.options!.length, expectedOptions.length,
              reason: 'option count mismatch for $id');
          for (var i = 0; i < expectedOptions.length; i++) {
            expect(result.options![i].isoString, expectedOptions[i]['utc'],
                reason: 'Option $i UTC mismatch for $id');
          }
        } else {
          // No options expected (nonexistent / INVALID_* / END_BEFORE_START).
          expect(result.options, isNull,
              reason: 'Did not expect options for $id');
        }
      });
    }
  });

  // =========================================================================
  // Group 3: explicit invariant tests (INVARIANT-002/003/007).
  // =========================================================================
  group('Invariant Tests', () {
    test('INVARIANT-002: Duration from UTC instants, not local subtraction', () {
      // DST-001 case: 22:00 -> 06:00 is 8h local, but 7h UTC (spring-forward).
      final result = resolveShift(
        shiftDate: '2026-03-07',
        startTime: '22:00',
        endTime: '06:00+1',
        timezone: 'America/New_York',
      );
      expect(result.isSuccess, true);
      expect(result.duration!.hours, 7.0);
    });

    test('INVARIANT-002: durationHours equals (utcEnd - utcStart) in hours', () {
      final result = resolveShift(
        shiftDate: '2026-06-15',
        startTime: '07:00',
        endTime: '15:00',
        timezone: 'America/New_York',
      );
      expect(result.isSuccess, true);
      final computed =
          result.utcStart!.durationTo(result.utcEnd!).inHours;
      expect(result.duration!.hours, computed);
    });

    test('INVARIANT-007: Existing occurrence keeps original timezone', () {
      final retainsOriginal = checkTimezoneRetention(
        originalTimezone: 'America/New_York',
        currentTimezone: 'America/Los_Angeles',
        occurrenceTimezone: 'America/New_York',
      );
      expect(retainsOriginal, true);
    });

    test('INVARIANT-003: Recurrence uses local civil time', () {
      final usesLocalBasis = checkRecurrenceBasis(
        patternTimezone: 'America/New_York',
        patternLocalTime: '19:00',
        occurrenceLocalTime: '19:00',
        occurrenceTimezone: 'America/New_York',
      );
      expect(usesLocalBasis, true);
    });
  });

  // =========================================================================
  // Group 4: duration calculation unit tests
  // =========================================================================
  group('Duration Calculation', () {
    test('Calculate duration from UTC instants', () {
      final start = UtcInstant.parse('2026-03-08T03:00:00.000Z');
      final end = UtcInstant.parse('2026-03-08T10:00:00.000Z');
      final duration = calculateDuration(utcStart: start, utcEnd: end);
      expect(duration.hours, 7.0);
    });

    test('Calculate duration across midnight', () {
      final start = UtcInstant.parse('2026-06-15T23:00:00.000Z');
      final end = UtcInstant.parse('2026-06-16T11:00:00.000Z');
      final duration = calculateDuration(utcStart: start, utcEnd: end);
      expect(duration.hours, 12.0);
    });
  });

  // =========================================================================
  // Group 5 (H-4): round-trip property — every RESOLVED candidate must map
  // back to the exact wall-clock input. One full year, every hour, in the
  // three zones that matter: America/New_York (60-min DST), Europe/Berlin
  // (60-min DST), Australia/Lord_Howe (30-min DST).
  // =========================================================================
  group('Round-trip property (H-4)', () {
    const zones = [
      'America/New_York',
      'Europe/Berlin',
      'Australia/Lord_Howe',
    ];

    for (final zoneName in zones) {
      test('$zoneName: every hour of 2026 round-trips wall-clock -> UTC -> wall-clock',
          () {
        final location = tz.getLocation(zoneName);
        final yearStart = DateTime.utc(2026, 1, 1);
        final yearEnd = DateTime.utc(2026, 12, 31);

        var dayCount = 0;
        var checkedResolved = 0;
        var checkedAmbiguousOptions = 0;

        var day = yearStart;
        while (!day.isAfter(yearEnd)) {
          for (var hour = 0; hour < 24; hour++) {
            final date = '${day.year.toString().padLeft(4, '0')}-'
                '${day.month.toString().padLeft(2, '0')}-'
                '${day.day.toString().padLeft(2, '0')}';
            final time = '${hour.toString().padLeft(2, '0')}:00';

            final result =
                resolveUtcInstant(date: date, time: time, timezone: zoneName);

            if (result.ambiguity == DstAmbiguityType.nonexistent) {
              continue; // real DST gap — nothing resolves, nothing to check
            }

            if (result.utcInstant != null) {
              checkedResolved++;
              final local = tz.TZDateTime.from(
                DateTime.fromMillisecondsSinceEpoch(
                  result.utcInstant!.millisecondsSinceEpoch,
                  isUtc: true,
                ),
                location,
              );
              expect(
                local.year == day.year &&
                    local.month == day.month &&
                    local.day == day.day &&
                    local.hour == hour &&
                    local.minute == 0,
                isTrue,
                reason: '$zoneName: $date $time resolved to '
                    '${result.utcInstant!.isoString} which renders back as '
                    '${local.toIso8601String()} — wall-clock round-trip failed.',
              );
            }

            if (result.options != null) {
              for (final option in result.options!) {
                checkedAmbiguousOptions++;
                final local = tz.TZDateTime.from(
                  DateTime.fromMillisecondsSinceEpoch(
                    option.millisecondsSinceEpoch,
                    isUtc: true,
                  ),
                  location,
                );
                expect(
                  local.year == day.year &&
                      local.month == day.month &&
                      local.day == day.day &&
                      local.hour == hour &&
                      local.minute == 0,
                  isTrue,
                  reason: '$zoneName: ambiguous option ${option.isoString} for '
                      '$date $time renders back as '
                      '${local.toIso8601String()} — round-trip failed.',
                );
              }
            }
          }
          dayCount++;
          day = day.add(const Duration(days: 1));
        }

        expect(dayCount, 365); // 2026 is not a leap year
        expect(checkedResolved, greaterThan(0));
        // NY/Berlin have ambiguous top-of-hours (Lord Howe's 30-min overlap
        // is 01:30-02:00 so no top-of-hour lands in it — that case is covered
        // exactly by golden DST-009 at 01:45).
        if (zoneName == 'America/New_York' ||
            zoneName == 'Europe/Berlin') {
          expect(checkedAmbiguousOptions, greaterThan(0),
              reason: '$zoneName should have ambiguous top-of-hours in 2026');
        }
      });
    }
  });
}
