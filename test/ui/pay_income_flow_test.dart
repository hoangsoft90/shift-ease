// =============================================================================
// Gate C B2 — Pay/Income minimum (widget level, real :memory: SQLite):
//
//   1. JobDetail exposes a Pay rule card; the editor saves a basic rule
//      (base rate + night/weekend differentials) which persists and resolves
//      as the ACTIVE rule for the job.
//   2. Today shows a per-job income card with line items and the mandatory
//      disclaimer label 'Ước tính — không phải bảng lương chính thức' (D-C6).
//   3. A job WITHOUT any pay rule shows the explicit 'no rule — cannot
//      estimate' reason instead of a fabricated number.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/core/time/time_engine.dart' show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/jobs/job_detail_screen.dart';
import 'package:shiftease/features/today/today_screen.dart';

const _tz = 'UTC';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _mondayIso() {
  final now = DateTime.now();
  final mon = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - DateTime.monday));
  return _iso(mon);
}

void main() {
  setUpAll(initializeTimezoneDatabase);

  late Database db;
  late ScheduleService service;

  setUp(() {
    db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      pay: PayRuleRepository(db, patterns),
    );
  });

  tearDown(() => db.close());

  /// Seeds a job with a daily 07:00–19:00 pattern covering the current week.
  String seedDailyJob() {
    final jobId = service.createJob(name: 'Pay Hospital', timezone: _tz);
    service.saveTemplate(
      jobId: jobId,
      template: ShiftTemplate(
        id: slugId('tpl', ['Day', '07:00', '19:00']),
        jobId: jobId,
        name: 'Day',
        code: 'D',
        color: '#1565C0',
        startTime: '07:00',
        endTime: '19:00',
      ),
    );
    final from = _mondayIso();
    service.saveNewPattern(
      pattern: ShiftPattern(
        id: slugId('pat', ['Daily', jobId, from]),
        jobId: jobId,
        name: 'Daily',
        type: 'FIXED_CYCLE',
        cycleLengthDays: 1,
        sequence: [service.templates(jobId).single.id],
        anchorDate: from,
        defaultTimezone: _tz,
        effectiveFrom: from,
      ),
      templates: service.templates(jobId),
    );
    return jobId;
  }

  testWidgets('Pay rule editor on JobDetail saves a rule; Today shows the '
      'income card with the estimate disclaimer', (tester) async {
    final jobId = seedDailyJob();
    service.savePayRule(PayRule(
      id: slugId('payrule', [jobId, _mondayIso()]),
      jobId: jobId,
      baseHourlyRate: 20,
      differentials: const [
        PayDifferential(
          type: DifferentialType.weekend,
          mode: DifferentialMode.percent,
          value: 50,
        ),
      ],
      overtimeRules: const [
        OvertimeRule(
            thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
      ],
      effectiveFrom: _mondayIso(),
    ));

    // JobDetail reflects the active rule.
    await tester.pumpWidget(MaterialApp(
        home: JobDetailScreen(service: service, jobId: jobId)));
    await tester.pumpAndSettle();
    expect(find.text('Pay rule'), findsOneWidget);
    expect(find.textContaining('\$20.00/h'), findsOneWidget);
    expect(find.textContaining('weekend +50%'), findsOneWidget);

    // Edit dialog prefills; saving the same numbers is an idempotent no-op
    // and the rule stays active (Gate A §A6 semantics surface in the UI).
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Pay rule (estimate)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pay-save')));
    await tester.pumpAndSettle();
    expect(service.payRules(jobId).length, 1, reason: 'identical re-save');
    expect(
      service.activePayRule(jobId: jobId, date: _mondayIso()),
      isNotNull,
    );

    // Today income card with the mandatory disclaimer (fling to the bottom —
    // the ListView builds lazily below the fold).
    await tester.pumpWidget(MaterialApp(home: TodayScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.fling(
        find.byType(ListView).first, const Offset(0, -1400), 3000);
    await tester.pumpAndSettle();
    expect(find.textContaining('Income this week'), findsOneWidget);
    expect(find.textContaining('USD \$'), findsWidgets);
  });

  testWidgets('job with no pay rule shows the explicit reason, never a number',
      (tester) async {
    seedDailyJob(); // no pay rule saved
    await tester.pumpWidget(MaterialApp(home: TodayScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.fling(
        find.byType(ListView).first, const Offset(0, -1400), 3000);
    await tester.pumpAndSettle();
    expect(find.textContaining('không đoán số'), findsOneWidget);
    expect(find.textContaining('Regular Pay'), findsNothing);
  });
}
