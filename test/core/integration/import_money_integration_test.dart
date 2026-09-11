// =============================================================================
// Import Pipeline -> Money Engine integration (the pay seam).
// =============================================================================
//
// A pasted roster becomes COMMITTED shifts (import engine, UTC via core/time),
// then a work-week income estimate (money engine: active-rule lookup, LIFO
// weekly allocation, Method B). No hand-fed hours: durations come from the
// committed UTC instants (INVARIANT-002); templates are only consulted by the
// import suggestion step.
//
// Calendar layer stand-in: the persistence/UI gate does not exist yet, so the
// seam helpers here (durationOf / priceCommittedWeek) are exactly what that
// layer must do — this test pins the contract so the future layer can be
// built against verified behavior. No pattern types are fabricated: WEEK
// allocation runs on money's decoupled hours core
// (allocateWeeklyOvertimeHours) fed straight from the import engine's
// CommittedShift output.
//
// Arithmetic of every scenario is closed-form and independently checkable.
// =============================================================================

import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:shiftease/core/import/import_types.dart';
import 'package:shiftease/core/import/import_engine.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/money/money_engine.dart';

void main() {
  tz.initializeTimeZones();

  // ---------------------------------------------------------------------------
  // Seam helpers (the future calendar layer's contract, pinned by this test).
  // ---------------------------------------------------------------------------

  /// A 14h day template the import suggestion step can match.
  const TemplateSpec day14 = TemplateSpec(
      id: 'tpl-day', name: 'Day', startTime: '07:00', endTime: '21:00');

  /// Roster for Mon 2026-09-07 / Wed 09 / Fri 11, each 07:00-21:00 (14h).
  const rosterSepWeek =
      'Sep 07 Day 07:00-21:00\nSep 09 Day 07:00-21:00\nSep 11 Day 07:00-21:00';

  /// Import -> review (bulk accept HIGH) -> COMMIT. Returns the committed
  /// UTC-resolved shifts (INVARIANT-004: review and commit are explicit).
  List<CommittedShift> importCommittedShifts(
    String rosterText, {
    required String referenceDate,
    String timezone = 'America/New_York',
    String id = 'session',
  }) {
    final session = parseDocument(
      sourceType: ImportSourceType.pasteText,
      rawText: rosterText,
      templates: const [day14],
      referenceDate: referenceDate,
      timezone: timezone,
      id: id,
    );
    expect(session.state, ImportState.extracted);
    final result = commitImport(bulkAcceptHigh(session));
    expect(result.error, isNull, reason: result.error?.message);
    expect(result.session.state, ImportState.committed);
    expect(result.shifts.length, 3, reason: '3 roster days committed');
    return result.shifts;
  }

  /// Duration of a committed shift from its RESOLVED UTC instants.
  double durationOf(CommittedShift s) {
    final start =
        DateTime.parse(s.startDateTimeUtc).millisecondsSinceEpoch;
    final end = DateTime.parse(s.endDateTimeUtc).millisecondsSinceEpoch;
    return (end - start) / 3600000.0;
  }

  /// Price one committed week: LIFO WEEK allocation over its shifts, then one
  /// breakdown per shift under [ruleFor] (the PayRule ACTIVE on its date —
  /// INVARIANT-006). Returns occurrenceId -> pay plus the week total.
  (Map<String, double>, double) priceCommittedWeek(
    List<CommittedShift> week, {
    required PayRule Function(String date) ruleFor,
    double weeklyThreshold = 40,
  }) {
    final allocation = allocateWeeklyOvertimeHours(
      shifts: [
        for (final s in week)
          (id: s.occurrenceId, shiftDate: s.shiftDate, hours: durationOf(s))
      ],
      weeklyThreshold: weeklyThreshold,
    );
    final pays = <String, double>{};
    var total = 0.0;
    for (final s in week) {
      final hours = durationOf(s);
      final bd = calculatePayBreakdown(
        input: PayInput(
          shiftHours: hours,
          dailyHours: hours,
          assignedOvertimeHours: allocation[s.occurrenceId],
          assignedMultiplier: 1.5, // both scenarios use x1.5 WEEK rules
        ),
        rule: ruleFor(s.shiftDate),
      );
      pays[s.occurrenceId] = bd.total;
      total += bd.total;
    }
    return (pays, total);
  }

  PayRule weekOnlyRule({required double rate, String from = '2026-01-01'}) =>
      PayRule(
        id: 'rule-week',
        jobId: 'job-1',
        baseHourlyRate: rate,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ],
        effectiveFrom: from,
      );

  PayRule caRule({required double rate}) => PayRule(
        id: 'rule-ca',
        jobId: 'job-1',
        baseHourlyRate: rate,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 8,
              period: OvertimePeriod.shift,
              multiplier: 1.5),
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ],
        effectiveFrom: '2026-01-01',
      );

  group('Import -> Money integration', () {
    test('WEEK-only rule: imported 3x14h week pays \$1505 end-to-end', () {
      final shifts = importCommittedShifts(
        rosterSepWeek,
        referenceDate: '2026-09-01',
        id: 's-week',
      );

      // Durations from RESOLVED UTC (INVARIANT-002): 14h each.
      for (final s in shifts) {
        expect(durationOf(s), closeTo(14, 1e-9));
      }
      // NY September is EDT (UTC-4): 07:00 EDT -> 11:00Z; 21:00 EDT -> next
      // day 01:00Z — the import commit resolved real instants, not math.
      final mon = shifts.firstWhere((s) => s.shiftDate == '2026-09-07');
      expect(mon.startDateTimeUtc, '2026-09-07T11:00:00.000Z');
      expect(mon.endDateTimeUtc, '2026-09-08T01:00:00.000Z');

      final rule = weekOnlyRule(rate: 35);
      final (pays, total) = priceCommittedWeek(shifts, ruleFor: (_) => rule);

      // Closed-form cross-check (identical arithmetic to golden PAY-014):
      // 42h week - 40h threshold = 2h OT, LIFO onto the LAST shift (Fri).
      // Mon/Wed $490 each; Fri 12h reg + 2h OT = $525; week $1505.
      expect(total, closeTo(1505.00, 0.005));
      final fri = shifts.firstWhere((s) => s.shiftDate == '2026-09-11');
      expect(pays[fri.occurrenceId], closeTo(525.00, 0.005));
      expect(pays[mon.occurrenceId], closeTo(490.00, 0.005));
    });

    test('CA rule set over the imported week: daily OT composes -> \$1785', () {
      final shifts = importCommittedShifts(
        rosterSepWeek,
        referenceDate: '2026-09-01',
        id: 's-ca',
      );
      final rule = caRule(rate: 35);
      final (_, total) = priceCommittedWeek(shifts, ruleFor: (_) => rule);

      // Closed form: each 14h shift carries 6h of its own SHIFT-rule OT; the
      // week's 2h overage (LIFO -> Fri) never exceeds that, so per-shift OT =
      // max(6, share) = 6h -> 3 x ($280 + $315) = $1785. A replace-not-compose
      // bug would drop the daily OT and underpay the week.
      expect(total, closeTo(1785.00, 0.005));
    });

    test('INVARIANT-006: rule active at each date; history never re-priced',
        () {
      // Two imported weeks across a rate bump: Aug week under v1 ($35),
      // Sep week under v2 ($40). Both priced AFTER v2 exists.
      const augRoster = 'Aug 24 Day 07:00-21:00\n'
          'Aug 26 Day 07:00-21:00\n'
          'Aug 28 Day 07:00-21:00';
      final v1 = weekOnlyRule(rate: 35, from: '2026-01-01');
      final v2 = PayRule(
        id: 'rule-week-v2',
        jobId: 'job-1',
        baseHourlyRate: 40,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40,
              period: OvertimePeriod.week,
              multiplier: 1.5),
        ],
        effectiveFrom: '2026-09-01', // supersedes v1 mid-history
      );
      final allRules = [v1, v2];
      PayRule ruleFor(String date) =>
          getActivePayRule(rules: allRules, jobId: 'job-1', date: date)!;

      final augShifts = importCommittedShifts(
        augRoster,
        referenceDate: '2026-08-01',
        id: 's-aug',
      );
      final sepShifts = importCommittedShifts(
        rosterSepWeek,
        referenceDate: '2026-09-01',
        id: 's-sep',
      );

      // Active rule per shift date.
      expect(ruleFor('2026-08-24').id, 'rule-week');
      expect(ruleFor('2026-09-07').id, 'rule-week-v2');

      final (_, augTotal) = priceCommittedWeek(augShifts, ruleFor: ruleFor);
      final (_, sepTotal) = priceCommittedWeek(sepShifts, ruleFor: ruleFor);

      // Aug week stays $1505 (v1 @ $35) even though v2 ($40) now exists —
      // historical snapshots are immutable (INVARIANT-006).
      expect(augTotal, closeTo(1505.00, 0.005));
      // Sep week prices at v2: Mon/Wed 14h x $40 = $560 each; Fri
      // 12h x $40 + 2h x $60 = $600 -> $1720.
      expect(sepTotal, closeTo(1720.00, 0.005));
    });
  });
}
