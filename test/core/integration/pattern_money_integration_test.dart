// =============================================================================
// Pattern Engine -> Money Engine integration (the pay-calculation seam).
// =============================================================================
//
// What this file proves end-to-end (no hand-fed numbers):
//   1. projectOccurrences renders a real multi-shift week from a pattern.
//   2. Each occurrence's DURATION is derived from its RESOLVED UTC instants
//      (INVARIANT-002) — the money engine never guesses from local times.
//   3. WEEK overtime is distributed LIFO via allocateWeeklyOvertime
//      (plan2 §5.7) across the occurrences OF THE SAME week.
//   4. Per-shift overtime = MAX(daily/SHIFT-rule OT, LIFO WEEK share) — the
//      composition that neither double-counts nor under-counts (Gate-1 fix).
//   5. Pay estimates snapshot onto occurrence COPIES (actualPayEstimate),
//      leaving the projected occurrences untouched (INVARIANT-001) for the
//      persistence layer to store — historical snapshots are immutable
//      (INVARIANT-006).
//
// Arithmetic of every scenario is independently verifiable below — nothing is
// asserted from the engine's own output without a closed-form cross-check.
// =============================================================================

import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/pattern/pattern_engine.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/money/money_engine.dart';

void main() {
  tz.initializeTimeZones();

  // A 14h day shift (07:00-21:00) — trivial in UTC: duration is exactly 14h.
  ShiftTemplate day14(String id) => ShiftTemplate(
        id: id,
        jobId: 'job-1',
        name: id,
        code: 'D',
        color: '#3366FF',
        startTime: '07:00',
        endTime: '21:00',
      );

  ShiftPattern threeShiftsWeek() {
    // Mon 2026-09-07 anchor; cycle Monday..Sunday: Mon/Wed/Fri work, off days
    // as null entries.
    return ShiftPattern(
      id: 'pat-3x14',
      jobId: 'job-1',
      name: 'Mon/Wed/Fri 14h',
      type: 'FIXED_CYCLE',
      cycleLengthDays: 7,
      sequence: ['st14', null, 'st14', null, 'st14', null, null],
      anchorDate: '2026-09-07', // Monday
      defaultTimezone: 'UTC',
      effectiveFrom: '2026-01-01',
    );
  }

  double durationHoursOf(ShiftOccurrence o) {
    final start =
        DateTime.parse(o.startDateTimeUtc).millisecondsSinceEpoch;
    final end = DateTime.parse(o.endDateTimeUtc).millisecondsSinceEpoch;
    return (end - start) / 3600000.0;
  }

  /// Price every shift of a rendered week: LIFO WEEK share + per-shift
  /// breakdown. Returns (pricedOccurrences, totalPay).
  (List<ShiftOccurrence>, double) priceWeek({
    required List<ShiftOccurrence> occurrences,
    required PayRule rule,
    double? assignedMultiplier,
  }) {
    // Week threshold from the rule's WEEK entries (all share one in our cases).
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
          assignedMultiplier: assignedMultiplier ?? weekRule.multiplier,
        ),
        rule: rule,
      );
      total += bd.total;
      // Snapshot the estimate onto a COPY — the projected occurrence is not
      // mutated (INVARIANT-001); the copy is what persistence stores.
      priced.add(o.copyWith(actualPayEstimate: bd.total));
    }
    return (priced, total);
  }

  group('Pattern -> Money integration', () {
    test('WEEK-only rule: 3x14h week pays \$1505 end-to-end (NY-style)', () {
      final result = projectOccurrences(
        pattern: threeShiftsWeek(),
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-13',
        templates: [day14('st14')],
      );
      expect(result.issues, isEmpty);
      expect(result.occurrences.length, 3);
      // Every occurrence has resolved UTC instants — nothing empty (P0-3/D1).
      for (final o in result.occurrences) {
        expect(o.startDateTimeUtc, isNotEmpty);
        expect(o.endDateTimeUtc, isNotEmpty);
        expect(durationHoursOf(o), closeTo(14, 1e-9));
      }
      // Real week total from UTC durations.
      final weekHours =
          result.occurrences.fold(0.0, (s, o) => s + durationHoursOf(o));
      expect(weekHours, closeTo(42, 1e-9));

      final rule = PayRule(
        id: 'rule-ny',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ],
        effectiveFrom: '2000-01-01',
      );

      final (priced, totalPay) =
          priceWeek(occurrences: result.occurrences, rule: rule);

      // Closed-form cross-check (identical to golden PAY-014 arithmetic):
      // 42h week - 40h threshold = 2h OT, all on the LAST shift (Fri, LIFO).
      // Mon/Wed: 14h x $35 = $490 each. Fri: 12h x $35 + 2h x $35 x 1.5.
      expect(totalPay, closeTo(1505.00, 0.005));
      final fri = priced.firstWhere((o) => o.shiftDate == '2026-09-11');
      final mon = priced.firstWhere((o) => o.shiftDate == '2026-09-07');
      expect(fri.actualPayEstimate, closeTo(525.00, 0.005));
      expect(mon.actualPayEstimate, closeTo(490.00, 0.005));

      // INVARIANT-001: originals untouched — only the copies carry estimates.
      for (final o in result.occurrences) {
        expect(o.actualPayEstimate, isNull);
      }
      expect(priced.length, result.occurrences.length);
    });

    test('CA rule set: daily OT composes with LIFO share via MAX -> \$1785', () {
      final result = projectOccurrences(
        pattern: threeShiftsWeek(),
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-13',
        templates: [day14('st14')],
      );
      expect(result.issues, isEmpty);

      final rule = PayRule(
        id: 'rule-ca',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [],
        overtimeRules: const [
          // California double-trigger: daily OT after 8h AND weekly after 40h.
          OvertimeRule(
              thresholdHours: 8,
              period: OvertimePeriod.shift,
              multiplier: 1.5),
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ],
        effectiveFrom: '2000-01-01',
      );

      final (priced, totalPay) =
          priceWeek(occurrences: result.occurrences, rule: rule);

      // Closed form: each 14h shift has 14-8 = 6h daily OT (hours 9-14). The
      // week's 42-40 = 2h weekly overage (LIFO -> Fri) never exceeds a
      // shift's own daily OT, so per-shift OT = max(6, share) = 6h.
      // Total: 3 x (8h x $35 + 6h x $35 x 1.5) = 3 x ($280 + $315) = $1785.
      // If daily OT were lost to the LIFO share (pre-fix), Fri would pay
      // 8h + max(...) differently and the week would come up short.
      expect(totalPay, closeTo(1785.00, 0.005));
      for (final o in priced) {
        expect(o.actualPayEstimate, closeTo(595.00, 0.005));
      }

      // And no shift can owe MORE than its own daily OT here: the LIFO share
      // for the absorbing (Fri) shift is 2h < its 6h daily OT, so 6h is right.
      // Re-run LIFO to double-check the allocation bookkeeping explicitly.
      final alloc = allocateWeeklyOvertime(
        shifts: result.occurrences,
        weeklyThreshold: 40,
      );
      final fri = result.occurrences.firstWhere((o) => o.shiftDate == '2026-09-11');
      expect(alloc[fri.id], closeTo(2, 1e-9)); // all 2h weekly OT on Fri
    });

    test('night window differential via template local times (22:00-06:00)', () {
      // One night-shift pattern in UTC: 22:00 -> 06:00 (overnight, +1 day).
      final pat = ShiftPattern(
        id: 'pat-night',
        jobId: 'job-1',
        name: 'Night',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 7,
        sequence: List.filled(7, 'st-night'),
        anchorDate: '2026-09-07',
        defaultTimezone: 'UTC',
        effectiveFrom: '2026-01-01',
      );
      final templates = [
        ShiftTemplate(
          id: 'st-night',
          jobId: 'job-1',
          name: 'Night',
          code: 'N',
          color: '#6633CC',
          startTime: '22:00',
          endTime: '06:00',
        ),
      ];
      final result = projectOccurrences(
        pattern: pat,
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-13',
        templates: templates,
      );
      expect(result.issues, isEmpty);
      expect(result.occurrences.length, 7);

      final rule = PayRule(
        id: 'rule-night',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 10,
            scope: DifferentialScope.hoursInWindow,
            window: DifferentialWindow(startLocal: '22:00', endLocal: '06:00'),
          ),
        ],
        overtimeRules: const [],
        effectiveFrom: '2000-01-01',
      );

      var totalPay = 0.0;
      for (final o in result.occurrences) {
        // Reconstruct local civil times from the occurrence's template — the
        // calendar layer's job at this seam (ShiftOccurrence stores UTC +
        // templateId; the template holds the local intent).
        final tmpl = templates.firstWhere((t) => t.id == o.templateId);
        final endMarker =
            tmpl.endTime.compareTo(tmpl.startTime) < 0 ? '+1' : '';
        final hours = durationHoursOf(o);
        expect(hours, closeTo(8, 1e-9)); // 22:00-06:00, 8h (UTC, no DST)

        final bd = calculatePayBreakdown(
          input: PayInput(
            shiftHours: hours,
            dailyHours: hours,
            shiftStartLocal: tmpl.startTime,
            shiftEndLocal: '${tmpl.endTime}$endMarker',
          ),
          rule: rule,
        );
        // Entire shift sits inside its own 22:00-06:00 night window: all 8h
        // get the 10% night differential on REGULAR hours (no OT in play).
        expect(bd.overtimeHours, closeTo(0, 1e-9));
        expect(bd.regularPay, closeTo(280.00, 0.005)); // 8h x $35
        expect(
          bd.differentialPay[DifferentialType.night],
          closeTo(28.00, 0.005), // 8h x $35 x 10%
        );
        expect(bd.total, closeTo(308.00, 0.005));
        totalPay += bd.total;
      }
      expect(totalPay, closeTo(2156.00, 0.005)); // 7 nights x $308
    });
  });
}
