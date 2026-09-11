// =============================================================================
// RC plan §B5 — pay rule preset template library.
//
//   Choose a preset (e.g. US-CA Nurse) → the editor PREFILLS the numbers as a
//   starting point → the user can review/edit → nothing is saved implicitly —
//   only the explicit 'Save rule' press persists. The verify-against-your-
//   policy disclaimer ships with every applied preset.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart' as dblib;
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/time/time_engine.dart' show initializeTimezoneDatabase;
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/pay/pay_presets.dart';
import 'package:shiftease/features/pay/pay_rule_edit_dialog.dart';

const _tz = 'UTC';

String _todayIso() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

void main() {
  setUpAll(initializeTimezoneDatabase);

  testWidgets('B5: choosing a preset prefills the editor (starting point); '
      'explicit Save persists it; disclaimer shown', (tester) async {
    final db = dblib.openInMemory();
    final patterns = PatternRepository(db);
    final service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
      db: db,
      pay: PayRuleRepository(db, patterns),
    );
    final jobId = service.createJob(name: 'Hospital', timezone: _tz);

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
    expect(find.text('Pay rule (estimate)'), findsOneWidget);

    // No rule is saved before the explicit save — nothing implicit (B5).
    expect(service.payRules(jobId), isEmpty);

    // Choose the US-CA Nurse preset.
    await tester.tap(find.byKey(const ValueKey('pay-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('US-CA Nurse').last);
    await tester.pumpAndSettle();

    // Prefilled as a starting point + mandatory disclaimer.
    final ca = payPresets.firstWhere((p) => p.name == 'US-CA Nurse');
    expect(find.text(ca.baseRate.toStringAsFixed(2)), findsOneWidget,
        reason: 'preset prefills the base rate');
    expect(find.text(PayPreset.disclaimer), findsOneWidget,
        reason: 'B5: verify-against-your-policy disclaimer ships with presets');

    // Explicit save persists the preset-derived rule.
    await tester.tap(find.byKey(const ValueKey('pay-save')));
    await tester.pumpAndSettle();
    final rules = service.payRules(jobId);
    expect(rules, hasLength(1),
        reason: 'B5: only the explicit Save press writes a rule');
    expect(rules.single.baseHourlyRate, ca.baseRate);
    expect(rules.single.differentials.map((d) => d.value),
        containsAll([ca.nightPercent, ca.weekendPercent]));
    expect(rules.single.overtimeRules.single.thresholdHours,
        ca.otThresholdHours);
    expect(rules.single.overtimeRules.single.multiplier, ca.otMultiplier);
    expect(rules.single.effectiveFrom, _todayIso());
    db.close();
  });
}