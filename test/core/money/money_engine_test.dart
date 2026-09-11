// =============================================================================
// ShiftEase Money Engine — Golden Test Suite Runner (PAY-001..014)
// =============================================================================
//
// Reads test/golden/money_engine_cases.json and runs every case against the
// Money Engine. No hard-coded expected values — single source of truth.
//
// Locked semantics exercised (plan2 §5 + Gate 1):
//   - Method B: regular = shiftHours - overtimeHours (no double-count)
//   - Multi-rule OT: max() between applicable rules, never the sum
//   - Differentials apply to REGULAR hours only
//   - PAY-013 window overlap: half-open wall-clock hours (5h, user-approved)
//   - PAY-014: LIFO weekly allocation (allocateWeeklyOvertime)
//   - PAY-011: versioned PayRule + active-rule lookup (INVARIANT-006)
//
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:shiftease/core/pattern/pattern_types.dart'
    show ShiftOccurrence, OccurrenceSource;
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/money/money_engine.dart';
import 'package:shiftease/core/money/payrule_templates.dart';

List<Map<String, dynamic>> loadGoldenCases() {
  final candidates = [
    'test/golden/money_engine_cases.json',
    '../test/golden/money_engine_cases.json',
    '../../test/golden/money_engine_cases.json',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (data['cases'] as List)
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
    }
  }
  throw FileSystemException('Could not find money_engine_cases.json');
}

// ---------------------------------------------------------------------------
// JSON -> domain parsing (test-side only; library stays JSON-free)
// ---------------------------------------------------------------------------

PayDifferential parseDiff(Map<String, dynamic> json) {
  final calc = json['calc'] as Map<String, dynamic>;
  Map<String, dynamic>? windowJson = (json['window'] as Map?)?.cast<String, dynamic>();
  return PayDifferential(
    id: json['id'] as String?,
    type: DifferentialType.fromName(json['type'] as String),
    mode: DifferentialMode.fromName(calc['mode'] as String),
    value: (calc['value'] as num).toDouble(),
    scope: DifferentialScope.fromName(json['appliesTo'] as String),
    window: windowJson == null
        ? null
        : DifferentialWindow(
            startLocal: windowJson['startLocal'] as String,
            endLocal: windowJson['endLocal'] as String,
          ),
  );
}

OvertimeRule parseOtRule(Map<String, dynamic> json) => OvertimeRule(
      thresholdHours: (json['thresholdHours'] as num).toDouble(),
      period: OvertimePeriod.fromName(json['period'] as String),
      multiplier: (json['multiplier'] as num).toDouble(),
    );

PayRule parsePayRule(Map<String, dynamic> json, {required String id}) {
  final diffs = (json['differentials'] as List? ?? const [])
      .map((d) => parseDiff(Map<String, dynamic>.from(d as Map)))
      .toList();
  final rules = (json['overtimeRules'] as List? ?? const [])
      .map((r) => parseOtRule(Map<String, dynamic>.from(r as Map)))
      .toList();
  return PayRule(
    id: id,
    jobId: 'job-1',
    // 'baseRate' (single-shift inputs) or 'baseHourlyRate' (versioned rules).
    baseHourlyRate: (json['baseRate'] ?? json['baseHourlyRate'] as num)
        .toDouble(),
    differentials: diffs,
    overtimeRules: rules,
    effectiveFrom: json['effectiveFrom'] as String? ?? '2000-01-01',
    effectiveUntil: json['effectiveUntil'] as String?,
  );
}

Map<String, dynamic> inputJson(Map<String, dynamic> caseJson) =>
    caseJson['input'] as Map<String, dynamic>;

void checkBreakdown(
  PayBreakdown bd,
  Map<String, dynamic> expected, {
  required String caseId,
}) {
  double diffOf(String key) => bd.differentialPay[DifferentialType.fromName(
          key.replaceFirst('Diff', ''))] ??
      0.0;

  if (expected.containsKey('regularPay')) {
    expect(bd.regularPay, closeTo((expected['regularPay'] as num).toDouble(), 0.005),
        reason: '$caseId regularPay');
  }
  if (expected.containsKey('overtimeHours')) {
    expect(bd.overtimeHours,
        closeTo((expected['overtimeHours'] as num).toDouble(), 1e-9),
        reason: '$caseId overtimeHours');
  }
  if (expected.containsKey('overtimePay')) {
    expect(bd.overtimePay,
        closeTo((expected['overtimePay'] as num).toDouble(), 0.005),
        reason: '$caseId overtimePay');
  }
  for (final key in ['nightDiff', 'weekendDiff', 'holidayDiff', 'hazardDiff']) {
    if (expected.containsKey(key)) {
      expect(diffOf(key), closeTo((expected[key] as num).toDouble(), 0.005),
          reason: '$caseId $key');
    }
  }
  if (expected.containsKey('total')) {
    expect(bd.total, closeTo((expected['total'] as num).toDouble(), 0.005),
        reason: '$caseId total');
  }
  if (expected.containsKey('breakdownLines')) {
    expect(bd.lines.length, expected['breakdownLines'],
        reason: '$caseId breakdownLines '
            '(labels: ${bd.lines.map((l) => l.label).join(', ')})');
  }
}

