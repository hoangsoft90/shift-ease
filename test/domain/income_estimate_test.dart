// =============================================================================
// Gate C B2 — income estimate (domain level, real SQLite).
//
//   1. WEEK-only OT rule: Mon/Wed/Fri 3×14h @ $35, 40h/week ×1.5 → $1505 —
//      the exact number the DB/pattern/import money integrations pin (one
//      price across every seam).
//   2. Base + night 20% + weekend 50% differentials compose on regular hours.
//   3. Missing rule / multi-version week → UNAVAILABLE with an explicit
//      reason — never a guessed number (D-C6).
// =============================================================================

import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/domain/income_estimate.dart';

void main() {
  tz.initializeTimeZones();

  ShiftTemplate tpl(String id, String start, String end) => ShiftTemplate(
        id: id,
        jobId: 'job-1',
        name: id,
        code: id,
        color: '#3366FF',
        startTime: start,
        endTime: end,
      );

  (ScheduleService, Database) harness() {
    final db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    final service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      pay: PayRuleRepository(db, patterns),
    );
    return (service, db);
  }

  group('Gate C B2 — income estimate', () {
    test('WEEK-only OT rule: 3x14h @ \$35 with 40h/week x1.5 = \$1505', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'America/New_York');
      service.saveTemplate(jobId: 'job-1', template: tpl('st14', '07:00', '21:00'));
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-w',
          jobId: 'job-1',
          name: 'Mon/Wed/Fri 14h',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: ['st14', null, 'st14', null, 'st14', null, null],
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-w',
        jobId: 'job-1',
        baseHourlyRate: 35,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
        ],
        effectiveFrom: '2026-01-01',
      ));

      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-13',
      );
      expect(est.available, isTrue, reason: est.unavailableReason);
      expect(est.hoursWorked, closeTo(42.0, 1e-9));
      expect(est.total, closeTo(1505.0, 1e-9));
      expect(est.regularPay, closeTo(1400.0, 1e-9)); // 40h x $35
      expect(est.overtimePay, closeTo(105.0, 1e-9)); // 2h x $52.5
      // Every amount ships with the estimate label.
      expect(WeekIncomeEstimate.disclaimer, contains('Ước tính'));
      db.close();
    });

    test('night + weekend differentials compose on regular hours only', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'UTC');
      service.saveTemplate(jobId: 'job-1', template: tpl('n', '19:00', '07:00+1'));
      // Anchor Monday 2026-10-26, slots 5-6 = Saturday 10-31 + Sunday 11-01
      // 19:00-07:00 = 12h each (night + weekend).
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-we',
          jobId: 'job-1',
          name: 'Weekend nights',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: [null, null, null, null, null, 'n', 'n'],
          anchorDate: '2026-10-26', // Monday
          defaultTimezone: 'UTC',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-nw',
        jobId: 'job-1',
        baseHourlyRate: 20,
        differentials: const [
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 20,
          ),
          PayDifferential(
            type: DifferentialType.weekend,
            mode: DifferentialMode.percent,
            value: 50,
          ),
        ],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));

      // Week Mon 2026-10-26..Sun 2026-11-01 → Sat 10-31 + Sun 11-01 nights.
      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-10-26',
        rangeEnd: '2026-11-01',
      );
      expect(est.available, isTrue, reason: est.unavailableReason);
      expect(est.hoursWorked, closeTo(24.0, 1e-9));
      // Regular 24h x 20 = 480; night 20% -> 96; weekend 50% -> 240.
      expect(est.regularPay, closeTo(480.0, 1e-9));
      expect(est.differentialPay, closeTo(336.0, 1e-9));
      expect(est.total, closeTo(816.0, 1e-9));
      expect(est.overtimePay, closeTo(0.0, 1e-9));
      db.close();
    });

    test('no active pay rule -> UNAVAILABLE with reason (never guessed)', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'UTC');
      service.saveTemplate(jobId: 'job-1', template: tpl('d', '07:00', '19:00'));
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-nr',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['d'],
          anchorDate: '2026-09-07',
          defaultTimezone: 'UTC',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      // No pay rule saved at all.
      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-08',
      );
      expect(est.available, isFalse);
      expect(est.unavailableReason, contains('không đoán số'));
      expect(est.total, 0);
      db.close();
    });
  });

  group('RC B1 — estimator parity with the money engine', () {
    test('PAY-013 golden: 15:00-03:00+1 shift vs window 22:00-06:00 → 5h '
        'window differential', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'America/New_York');
      service.saveTemplate(jobId: 'job-1', template: tpl('n', '15:00', '03:00+1'));
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-w13',
          jobId: 'job-1',
          name: 'Window night',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          // one shift on the anchor Monday, six OFF days
          sequence: ['n', null, null, null, null, null, null],
          anchorDate: '2026-09-07',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-p13',
        jobId: 'job-1',
        baseHourlyRate: 20,
        differentials: const [
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 50,
            scope: DifferentialScope.hoursInWindow,
            window: DifferentialWindow(startLocal: '22:00', endLocal: '06:00'),
          ),
        ],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));

      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-13',
      );
      expect(est.available, isTrue, reason: est.unavailableReason);
      expect(est.hoursWorked, closeTo(12.0, 1e-9));
      // 22:00→03:00 = 5h overlap: 5h x $20 x 50% = $50.
      expect(est.differentialPay, closeTo(50.0, 1e-9),
          reason: 'PAY-013: window overlap on the shift\'s own wall clock');
      expect(est.regularPay, closeTo(240.0, 1e-9)); // 12h x $20
      expect(est.total, closeTo(290.0, 1e-9));
      db.close();
    });

    test('overnight window golden: 19:00-07:00+1 vs 22:00-06:00 → 8h '
        'differential', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'UTC');
      service.saveTemplate(jobId: 'job-1', template: tpl('n8', '19:00', '07:00+1'));
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-w8',
          jobId: 'job-1',
          name: 'Overnight',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 7,
          sequence: ['n8', null, null, null, null, null, null],
          anchorDate: '2026-09-07',
          defaultTimezone: 'UTC',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-p8',
        jobId: 'job-1',
        baseHourlyRate: 20,
        differentials: const [
          PayDifferential(
            type: DifferentialType.night,
            mode: DifferentialMode.percent,
            value: 50,
            scope: DifferentialScope.hoursInWindow,
            window: DifferentialWindow(startLocal: '22:00', endLocal: '06:00'),
          ),
        ],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));

      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-09-07',
        rangeEnd: '2026-09-13',
      );
      expect(est.available, isTrue, reason: est.unavailableReason);
      // 22:00→06:00 fully inside 19:00→07:00+1 = 8h overlap.
      expect(est.differentialPay, closeTo(80.0, 1e-9));
      expect(est.total, closeTo(320.0, 1e-9));
      db.close();
    });

    test('DST spring-forward week prices from resolved UTC (shift spans the '
        'gap: 01:00-09:00 on 03-08 = 7h not 8h)', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'America/New_York');
      service.saveTemplate(jobId: 'job-1', template: tpl('dst', '01:00', '09:00'));
      // Week Mon 2026-03-02..Sun 2026-03-08 — US springs forward 03-08
      // 02:00->03:00; a 01:00-09:00 shift that day LOSES one hour (7h).
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-dst',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['dst'],
          anchorDate: '2026-03-02',
          defaultTimezone: 'America/New_York',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-dst',
        jobId: 'job-1',
        baseHourlyRate: 10,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));

      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-03-02',
        rangeEnd: '2026-03-08',
      );
      expect(est.available, isTrue, reason: est.unavailableReason);
      // 6 normal days x 8h + spring-forward Sunday 7h = 55h (INVARIANT-002).
      expect(est.hoursWorked, closeTo(55.0, 1e-9),
          reason: 'DST hours must come from resolved UTC instants');
      expect(est.total, closeTo(550.0, 1e-9));
      db.close();
    });
  });

  group('RC B2 — per-occurrence PayRule resolution', () {
    test('range spanning TWO versions with a WEEK OT scheme → UNAVAILABLE '
        '(weekly overtime not provable across versions)', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'UTC');
      service.saveTemplate(jobId: 'job-1', template: tpl('d', '07:00', '19:00'));
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-b2',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['d'],
          anchorDate: '2026-08-31', // Monday
          defaultTimezone: 'UTC',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-b2-v1',
        jobId: 'job-1',
        baseHourlyRate: 20,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
        ],
        effectiveFrom: '2026-01-01',
        effectiveUntil: '2026-09-02',
      ));
      service.savePayRule(PayRule(
        id: 'rule-b2-v2',
        jobId: 'job-1',
        baseHourlyRate: 25,
        differentials: const [],
        overtimeRules: const [
          OvertimeRule(
              thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
        ],
        effectiveFrom: '2026-09-03',
      ));

      // Mon 08-31 .. Sun 09-06 spans v1 (Mon-Wed) and v2 (Thu-Sun).
      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-08-31',
        rangeEnd: '2026-09-06',
      );
      expect(est.available, isFalse);
      expect(est.unavailableReason,
          contains('weekly overtime cannot be determined across multiple '
              'pay-rule versions'),
          reason: 'B2: never guess a weekly allocation across versions');
      expect(est.total, 0);
      db.close();
    });

    test('multi-version range WITHOUT a WEEK scheme prices per occurrence '
        '(each shift under its own rule)', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'UTC');
      service.saveTemplate(jobId: 'job-1', template: tpl('d', '07:00', '19:00'));
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-b2b',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['d'],
          anchorDate: '2026-08-31',
          defaultTimezone: 'UTC',
          effectiveFrom: '2026-01-01',
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-b2b-v1',
        jobId: 'job-1',
        baseHourlyRate: 20,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
        effectiveUntil: '2026-09-02',
      ));
      service.savePayRule(PayRule(
        id: 'rule-b2b-v2',
        jobId: 'job-1',
        baseHourlyRate: 25,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-09-03',
      ));

      final est = service.estimateIncome(
        jobId: 'job-1',
        rangeStart: '2026-08-31',
        rangeEnd: '2026-09-06',
      );
      expect(est.available, isTrue, reason: est.unavailableReason);
      expect(est.hoursWorked, closeTo(84.0, 1e-9));
      // 3 days (Mon-Wed) at $20 + 4 days (Thu-Sun) at $25, 12h each.
      expect(est.regularPay, closeTo(3 * 12 * 20 + 4 * 12 * 25, 1e-9));
      expect(est.total,
          closeTo(3 * 12 * 20 + 4 * 12 * 25, 1e-9));
      db.close();
    });
  });

  group('RC B6 — income impact preview (persist:false)', () {
    String mondayIso() {
      final now = DateTime.now();
      final mon = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));
      return '${mon.year.toString().padLeft(4, '0')}-'
          '${mon.month.toString().padLeft(2, '0')}-'
          '${mon.day.toString().padLeft(2, '0')}';
    }

    test('estimateIncomeImpact prices before/after/delta for a DELETE and '
        'goes UNAVAILABLE when a leg cannot price', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'UTC');
      service.saveTemplate(jobId: 'job-1', template: tpl('d', '07:00', '19:00'));
      final from = mondayIso();
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-imp',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['d'],
          anchorDate: from,
          defaultTimezone: 'UTC',
          effectiveFrom: from,
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-imp',
        jobId: 'job-1',
        baseHourlyRate: 20,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: from,
      ));

      final week = service.currentWeekShifts('job-1');
      expect(week, hasLength(7));
      final monday = week.firstWhere((o) => o.shiftDate == from);
      final impact = service.estimateIncomeImpact(
        jobId: 'job-1',
        current: week,
        prospective: [
          for (final o in week)
            if (o.id != monday.id) o,
        ],
      );
      expect(impact.available, isTrue, reason: impact.unavailableReason);
      expect(impact.before, closeTo(1680.0, 1e-9)); // 84h x $20
      expect(impact.after, closeTo(1440.0, 1e-9)); // 72h x $20
      expect(impact.delta, closeTo(-240.0, 1e-9));
      db.close();

      // No rule on the job → both legs UNAVAILABLE with the specific reason.
      final (service2, db2) = harness();
      service2.createJob(name: 'H', timezone: 'UTC');
      service2.saveTemplate(jobId: 'job-1', template: tpl('d', '07:00', '19:00'));
      service2.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-imp2',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['d'],
          anchorDate: from,
          defaultTimezone: 'UTC',
          effectiveFrom: from,
        ),
        templates: service2.templates('job-1'),
      );
      final w2 = service2.currentWeekShifts('job-1');
      final impact2 = service2.estimateIncomeImpact(
        jobId: 'job-1',
        current: w2,
        prospective: w2.sublist(1),
      );
      expect(impact2.available, isFalse);
      expect(impact2.unavailableReason, contains('không đoán số'));
      db2.close();
    });

    test('estimateReversionImpact: overrides on the changed days → '
        'UNAVAILABLE; a clean re-version prices before/after', () {
      final (service, db) = harness();
      service.createJob(name: 'H', timezone: 'UTC');
      service.saveTemplate(jobId: 'job-1', template: tpl('d', '07:00', '19:00'));
      final from = mondayIso();
      service.saveNewPattern(
        pattern: ShiftPattern(
          id: 'pat-rev',
          jobId: 'job-1',
          name: 'Daily',
          type: 'FIXED_CYCLE',
          cycleLengthDays: 1,
          sequence: ['d'],
          anchorDate: from,
          defaultTimezone: 'UTC',
          effectiveFrom: from,
        ),
        templates: service.templates('job-1'),
      );
      service.savePayRule(PayRule(
        id: 'rule-rev',
        jobId: 'job-1',
        baseHourlyRate: 20,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: from,
      ));

      final next = ShiftPattern(
        id: 'pat-rev-v2',
        jobId: 'job-1',
        name: 'Rota v2',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 4,
        sequence: [service.templates('job-1').single.id, null, null, null],
        anchorDate: from,
        defaultTimezone: 'UTC',
        effectiveFrom: from, // re-version effective tomorrow in the real flow
      );

      // Clean: no overrides/imports on the changed days → available.
      final clean = service.estimateReversionImpact(
          jobId: 'job-1', nextVersion: next);
      expect(clean.available, isTrue, reason: clean.unavailableReason);
      expect(clean.before, closeTo(1680.0, 1e-9));
      expect(clean.after, lessThan(clean.before),
          reason: 'a 1-on/3-off version replaces 7 daily shifts');

      // Now apply an UPDATE override on Friday → the changed days are no
      // longer pure baseline → the preview must refuse (never silently drop).
      final week = service.currentWeekShifts('job-1');
      final fri = week.firstWhere((o) => o.shiftDate ==
          _iso(DateTime.parse(from).add(const Duration(days: 4))));
      service.applyOverride(
        Override(
          id: service.newOverrideId(fri.id),
          occurrenceId: fri.id,
          operation: OverrideOperation.update,
          updatePayload: const UpdatePayload(startTime: '08:00', endTime: '20:00'),
          createdAt: ScheduleService.nowIso(),
        ),
        jobId: 'job-1',
      );
      final guarded = service.estimateReversionImpact(
          jobId: 'job-1', nextVersion: next);
      expect(guarded.available, isFalse);
      expect(guarded.unavailableReason,
          contains('Overrides or imported rows exist'),
          reason: 'B6: never silently drop an override in a preview');
      db.close();
    });
  });

  group('P7.1 M1 — estimateRosterDiffImpact never drops unresolvable rows', () {
    // P7.1 (M1): a prospective row that fails to resolve (DST spring gap,
    // malformed times) must turn the WHOLE preview UNAVAILABLE naming the
    // row — never a silently reduced "After" total.
    const validMon = (date: '2026-03-07', start: '07:00', end: '15:00');
    const validWed = (date: '2026-03-09', start: '07:00', end: '15:00');
    // 02:00 does not exist on 2026-03-08 (US spring forward).
    const dstGapRow = (date: '2026-03-08', start: '02:00', end: '10:00');
    const offDay = (date: '2026-03-08', start: null, end: null); // OFF day

    (ScheduleService, Database, String) diffHarness() {
      final (service, db) = harness();
      final jobId = service.createJob(name: 'DST', timezone: 'America/New_York');
      service.savePayRule(PayRule(
        jobId: jobId,
        id: 'rule-m1',
        baseHourlyRate: 10,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: '2026-01-01',
      ));
      return (service, db, jobId);
    }

    test('valid rows only (incl. a legitimate OFF day) → AVAILABLE', () {
      final (service, db, jobId) = diffHarness();
      final impact = service.estimateRosterDiffImpact(
        jobId: jobId,
        from: '2026-03-02',
        to: '2026-03-08',
        prospective: [validMon, offDay, validWed],
      );
      expect(impact.available, isTrue, reason: impact.unavailableReason);
      expect(impact.before, closeTo(0.0, 1e-9));
      expect(impact.after, closeTo(160.0, 1e-9)); // 16h x $10
      expect(impact.delta, closeTo(160.0, 1e-9));
      db.close();
    });

    test('one DST-gap row → UNAVAILABLE naming the row (no optimistic total)',
        () {
      final (service, db, jobId) = diffHarness();
      final impact = service.estimateRosterDiffImpact(
        jobId: jobId,
        from: '2026-03-02',
        to: '2026-03-08',
        prospective: [validMon, dstGapRow],
      );
      expect(impact.available, isFalse);
      expect(impact.unavailableReason, contains('After:'));
      expect(impact.unavailableReason, contains('2026-03-08'));
      expect(impact.unavailableReason,
          contains('could not be resolved'));
      db.close();
    });

    test('mixed valid + unresolvable rows → UNAVAILABLE (never partial)', () {
      final (service, db, jobId) = diffHarness();
      final impact = service.estimateRosterDiffImpact(
        jobId: jobId,
        from: '2026-03-02',
        to: '2026-03-08',
        prospective: [validMon, validWed, dstGapRow],
      );
      expect(impact.available, isFalse);
      expect(impact.unavailableReason, contains('2026-03-08'));
      db.close();
    });
  });
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
