// plan_payrule_version_ux.md §7.3 — UI test: the editor must NEVER surface
// the raw Gate A §A6 / persistence error text. Changing the rate and saving
// (same From date, same id) now transparently mints a new version: success
// copy, no technical leak, dialog closes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/time/time_engine.dart'
    show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/pay/pay_rule_edit_dialog.dart';

const _tz = 'UTC';

String _todayIso() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

void main() {
  setUpAll(initializeTimezoneDatabase);

  testWidgets('edited rate + Save → success, no A6/Gate text, new version '
      'created behind the scenes', (tester) async {
    final db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    final service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      pay: PayRuleRepository(db, patterns),
    );
    final jobId = service.createJob(name: 'Hospital', timezone: _tz);
    // Seed a first version the dialog will treat as "existing".
    service.savePayRuleFromEditor(
      rule: PayRule(
        id: 'seed-1',
        jobId: jobId,
        baseHourlyRate: 25,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: _todayIso(),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) =>
                    PayRuleEditDialog(service: service, jobId: jobId),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Change the rate on the SAME From date (the old failure shape: raw A6
    // StateError surfaced here).
    await tester.enterText(find.byKey(const ValueKey('pay-base')), '31.5');
    await tester.tap(find.byKey(const ValueKey('pay-save')));
    await tester.pumpAndSettle();

    // Dialog closed; no technical text anywhere.
    expect(find.textContaining('Gate A'), findsNothing);
    expect(find.textContaining('DIFFERENT payload'), findsNothing);
    expect(find.textContaining('persistence'), findsNothing);
    expect(find.byType(PayRuleEditDialog), findsNothing);
    expect(find.textContaining('Applies from'), findsOneWidget);

    // Two versions persisted; the old rate is untouched (history intact).
    final rules = service.payRules(jobId);
    expect(rules.length, 2);
    expect(rules.where((r) => r.id == 'seed-1').single.baseHourlyRate, 25);
    expect(rules.firstWhere((r) => r.baseHourlyRate == 31.5).effectiveFrom,
        _todayIso());
  });

  testWidgets('invalid From date → one-line user-facing error, no write, '
      'no crash', (tester) async {
    final db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    final service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      pay: PayRuleRepository(db, patterns),
    );
    final jobId = service.createJob(name: 'Clinic', timezone: _tz);
    final pastDate = '2020-01-01';
    service.savePayRuleFromEditor(
      rule: PayRule(
        id: 'seed-2',
        jobId: jobId,
        baseHourlyRate: 20,
        differentials: const [],
        overtimeRules: const [],
        effectiveFrom: pastDate,
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) =>
                    PayRuleEditDialog(service: service, jobId: jobId),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The dialog prefilled From = 2020-01-01 (the seed's effectiveFrom).
    // Change the rate → changed payload with From BEFORE today → the floor
    // validation fires with honest copy.
    await tester.enterText(find.byKey(const ValueKey('pay-base')), '28');
    await tester.tap(find.byKey(const ValueKey('pay-save')));
    await tester.pump();

    expect(find.textContaining('Choose a From date on or after'),
        findsOneWidget);
    expect(find.textContaining('Gate A'), findsNothing);
    expect(find.byType(PayRuleEditDialog), findsOneWidget,
        reason: 'dialog stays open on validation error');
    expect(service.payRules(jobId).length, 1,
        reason: 'nothing written');
  });
}
