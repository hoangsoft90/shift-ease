// =============================================================================
// Pay rule preset templates (RC plan §B5). A preset is a STARTING point that
// prefills the editor — the user reviews and edits the numbers and explicitly
// saves; nothing is saved implicitly. Presets are approximate market/collective
// ranges, NOT legal/payroll guarantees: the editor shows a disclaimer to
// verify against the employer/payroll policy.
// =============================================================================

import 'package:shiftease/core/money/money_types.dart';

/// One starting preset for the PayRule editor.
class PayPreset {
  final String name;
  final double baseRate;
  final double nightPercent;
  final double weekendPercent;
  final double otThresholdHours;
  final double otMultiplier;

  /// Short honesty note shown under the preset row.
  final String note;

  const PayPreset({
    required this.name,
    required this.baseRate,
    required this.nightPercent,
    required this.weekendPercent,
    required this.otThresholdHours,
    required this.otMultiplier,
    required this.note,
  });

  /// The PayRule this preset starts (id filled by the editor at save time).
  PayRule toRule({
    required String id,
    required String jobId,
    required String effectiveFrom,
  }) =>
      PayRule(
        id: id,
        jobId: jobId,
        baseHourlyRate: baseRate,
        differentials: [
          if (nightPercent > 0)
            PayDifferential(
              type: DifferentialType.night,
              mode: DifferentialMode.percent,
              value: nightPercent,
            ),
          if (weekendPercent > 0)
            PayDifferential(
              type: DifferentialType.weekend,
              mode: DifferentialMode.percent,
              value: weekendPercent,
            ),
        ],
        overtimeRules: [
          OvertimeRule(
            thresholdHours: otThresholdHours,
            period: OvertimePeriod.week,
            multiplier: otMultiplier,
          ),
        ],
        effectiveFrom: effectiveFrom,
      );

  /// Mandatory preset disclaimer (B5) — shown whenever a preset is applied.
  static const String disclaimer =
      'Verify this preset against your employer/payroll policy.';
}

/// The B5 library. Approximate starting numbers only — a preset is NEVER a
/// payroll/legal guarantee (see [PayPreset.disclaimer]).
const List<PayPreset> payPresets = [
  PayPreset(
    name: 'US-CA Nurse',
    baseRate: 55,
    nightPercent: 15,
    weekendPercent: 20,
    otThresholdHours: 40,
    otMultiplier: 1.5,
    note: 'Common California RN range — verify against your contract.',
  ),
  PayPreset(
    name: 'US-NY',
    baseRate: 45,
    nightPercent: 10,
    weekendPercent: 15,
    otThresholdHours: 40,
    otMultiplier: 1.5,
    note: 'Common New York hourly range — verify against your contract.',
  ),
  PayPreset(
    name: 'US-TX',
    baseRate: 38,
    nightPercent: 10,
    weekendPercent: 10,
    otThresholdHours: 40,
    otMultiplier: 1.5,
    note: 'Common Texas hourly range — verify against your contract.',
  ),
  PayPreset(
    name: 'UK NHS',
    baseRate: 14,
    nightPercent: 33,
    weekendPercent: 60,
    otThresholdHours: 37.5,
    otMultiplier: 1.25,
    note: 'NHS unsocial-hours style bands — verify against your AfC terms.',
  ),
  PayPreset(
    name: 'DE',
    baseRate: 20,
    nightPercent: 25,
    weekendPercent: 50,
    otThresholdHours: 40,
    otMultiplier: 1.25,
    note: 'Common German collective-agreement ranges — verify your Tarifvertrag.',
  ),
];