// =============================================================================
// ShiftEase Money Engine — Core Types
// =============================================================================
//
// ARCHITECTURAL INVARIANTS (plan1_final_v2.md §10 + plan2.md §5):
//
// INVARIANT-005: ShiftTemplate carries time/UI semantics only — NO pay
//   semantics. All money semantics live in PayRule, scoped by jobId, versioned
//   with VersionedEntity { effectiveFrom, effectiveUntil }.
//
// INVARIANT-006: Historical pay estimates are immutable snapshots; a new
//   PayRule version NEVER rewrites past earnings. Pay is computed from the
//   PayRule ACTIVE at the occurrence's date (getActivePayRule).
//
// Method B (regular + overtime separated, no double-counting):
//   regularHours = durationHours - overtimeHours; overtime is paid in full at
//   rate x multiplier on top of the regular hours — the overtime hours are
//   NOT paid twice (no (1 + multiplier)x for OT hours).
//
// Differential semantics (locked): differentials apply to REGULAR hours only,
//   never to overtime hours.
//
// =============================================================================

import 'package:shiftease/core/pattern/pattern_types.dart'
    show VersionedEntity;

/// Differential type — pluggable (plan1 D-series: no hard-coded fields).
enum DifferentialType {
  night,
  weekend,
  holiday,
  hazard,
  callback,
  custom;

  /// Case- and underscore-insensitive: "NIGHT" == "night".
  static DifferentialType fromName(String name) =>
      DifferentialType.values.firstWhere(
        (t) => _norm(t.name) == _norm(name),
        orElse: () => DifferentialType.custom,
      );
}

/// How a differential's rate is expressed.
enum DifferentialMode {
  percent,
  flat;

  static DifferentialMode fromName(String name) =>
      DifferentialMode.values.firstWhere(
        (m) => _norm(m.name) == _norm(name),
        orElse: () => DifferentialMode.flat,
      );
}

/// Which hours of the shift a differential applies to.
enum DifferentialScope {
  /// The differential applies whenever the shift itself qualifies
  /// (e.g. a night shift, a weekend shift, a holiday shift).
  allHoursInShift,

  /// Only the hours of the shift that fall inside a daily [window]
  /// (e.g. premium for hours between 22:00 and 06:00).
  hoursInWindow;

  /// "ALL_HOURS_IN_SHIFT" / "HOURS_IN_WINDOW" (JSON) <-> camelCase enum names.
  static DifferentialScope fromName(String name) =>
      DifferentialScope.values.firstWhere(
        (s) => _norm(s.name) == _norm(name),
        orElse: () => DifferentialScope.allHoursInShift,
      );
}

/// Overtime accumulation period.
enum OvertimePeriod {
  shift,
  day,
  week;

  static OvertimePeriod fromName(String name) =>
      OvertimePeriod.values.firstWhere(
        (p) => _norm(p.name) == _norm(name),
        orElse: () => OvertimePeriod.shift,
      );
}

String _norm(String s) => s.toUpperCase().replaceAll('_', '');

/// A daily recurring window used by [DifferentialScope.hoursInWindow].
/// Local wall-clock "HH:mm" times. When [endLocal] is before [startLocal]
/// the window wraps past midnight (e.g. 22:00 -> 06:00 = 8 hours overnight).
class DifferentialWindow {
  final String startLocal;
  final String endLocal;

  const DifferentialWindow({required this.startLocal, required this.endLocal});
}

/// One pluggable differential (NIGHT/WEEKEND/HOLIDAY/HAZARD/CALLBACK/CUSTOM).
class PayDifferential {
  final String? id;

  /// NIGHT | WEEKEND | HOLIDAY | HAZARD | CALLBACK | CUSTOM
  final DifferentialType type;

  /// PERCENT (% of base rate) or FLAT (dollars per hour).
  final DifferentialMode mode;
  final double value;

  /// ALL_HOURS_IN_SHIFT or HOURS_IN_WINDOW.
  final DifferentialScope scope;

  /// Required when [scope] == hoursInWindow.
  final DifferentialWindow? window;

  const PayDifferential({
    this.id,
    required this.type,
    required this.mode,
    required this.value,
    this.scope = DifferentialScope.allHoursInShift,
    this.window,
  });
}

/// One overtime rule: hours above [thresholdHours] within [period] are paid
/// at [multiplier] x base rate.
class OvertimeRule {
  final double thresholdHours;
  final OvertimePeriod period;
  final double multiplier;

