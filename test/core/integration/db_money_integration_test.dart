// =============================================================================
// Persistence (SQLite) -> Money Engine integration (the snapshot seam).
// =============================================================================
//
// What this file proves end-to-end (no hand-fed numbers):
//   1. renderJobSchedule re-derives a real week from a PERSISTED pattern
//      (SQLite) through the pure engine, and the occurrences reload from the
//      DB with their resolved UTC instants intact (INVARIANT-002).
//   2. Durations come from those resolved UTC instants; WEEK overtime is
//      distributed LIFO across the week (plan2 §5.7); per-shift pay follows
//      Method B with the SHIFT/WEEK MAX composition (Gate-1 fix).
//   3. Pay estimates are committed through setPayEstimateSnapshot — the DB
//      enforces INVARIANT-006 (refuses to CHANGE an existing snapshot) and a
//      later re-render refreshes temporal fields but NEVER touches snapshots.
//   4. Active pay-rule resolution over the DB (activeRuleFor) matches the pure
//      engine's getActivePayRule over the same rows (INVARIANT-006 parity).
//
// Arithmetic of every scenario is closed-form and independently checkable —
// identical numbers to the pattern->money and import->money suites, so the
// three seams agree on one price.
// =============================================================================

import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/money/money_engine.dart';

void main() {
  tz.initializeTimeZones();

  // A 14h day shift (07:00-21:00). America/New_York: Sep/Aug are EDT (UTC-4)
  // with no DST transition, so duration is exactly 14h and 07:00 -> 11:00Z.
  ShiftTemplate day14(String id) => ShiftTemplate(
        id: id,
        jobId: 'job-1',
        name: id,
        code: 'D',
        color: '#3366FF',
        startTime: '07:00',
        endTime: '21:00',
      );

  /// Mon/Wed/Fri 14h pattern anchored on a Monday — renders 3 shifts/week.
  ShiftPattern threeShiftsWeek(String id) => ShiftPattern(
        id: id,
        jobId: 'job-1',
        name: 'Mon/Wed/Fri 14h',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: ['st14', null, 'st14', null, 'st14', null, null],
        anchorDate: '2026-09-07', // Monday
        defaultTimezone: 'America/New_York',
        effectiveFrom: '2026-01-01',
      );

  double durationHoursOf(ShiftOccurrence o) {
    final start = DateTime.parse(o.startDateTimeUtc).millisecondsSinceEpoch;
    final end = DateTime.parse(o.endDateTimeUtc).millisecondsSinceEpoch;
    return (end - start) / 3600000.0;
  }

  PayRule weekOnlyRule(String id, double rate,
          {String from = '2026-01-01'}) =>
      PayRule(
        id: id,
        jobId: 'job-1',
        baseHourlyRate: rate,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
        ],
        effectiveFrom: from,
      );

  PayRule caRule(String id, double rate) => PayRule(
        id: id,
        jobId: 'job-1',
        baseHourlyRate: rate,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 8, period: OvertimePeriod.shift, multiplier: 1.5),
          OvertimeRule(
              thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
        ],
        effectiveFrom: '2026-01-01',
      );

  /// Price every DB-reloaded occurrence of one week: LIFO WEEK share +
  /// per-shift breakdown under [rule], then commit each estimate through the
  /// repository's snapshot API. Returns (priced copy list, week total).
  (List<ShiftOccurrence>, double) priceAndSnapshotWeek({
    required ScheduleRepository sched,
    required List<ShiftOccurrence> occurrences,
    required PayRule rule,
    required String payRuleFrom,
  }) {
    final weekRule = rule.overtimeRules
        .where((r) => r.period == OvertimePeriod.week)
        .first;
    final allocation = allocateWeeklyOvertime(
      shifts: occurrences,
      weeklyThreshold: weekRule.thresholdHours,
    );
    final priced = <ShiftOccurrence>[];
    var total = 0.0;
    for (final o in occurrences) {
      final hours = durationHoursOf(o);
      final bd = calculatePayBreakdown(
        input: PayInput(
          shiftHours: hours,
          dailyHours: hours,
          assignedOvertimeHours: allocation[o.id],
          assignedMultiplier: weekRule.multiplier,
        ),
        rule: rule,
      );
      total += bd.total;
      sched.setPayEstimateSnapshot(
          occurrenceId: o.id, amount: bd.total, payRuleFrom: payRuleFrom);
      priced.add(o.copyWith(actualPayEstimate: bd.total));
    }
    return (priced, total);
  }

  group('DB -> Money integration', () {
    test('WEEK-only rule: rendered 3x14h week pays \$1505, snapshot survives '
        're-render', () {
      final db = dblib.openInMemory();
      final pat = PatternRepository(db);
      final sched = ScheduleRepository(db, pat);
      final pay = PayRuleRepository(db, pat);
      pat.savePattern(
          jobId: 'job-1', pattern: threeShiftsWeek('pat-db'), templates: [day14('st14')]);
      pay.savePayRule(rule: weekOnlyRule('rule-db', 35));

      final rendered = sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
      expect(rendered.issues, isEmpty);
      expect(rendered.occurrences.length, 3);

      // Reload from the DB — resolved UTC instants survive the round-trip.
      final week = sched.occurrencesInRange(
          patternId: 'pat-db', from: '2026-09-07', to: '2026-09-13');
      expect(week.length, 3);
      for (final o in week) {
        expect(o.startDateTimeUtc, isNotEmpty);
        expect(durationHoursOf(o), closeTo(14, 1e-9));
      }
      // NY/EDT: 07:00 -> 11:00Z (INVARIANT-002, resolved — not guessed).
      final mon = week.firstWhere((o) => o.shiftDate == '2026-09-07');
      expect(mon.startDateTimeUtc, '2026-09-07T11:00:00.000Z');

      // Active rule comes from the DB (INVARIANT-006 lookup).
      final rule = pay.activeRuleFor(jobId: 'job-1', date: '2026-09-07')!;
      expect(rule.baseHourlyRate, 35);

      final (_, total) = priceAndSnapshotWeek(
          sched: sched,
          occurrences: week,
          rule: rule,
          payRuleFrom: rule.effectiveFrom);
      // Closed form (identical to PAY-014 / pattern-money / import-money):
      // 42h - 40h = 2h OT LIFO onto Fri. Mon/Wed $490; Fri $525; week $1505.
      expect(total, closeTo(1505.00, 0.005));

      // Re-render (restart-equivalent) must NOT clobber the snapshots.
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
      final after = sched.occurrencesInRange(
          patternId: 'pat-db', from: '2026-09-07', to: '2026-09-13');
      final afterFri =
          after.firstWhere((o) => o.shiftDate == '2026-09-11');
      expect(afterFri.actualPayEstimate, closeTo(525.00, 0.005));
      expect(afterFri.payEstimateFrom, '2026-01-01');
      final afterMon =
          after.firstWhere((o) => o.shiftDate == '2026-09-07');
      expect(afterMon.actualPayEstimate, closeTo(490.00, 0.005));
      db.close();
    });

    test('CA rule over DB-rendered week: daily OT composes -> \$1785 '
        '(MAX, not replace)', () {
      final db = dblib.openInMemory();
      final pat = PatternRepository(db);
      final sched = ScheduleRepository(db, pat);
      final pay = PayRuleRepository(db, pat);
      pat.savePattern(
          jobId: 'job-1', pattern: threeShiftsWeek('pat-ca'), templates: [day14('st14')]);
      pay.savePayRule(rule: caRule('rule-ca', 35));

      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
      final week = sched.occurrencesInRange(
          patternId: 'pat-ca', from: '2026-09-07', to: '2026-09-13');
      final rule = pay.activeRuleFor(jobId: 'job-1', date: '2026-09-07')!;

      final (_, total) = priceAndSnapshotWeek(
          sched: sched,
          occurrences: week,
          rule: rule,
          payRuleFrom: rule.effectiveFrom);
      // Closed form: each 14h shift carries 6h of its own SHIFT-rule OT; the
      // week's 2h overage (LIFO -> Fri) never exceeds that, so per-shift OT =
      // max(6, share) = 6h -> 3 x ($280 + $315) = $1785.
      expect(total, closeTo(1785.00, 0.005));
      db.close();
    });

    test('INVARIANT-006: DB active-rule parity + snapshots never re-priced '
        'across a rate bump', () {
      final db = dblib.openInMemory();
      final pat = PatternRepository(db);
      final sched = ScheduleRepository(db, pat);
      final pay = PayRuleRepository(db, pat);
      pat.savePattern(
          jobId: 'job-1', pattern: threeShiftsWeek('pat-ver'), templates: [day14('st14')]);

      // v1 @ $35 from Jan; v2 @ $40 from Sep 1 (both persisted as separate
      // versioned rows — never a rewrite of the past).
      pay.savePayRule(rule: weekOnlyRule('rule-ver-v1', 35));
      pay.savePayRule(
          rule: weekOnlyRule('rule-ver-v2', 40, from: '2026-09-01'));

      // DB lookup per shift date == pure-engine lookup over the same rows.
      final allRules = pay.allRulesFor('job-1');
      expect(allRules.length, 2);
      final dbAug = pay.activeRuleFor(jobId: 'job-1', date: '2026-08-24')!;
      final dbSep = pay.activeRuleFor(jobId: 'job-1', date: '2026-09-07')!;
      final engineAug =
          getActivePayRule(rules: allRules, jobId: 'job-1', date: '2026-08-24')!;
      final engineSep =
          getActivePayRule(rules: allRules, jobId: 'job-1', date: '2026-09-07')!;
      expect(dbAug.baseHourlyRate, engineAug.baseHourlyRate);
      expect(dbSep.baseHourlyRate, engineSep.baseHourlyRate);
      expect(dbAug.baseHourlyRate, 35);
      expect(dbSep.baseHourlyRate, 40);

      // Render + price the Aug week under v1, then the Sep week under v2.
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-08-24', rangeEnd: '2026-08-30');
      final augWeek = sched.occurrencesInRange(
          patternId: 'pat-ver', from: '2026-08-24', to: '2026-08-30');
      final (_, augTotal) = priceAndSnapshotWeek(
          sched: sched,
          occurrences: augWeek,
          rule: dbAug,
          payRuleFrom: dbAug.effectiveFrom);
      expect(augTotal, closeTo(1505.00, 0.005)); // v1 @ $35

      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
      final sepWeek = sched.occurrencesInRange(
          patternId: 'pat-ver', from: '2026-09-07', to: '2026-09-13');
      final (_, sepTotal) = priceAndSnapshotWeek(
          sched: sched,
          occurrences: sepWeek,
          rule: dbSep,
          payRuleFrom: dbSep.effectiveFrom);
      // Sep at v2 @ $40: Mon/Wed $560 each; Fri 12h x $40 + 2h x $60 = $600.
      expect(sepTotal, closeTo(1720.00, 0.005));

      // Re-render BOTH weeks after v2 exists: Aug snapshots must stay at v1
      // prices (immutable — never re-priced by the newer version).
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-08-24', rangeEnd: '2026-08-30');
      sched.renderJobSchedule(
          jobId: 'job-1', rangeStart: '2026-09-07', rangeEnd: '2026-09-13');
      final augAfter = sched.occurrencesInRange(
          patternId: 'pat-ver', from: '2026-08-24', to: '2026-08-30');
      final sepAfter = sched.occurrencesInRange(
          patternId: 'pat-ver', from: '2026-09-07', to: '2026-09-13');
      for (final o in augAfter) {
        // Aug shifts stay v1-priced; the Fri (28th) keeps its LIFO 2h OT.
        final expected = o.shiftDate == '2026-08-28' ? 525.00 : 490.00;
        expect(o.actualPayEstimate, closeTo(expected, 0.005),
            reason: 'Aug shift ${o.shiftDate} must stay v1-priced');
        expect(o.payEstimateFrom, '2026-01-01');
      }
      final sepFri =
          sepAfter.firstWhere((o) => o.shiftDate == '2026-09-11');
      expect(sepFri.actualPayEstimate, closeTo(600.00, 0.005));
      expect(sepFri.payEstimateFrom, '2026-09-01');

      // Rewriting a snapshot to a different amount is REFUSED (the DB enforces
      // INVARIANT-006 — history is immutable, not just unused).
      expect(
          () => sched.setPayEstimateSnapshot(
              occurrenceId: sepFri.id, amount: 900.00, payRuleFrom: '2026-09-01'),
          throwsA(isA<ImmutableHistoryError>()));
      db.close();
    });
  });
}