void main() {
  final cases = loadGoldenCases();
  print('Money golden suite: ${cases.length} cases');

  // -------------------------------------------------------------------------
  // Generic PAY-x breakdown cases (single shift under one active rule).
  // -------------------------------------------------------------------------
  group('Pay Breakdown (golden)', () {
    for (final testCase in cases) {
      final id = testCase['id'] as String;
      if (!id.startsWith('PAY-')) continue;
      // Handled in their own groups below.
      if (const {
        'PAY-010',
        'PAY-011',
        'PAY-014'
      }.contains(id)) {
        continue;
      }
      final name = testCase['name'] as String;
      final expected = testCase['expected'] as Map<String, dynamic>;
      final input = inputJson(testCase);

      test('$id: $name', () {
        final diffs =
            (input['differentials'] as List? ?? const [])
                .map((d) => parseDiff(Map<String, dynamic>.from(d as Map)))
                .toList();
        final rules = (input['overtimeRules'] as List? ?? const [])
            .map((r) => parseOtRule(Map<String, dynamic>.from(r as Map)))
            .toList();

        final ruleWithArrays = PayRule(
          id: 'rule-$id',
          jobId: 'job-1',
          baseHourlyRate: (input['baseRate'] as num).toDouble(),
          differentials: diffs,
          overtimeRules: rules,
          effectiveFrom: '2000-01-01',
        );

        final payInput = PayInput(
          shiftHours: (input['shiftHours'] as num).toDouble(),
          dailyHours: (input['dailyHours'] as num?)?.toDouble() ?? 0,
          weeklyHours: (input['weeklyHours'] as num?)?.toDouble() ?? 0,
          isNightShift: input['isNightShift'] as bool? ?? false,
          isWeekend: input['isWeekend'] as bool? ?? false,
          isHoliday: input['isHoliday'] as bool? ?? false,
          shiftStartLocal: input['shiftStartLocal'] as String?,
          shiftEndLocal: input['shiftEndLocal'] as String?,
        );

        final bd = calculatePayBreakdown(
            input: payInput, rule: ruleWithArrays);
        checkBreakdown(bd, expected, caseId: id);
      });
    }
  });

  // -------------------------------------------------------------------------
  // PAY-010: PayRuleTemplate library applied end-to-end.
  // -------------------------------------------------------------------------
  group('PayRuleTemplate (PAY-010)', () {
    test('tpl-us-ca-nurse seed exists and matches the golden expectations', () {
      final template = payRuleTemplateById('tpl-us-ca-nurse');
      expect(template.name, 'US Hospital Nurse — California');
      expect(template.country, TemplateCountry.us);
      expect(template.region, 'California');
      expect(template.overtimeRules.length, 2);
      expect(template.overtimeRules[0].thresholdHours, 8);
      expect(template.overtimeRules[0].period, OvertimePeriod.shift);
      expect(template.overtimeRules[1].thresholdHours, 40);
      expect(template.overtimeRules[1].period, OvertimePeriod.week);
      expect(template.differentials.single.type, DifferentialType.night);

      final caseJson = cases.firstWhere((c) => c['id'] == 'PAY-010');
      final input = caseJson['input'] as Map<String, dynamic>;
      final expected = caseJson['expected'] as Map<String, dynamic>;
      final rule = PayRule(
        id: 'rule-PAY-010',
        jobId: 'job-1',
        // PAY-010 sets its own base rate; the template supplies structure.
        baseHourlyRate: (input['baseRate'] as num).toDouble(),
        differentials: template.differentials,
        overtimeRules: template.overtimeRules,
        effectiveFrom: '2000-01-01',
      );
      final bd = calculatePayBreakdown(
        input: PayInput(
          shiftHours: (input['shiftHours'] as num).toDouble(),
          dailyHours: (input['dailyHours'] as num).toDouble(),
          weeklyHours: (input['weeklyHours'] as num).toDouble(),
          isNightShift: input['isNightShift'] as bool? ?? false,
        ),
        rule: rule,
      );
      checkBreakdown(bd, expected, caseId: 'PAY-010');
    });
  });

  // -------------------------------------------------------------------------
  // PAY-011: PayRule versioning + INVARIANT-006.
  // -------------------------------------------------------------------------
  group('PayRule versioning (PAY-011 / INVARIANT-006)', () {
    test('occurrence uses the rule ACTIVE at its date; history is stable', () {
      final caseJson = cases.firstWhere((c) => c['id'] == 'PAY-011');
      final input = inputJson(caseJson);
      final expected = caseJson['expected'] as Map<String, dynamic>;

      final v1 = parsePayRule(
        Map<String, dynamic>.from(input['payRuleV1'] as Map),
        id: 'rule-v1',
      );
      final v2 = parsePayRule(
        Map<String, dynamic>.from(input['payRuleV2'] as Map),
        id: 'rule-v2',
      );
      final allRules = [v1, v2];

      // Active rule per date.
      expect(getActivePayRule(
              rules: allRules, jobId: 'job-1', date: '2026-06-15')?.id,
          'rule-v1');
      expect(getActivePayRule(
              rules: allRules, jobId: 'job-1', date: '2026-07-15')?.id,
          'rule-v2');

      PayBreakdown payFor(String date, num shiftHours) {
        final active = getActivePayRule(
            rules: allRules, jobId: 'job-1', date: date)!;
        return calculatePayBreakdown(
          input: PayInput(
            shiftHours: shiftHours.toDouble(),
            dailyHours: shiftHours.toDouble(),
            weeklyHours: 30,
          ),
          rule: active,
        );
      }

      final occV1 = payFor('2026-06-15', input['occurrenceV1']['shiftHours']);
      final occV2 = payFor('2026-07-15', input['occurrenceV2']['shiftHours']);

      final expV1 = expected['occurrenceV1_pay'] as Map<String, dynamic>;
      final expV2 = expected['occurrenceV2_pay'] as Map<String, dynamic>;
      checkBreakdown(occV1, expV1, caseId: 'PAY-011/v1');
      checkBreakdown(occV2, expV2, caseId: 'PAY-011/v2');

      // INVARIANT-006: with v2 already in the list, re-querying the v1 date
      // still yields the v1 pricing ($385) — never rewritten by the newer rate.
      expect(occV1.total, closeTo(385.00, 0.005));
      expect(occV2.total, closeTo(480.00, 0.005));
    });
  });

  // -------------------------------------------------------------------------
  // PAY-014: real multi-shift week + LIFO allocation.
  // -------------------------------------------------------------------------
  group('Weekly LIFO allocation (PAY-014)', () {
    test('3x14h week: 2h OT goes to the last chronological shift', () {
      final caseJson = cases.firstWhere((c) => c['id'] == 'PAY-014');
      final input = inputJson(caseJson);
      final expected = caseJson['expected'] as Map<String, dynamic>;
      final shiftsJson = (input['shifts'] as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      final baseRate = (input['baseRate'] as num).toDouble();

      // Build resolved occurrences: UTC fixture derived deterministically so
      // duration == the JSON shiftHours (14h). These are synthetic inputs for
      // the allocation (only duration + date order are read) — not golden UTC.
      final occurrences = <ShiftOccurrence>[];
      for (final s in shiftsJson) {
        final date = DateTime.parse(s['shiftDate'] as String);
        final startMs = DateTime.utc(date.year, date.month, date.day, 11)
            .millisecondsSinceEpoch;
        final hours = (s['shiftHours'] as num).toDouble();
        final start =
            DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
        final end = start.add(Duration(milliseconds: (hours * 3600000).round()));
        occurrences.add(ShiftOccurrence(
          id: s['id'] as String,
          patternId: 'pat-x',
          shiftDate: s['shiftDate'] as String,
          templateId: 'st-x',
          startDateTimeUtc: start.toIso8601String(),
          endDateTimeUtc: end.toIso8601String(),
          timezone: 'UTC',
          source: OccurrenceSource.baseline,
        ));
      }

      final threshold =
          ((input['overtimeRules'] as List).first as Map)['thresholdHours']
              as num;
      final allocation = allocateWeeklyOvertime(
        shifts: occurrences,
        weeklyThreshold: threshold.toDouble(),
      );

      // Allocation itself.
      final expectedAlloc =
          expected['allocation'] as Map<String, dynamic>;
      for (final entry in expectedAlloc.entries) {
        final exp = Map<String, dynamic>.from(entry.value as Map);
        expect(allocation[entry.key],
            closeTo((exp['overtimeHours'] as num).toDouble(), 1e-9),
            reason: 'PAY-014 allocation for ${entry.key}');
      }
      expect(allocation.values.fold(0.0, (s, v) => s + v),
          closeTo((expected['weeklyOvertimeHours'] as num).toDouble(), 1e-9));

      // Per-shift breakdown with the pre-assigned hours.
      final weekRule = OvertimeRule(
        thresholdHours: threshold.toDouble(),
        period: OvertimePeriod.week,
        multiplier:
            ((((input['overtimeRules'] as List).first as Map)['multiplier'])
                    as num)
                .toDouble(),
      );

      var weekTotalPay = 0.0;
      var weekTotalHours = 0.0;
      for (final s in shiftsJson) {
        final id = s['id'] as String;
        final hours = (s['shiftHours'] as num).toDouble();
        final bd = calculatePayBreakdown(
          input: PayInput(
            shiftHours: hours,
            assignedOvertimeHours: allocation[id],
            assignedMultiplier: weekRule.multiplier,
          ),
          rule: PayRule(
            id: 'rule-PAY-014',
            jobId: 'job-1',
            baseHourlyRate: baseRate,
            differentials: const [],
            overtimeRules: [weekRule],
            effectiveFrom: '2000-01-01',
          ),
        );
        checkBreakdown(
            bd, Map<String, dynamic>.from(expectedAlloc[id] as Map),
            caseId: 'PAY-014/$id');
        weekTotalPay += bd.total;
        weekTotalHours += hours;
      }

      expect(weekTotalHours,
          closeTo((expected['weeklyTotalHours'] as num).toDouble(), 1e-9));
      expect(weekTotalPay,
          closeTo((expected['weeklyTotalPay'] as num).toDouble(), 0.005));
    });
  });

  // -------------------------------------------------------------------------
  // Unit tests for semantics the goldens do not fully isolate.
  // -------------------------------------------------------------------------
  group('Money Engine unit semantics', () {
    PayRule ruleOf({
      List<PayDifferential> diffs = const [],
      required List<OvertimeRule> otRules,
      double rate = 35,
    }) {
      return PayRule(
        id: 'r',
        jobId: 'job-1',
        baseHourlyRate: rate,
        differentials: diffs,
        overtimeRules: otRules,
        effectiveFrom: '2000-01-01',
      );
    }

    test('DAY overtime rule (German-style daily >8h)', () {
      // 10h shift on a day totaling 10h; DAY threshold 8h -> 2h OT at 1.5.
      final bd = calculatePayBreakdown(
        input: const PayInput(
          shiftHours: 10,
          dailyHours: 10,
          weeklyHours: 30,
        ),
        rule: ruleOf(otRules: [
          OvertimeRule(
              thresholdHours: 8,
              period: OvertimePeriod.day,
              multiplier: 1.5),
        ]),
      );
      expect(bd.overtimeHours, closeTo(2, 1e-9));
      expect(bd.overtimePay, closeTo(105, 0.005));
      expect(bd.regularPay, closeTo(280, 0.005)); // 8h x 35, no double count
    });

    test('tie in OT hours picks the higher multiplier (plan2 §5.4)', () {
      // SHIFT >8h @ x1.0 (weird rule) and WEEK >40h @ x1.5 both yield 2h.
      final bd = calculatePayBreakdown(
        input: const PayInput(shiftHours: 10, weeklyHours: 42),
        rule: ruleOf(otRules: [
          OvertimeRule(
              thresholdHours: 8,
              period: OvertimePeriod.shift,
              multiplier: 1.0),
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ]),
      );
      expect(bd.overtimeHours, closeTo(2, 1e-9));
      // 2h x $35 x 1.5 = $105 — NOT 2h x $35 x 1.0 = $70.
      expect(bd.overtimePay, closeTo(105, 0.005));
    });

    test('windowOverlapHours: half-open wall-clock overlap', () {
      const window =
          DifferentialWindow(startLocal: '22:00', endLocal: '06:00');
      // PAY-013 style: 15:00 -> 03:00+1 overlaps 5h (22:00-03:00).
      expect(
        windowOverlapHours(
            shiftStartLocal: '15:00',
            shiftEndLocal: '03:00+1',
            window: window),
        closeTo(5, 1e-9),
      );
      // Fully inside the window: 23:00 -> 01:00+1 = 2h.
      expect(
        windowOverlapHours(
            shiftStartLocal: '23:00',
            shiftEndLocal: '01:00+1',
            window: window),
        closeTo(2, 1e-9),
      );
      // No overlap: 08:00 -> 16:00 day shift.
      expect(
        windowOverlapHours(
            shiftStartLocal: '08:00',
            shiftEndLocal: '16:00',
            window: window),
        closeTo(0, 1e-9),
      );
      // Whole night: 22:00 -> 06:00+1 matches the window fully (8h).
      expect(
        windowOverlapHours(
            shiftStartLocal: '22:00',
            shiftEndLocal: '06:00+1',
            window: window),
        closeTo(8, 1e-9),
      );
    });

    test('allocateWeeklyOvertimeHours: decoupled core equals occurrence path', () {
      // Same week through BOTH entry points: the ShiftOccurrence wrapper
      // (pattern layer) and the pure hours core (import CommittedShift layer)
      // must produce identical allocations.
      ShiftOccurrence occ(String id, String date, double hours) =>
          ShiftOccurrence(
            id: id,
            patternId: 'p',
            shiftDate: date,
            templateId: 't',
            startDateTimeUtc: '${date}T00:00:00.000Z',
            endDateTimeUtc: DateTime.fromMillisecondsSinceEpoch(
                    DateTime.parse('${date}T00:00:00.000Z')
                            .millisecondsSinceEpoch +
                        (hours * 3600000).round(),
                    isUtc: true)
                .toIso8601String(),
            timezone: 'UTC',
            source: OccurrenceSource.baseline,
          );
      final occurrences = [
        occ('a', '2026-09-07', 14),
        occ('b', '2026-09-09', 14),
        occ('c', '2026-09-11', 14),
      ];
      final fromOccurrences = allocateWeeklyOvertime(
          shifts: occurrences, weeklyThreshold: 40);
      final fromHours = allocateWeeklyOvertimeHours(
        shifts: [
          for (final o in occurrences)
            (
              id: o.id,
              shiftDate: o.shiftDate,
              hours: (DateTime.parse(o.endDateTimeUtc)
                          .millisecondsSinceEpoch -
                      DateTime.parse(o.startDateTimeUtc)
                          .millisecondsSinceEpoch) /
                  3600000.0,
            )
        ],
        weeklyThreshold: 40,
      );
      expect(fromHours, fromOccurrences);
      expect(fromHours['c'], closeTo(2, 1e-9)); // LIFO -> last shift
      expect(fromHours['a'], closeTo(0, 1e-9));
      expect(fromHours['b'], closeTo(0, 1e-9));
    });

    test('allocateWeeklyOvertimeHours: below threshold allocates nothing', () {
      final alloc = allocateWeeklyOvertimeHours(
        shifts: const [
          (id: 'm', shiftDate: '2026-09-07', hours: 8),
          (id: 'w', shiftDate: '2026-09-09', hours: 8),
        ],
        weeklyThreshold: 40,
      );
      expect(alloc.values.every((v) => v == 0), isTrue);
    });

    test('allocateWeeklyOvertimeHours: full-week absorption caps at shift length',
        () {
      // 14 + 14 + 14 + 1 = 43h vs 40h -> 3h OT. Last shift (1h) absorbs 1h,
      // overflow rolls to the previous shift (2h) — same LIFO edge as the
      // occurrence-based unit test, on the decoupled core.
      final alloc = allocateWeeklyOvertimeHours(
        shifts: const [
          (id: 's1', shiftDate: '2026-09-07', hours: 14),
          (id: 's2', shiftDate: '2026-09-08', hours: 14),
          (id: 's3', shiftDate: '2026-09-09', hours: 14),
          (id: 's4', shiftDate: '2026-09-10', hours: 1),
        ],
        weeklyThreshold: 40,
      );
      expect(alloc['s1'], closeTo(0, 1e-9));
      expect(alloc['s2'], closeTo(0, 1e-9));
      expect(alloc['s3'], closeTo(2, 1e-9));
      expect(alloc['s4'], closeTo(1, 1e-9));
    });

    test('LIFO allocation rolls overflow to the previous shift (plan2 §5.7)', () {
      // 14 + 14 + 14 + 1 = 43h, threshold 40h -> 3h OT.
      // Last shift (1h) absorbs 1h; the previous one absorbs the remaining 2h.
      ShiftOccurrence occ(String id, String date, double hours) =>
          ShiftOccurrence(
            id: id,
            patternId: 'p',
            shiftDate: date,
            templateId: 't',
            startDateTimeUtc: '${date}T00:00:00.000Z',
            endDateTimeUtc: DateTime.fromMillisecondsSinceEpoch(
                    DateTime.parse('${date}T00:00:00.000Z')
                            .millisecondsSinceEpoch +
                        (hours * 3600000).round(),
                    isUtc: true)
                .toIso8601String(),
            timezone: 'UTC',
            source: OccurrenceSource.baseline,
          );
      final shifts = [
        occ('s1', '2026-09-07', 14),
        occ('s2', '2026-09-08', 14),
        occ('s3', '2026-09-09', 14),
        occ('s4', '2026-09-10', 1),
      ];
      final alloc = allocateWeeklyOvertime(
          shifts: shifts, weeklyThreshold: 40);
      expect(alloc['s1'], closeTo(0, 1e-9));
      expect(alloc['s2'], closeTo(0, 1e-9));
      expect(alloc['s3'], closeTo(2, 1e-9));
      expect(alloc['s4'], closeTo(1, 1e-9));
    });

    test('assigned WEEK share composes with SHIFT rule via MAX (no underpay)', () {
      // CA-style: SHIFT >8h and WEEK >40h. Real multi-shift week — this 10h
      // shift got a 1h LIFO share of the week's 41h. Its own daily OT is 2h.
      // Correct: max(2 daily, 1 assigned) = 2h @1.5 — never the assigned 1h
      // alone (old bug: replaced daily OT, underpaid $17.50 on this shift).
      final bd = calculatePayBreakdown(
        input: const PayInput(
          shiftHours: 10,
          weeklyHours: 41,
          assignedOvertimeHours: 1,
          assignedMultiplier: 1.5,
        ),
        rule: ruleOf(otRules: [
          OvertimeRule(
              thresholdHours: 8,
              period: OvertimePeriod.shift,
              multiplier: 1.5),
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ]),
      );
      expect(bd.overtimeHours, closeTo(2, 1e-9));
      expect(bd.overtimePay, closeTo(105, 0.005));
      expect(bd.regularPay, closeTo(280, 0.005)); // 8h x $35
      expect(bd.total, closeTo(385, 0.005));
    });

    test('assigned=0 does not resurrect the WEEK rule on other shifts', () {
      // WEEK-only rule, real multi-shift week: this 10h shift absorbed none of
      // the week's overage (LIFO put it on a later shift). weeklyHours=42 must
      // NOT re-attribute 2h here — no double-count across the week.
      final bd = calculatePayBreakdown(
        input: const PayInput(
          shiftHours: 10,
          weeklyHours: 42,
          assignedOvertimeHours: 0,
          assignedMultiplier: 1.5,
        ),
        rule: ruleOf(otRules: [
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ]),
      );
      expect(bd.overtimeHours, closeTo(0, 1e-9));
      expect(bd.regularPay, closeTo(350, 0.005)); // 10h x $35, all regular
      expect(bd.total, closeTo(350, 0.005));
    });

    test('never double-counts overtime: total == regular + diffs + OT', () {
      final bd = calculatePayBreakdown(
        input: const PayInput(
          shiftHours: 12,
          weeklyHours: 44,
          isNightShift: true,
        ),
        rule: ruleOf(
          diffs: const [
            PayDifferential(
              type: DifferentialType.night,
              mode: DifferentialMode.percent,
              value: 10,
            ),
          ],
          otRules: [
            OvertimeRule(
                thresholdHours: 8,
                period: OvertimePeriod.shift,
                multiplier: 1.5),
            OvertimeRule(
                thresholdHours: 40,
                period: OvertimePeriod.week,
                multiplier: 1.5),
          ],
        ),
      );
      final diffSum = bd.differentialPay.values.fold(0.0, (s, v) => s + v);
      expect(bd.total,
          closeTo(bd.regularPay + diffSum + bd.overtimePay, 1e-6));
    });
  });
}