  const OvertimeRule({
    required this.thresholdHours,
    required this.period,
    required this.multiplier,
  });
}

/// A versioned set of pay rules for one job.
///
/// INVARIANT-005: money semantics live here — never on ShiftTemplate.
/// INVARIANT-006: historical queries resolve the version active at the
/// occurrence's date; later versions never rewrite the past.
class PayRule extends VersionedEntity {
  final String id;
  final String jobId;
  final double baseHourlyRate;
  final List<PayDifferential> differentials;
  final List<OvertimeRule> overtimeRules;

  const PayRule({
    required this.id,
    required this.jobId,
    required this.baseHourlyRate,
    required this.differentials,
    required this.overtimeRules,
    required super.effectiveFrom,
    super.effectiveUntil,
  });
}

/// Everything the engine needs to know about ONE worked shift to compute its
/// pay breakdown. Contextual totals (day/week hours, calendar flags, window
/// times) are computed upstream by the calendar layer; the money engine stays
/// free of timezone/date logic (single responsibility).
class PayInput {
  /// This shift's actual duration in hours (from UTC instants — INVARIANT-002).
  final double shiftHours;

  /// Total hours worked on the same day, including this shift.
  final double dailyHours;

  /// Total hours worked in the same week, including this shift.
  final double weeklyHours;

  /// Qualifiers that decide whether ALL_HOURS differentials apply.
  final bool isNightShift;
  final bool isWeekend;
  final bool isHoliday;

  /// Extra qualifiers (HAZARD / CALLBACK / CUSTOM differentials).
  final Set<DifferentialType> extraTags;

  /// Local civil start/end ("HH:mm", end may carry "+1") — used only to
  /// compute HOURS_IN_WINDOW overlap. Null when no window differentials.
  final String? shiftStartLocal;
  final String? shiftEndLocal;

  /// Optional pre-assigned overtime for THIS shift, produced by the weekly
  /// LIFO allocation (plan2 §5.7) when a WEEK rule is in play across a real
  /// multi-shift week (PAY-014). When null the engine derives OT from the
  /// rules themselves.
  final double? assignedOvertimeHours;

  /// Multiplier to pair with [assignedOvertimeHours].
  final double? assignedMultiplier;

  const PayInput({
    required this.shiftHours,
    this.dailyHours = 0,
    this.weeklyHours = 0,
    this.isNightShift = false,
    this.isWeekend = false,
    this.isHoliday = false,
    this.extraTags = const {},
    this.shiftStartLocal,
    this.shiftEndLocal,
    this.assignedOvertimeHours,
    this.assignedMultiplier,
  });
}

/// What a breakdown line represents (regular / a differential / overtime).
enum PayLineKind {
  regular,
  differential,
  overtime,
}

/// One itemized line of a pay breakdown, ready for UI display.
class PayLine {
  final String label;
  final PayLineKind kind;

  /// Differential type when [kind] == differential.
  final DifferentialType? differentialType;

  final double hours;
  final double rate; // effective per-hour rate on this line
  final double amount;

  const PayLine({
    required this.label,
    required this.kind,
    this.differentialType,
    required this.hours,
    required this.rate,
    required this.amount,
  });
}

/// The full breakdown for one shift.
///
/// Every amount is always accompanied by this breakdown and the disclaimer —
/// "Estimate — not official payroll" (plan1 §7 display principle).
class PayBreakdown {
  final List<PayLine> lines;
  final double total;
  final double regularHours;
  final double overtimeHours;

  /// Display principle from plan1 §7 — every amount ships with this label.
  static const String disclaimer = 'Estimate — not official payroll';

  const PayBreakdown({
    required this.lines,
    required this.total,
    required this.regularHours,
    required this.overtimeHours,
  });

  double get regularPay => _amountOf(PayLineKind.regular);
  double get overtimePay => _amountOf(PayLineKind.overtime);

  /// Sum of differential amounts, keyed by differential type.
  Map<DifferentialType, double> get differentialPay {
    final map = <DifferentialType, double>{};
    for (final line in lines) {
      if (line.kind == PayLineKind.differential && line.differentialType != null) {
        map.update(
          line.differentialType!,
          (v) => v + line.amount,
          ifAbsent: () => line.amount,
        );
      }
    }
    return map;
  }

  double _amountOf(PayLineKind kind) => lines
      .where((l) => l.kind == kind)
      .fold(0.0, (sum, l) => sum + l.amount);
}
