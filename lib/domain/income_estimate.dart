// =============================================================================
// Income estimate (Gate C B2) — domain use-case over core/money + rendered
// occurrences.
//
// Honesty rules (locked by the Correctness Contract + Gate C D-C6 + RC §B1/B2):
//   - NO number is ever produced when the config cannot price it accurately.
//     A shift date with no active PayRule, a payroll week spanning multiple
//     PayRule versions with a WEEK overtime scheme, or a rule mixing several
//     WEEK OT schemes → [WeekIncomeEstimate] is UNAVAILABLE with an explicit
//     reason. Never a guessed $0.
//   - When available, the arithmetic is EXACTLY the money engine's
//     (calculatePayBreakdown), with WEEK overtime distributed LIFO across the
//     range (allocateWeeklyOvertime) — the same numbers the integration suites
//     pin (e.g. 3×14h @ $35 + 40h/week ×1.5 = $1505).
//   - RC §B1: every shift is priced under the rule ACTIVE ON ITS OWN DATE
//     (per-occurrence resolution), and HOURS_IN_WINDOW differentials use the
//     shift's own local wall-clock (derived from its resolved UTC instants in
//     its own timezone) — the exact PAY-013 overlap the money engine consumes.
//   - Every amount is displayed with the estimate disclaimer (D-C6).
// =============================================================================

import 'package:timezone/timezone.dart' as tz;

import 'package:shiftease/core/money/money_engine.dart';
import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/core/pattern/pattern_types.dart'
    show ShiftOccurrence;

/// One itemized income line aggregated over the range.
class IncomeLine {
  final String label;
  final PayLineKind kind;
  final double amount;

  /// Differential type when [kind] == differential (kept for the breakdown
  /// screen to group Night/Weekend/Holiday/... sections).
  final DifferentialType? differentialType;

  const IncomeLine({
    required this.label,
    required this.kind,
    required this.amount,
    this.differentialType,
  });
}

/// The range income estimate for one job.
class WeekIncomeEstimate {
  /// False when the config cannot price the range accurately.
  final bool available;

  /// Human reason when [available] == false (shown verbatim in the UI).
  final String? unavailableReason;

  final List<IncomeLine> lines;
  final double total;
  final double hoursWorked;

  /// Display label shipped with every amount (D-C6).
  static const String disclaimer =
      'Estimate — not an official payroll figure';

  const WeekIncomeEstimate({
    required this.available,
    this.unavailableReason,
    this.lines = const [],
    this.total = 0,
    this.hoursWorked = 0,
  });

  factory WeekIncomeEstimate.unavailable(String reason) => WeekIncomeEstimate(
        available: false,
        unavailableReason: reason,
      );

  double get regularPay => _payOf(PayLineKind.regular);
  double get overtimePay => _payOf(PayLineKind.overtime);
  double get differentialPay => _payOf(PayLineKind.differential);

  double _payOf(PayLineKind kind) =>
      lines.where((l) => l.kind == kind).fold(0.0, (s, l) => s + l.amount);
}

/// Before/After/Delta of one edit (RC plan §B6). Built from a persist:false
/// estimate of the CURRENT effective schedule vs the PROSPECTIVE one — the
/// preview never writes the DB. When either leg cannot be priced accurately
/// [available] is false with the specific reason — never a guessed delta.
class IncomeImpact {
  final bool available;
  final String? unavailableReason;
  final double before;
  final double after;
  final double delta;

  const IncomeImpact({
    required this.available,
    this.unavailableReason,
    this.before = 0,
    this.after = 0,
    this.delta = 0,
  });

  factory IncomeImpact.unavailable(String reason) =>
      IncomeImpact(available: false, unavailableReason: reason);
}

/// Compute a job's income estimate over [shifts] (resolved occurrences) given
/// the job's pay rules. [activeRuleFor] resolves the rule active on a date
/// (INVARIANT-006 — newest effectiveFrom wins, never rewritten history).
///
/// RC plan §B1/B2 semantics (money-engine parity):
///   - EVERY shift is priced under the rule ACTIVE ON ITS OWN DATE
///     (per-occurrence resolution — never the rule of the range's first day).
///   - HOURS_IN_WINDOW differentials use the real window overlap over the
///     shift's OWN local wall-clock (derived from its resolved UTC instants in
///     its own timezone, INVARIANT-002/007) — exactly what the money engine's
///     windowOverlapHours consumes, so PAY-013-style windows price identically.
///     No hardcoded 19:00–06:00 band ever substitutes for a configured window.
///   - WEEK overtime is distributed LIFO (PAY-014) and is only defined when the
///     WHOLE range shares ONE rule version (a payroll week spanning multiple
///     versions has no provable weekly allocation) — otherwise UNAVAILABLE with
///     the explicit reason (RC §B2). SHIFT/DAY OT + differentials stay exact
///     per occurrence under multi-version ranges.
///   - Missing rule / malformed config → UNAVAILABLE + reason. Never $0.
WeekIncomeEstimate estimateJobIncome({
  required List<ShiftOccurrence> shifts,
  required PayRule? Function(String jobId, String date) activeRuleFor,
  required String jobId,
}) {
  if (shifts.isEmpty) {
    return const WeekIncomeEstimate(available: true, hoursWorked: 0);
  }
  double hoursOf(ShiftOccurrence o) {
    final s = DateTime.parse(o.startDateTimeUtc).millisecondsSinceEpoch;
    final e = DateTime.parse(o.endDateTimeUtc).millisecondsSinceEpoch;
    return (e - s) / 3600000.0;
  }

  final totalHours = shifts.fold(0.0, (sum, o) => sum + hoursOf(o));

  // Per-occurrence rule resolution (RC §B2 — never the week-start rule).
  final ruleOf = <String, PayRule>{};
  for (final o in shifts) {
    final rule = activeRuleFor(jobId, o.shiftDate);
    if (rule == null) {
      return WeekIncomeEstimate.unavailable(
          'No active pay rule for ${o.shiftDate} — guessing is not allowed.\n'
          '(Unable to calculate accurately: no active pay rule on '
          '${o.shiftDate}.)');
    }
    ruleOf[o.id] = rule;
  }
  final distinctRuleIds = ruleOf.values.map((r) => r.id).toSet();

  // WEEK OT schemes: at most one per rule; and a multi-version range with ANY
  // WEEK rule cannot allocate LIFO provably (RC §B2) → UNAVAILABLE.
  final weekScheme = <String, ({PayRule rule, OvertimeRule ot})>{};
  for (final rule in ruleOf.values) {
    final wrs = rule.overtimeRules
        .where((r) => r.period == OvertimePeriod.week)
        .toList();
    if (wrs.length > 1) {
      return WeekIncomeEstimate.unavailable(
          'Multiple weekly overtime schemes — pick one.\n(Unable to calculate '
          'accurately: multiple weekly overtime schemes.)');
    }
    if (wrs.isNotEmpty) weekScheme[rule.id] = (rule: rule, ot: wrs.single);
  }
  if (distinctRuleIds.length > 1 && weekScheme.isNotEmpty) {
    return WeekIncomeEstimate.unavailable(
        'This week spans multiple pay-rule versions with a weekly overtime '
        'scheme — totals cannot be split accurately.\n(Unable to calculate '
        'accurately: weekly overtime cannot be determined across multiple '
        'pay-rule versions.)');
  }
  final weekSchemeRule =
      weekScheme.isEmpty ? null : weekScheme.values.single;

  final allocation = weekSchemeRule == null
      ? <String, double>{}
      : allocateWeeklyOvertime(
          shifts: shifts,
          weeklyThreshold: weekSchemeRule.ot.thresholdHours,
        );

  // Per-day totals (DAY-period OT rules need the whole day's hours).
  final dailyHours = <String, double>{};
  for (final o in shifts) {
    dailyHours.update(o.shiftDate, (v) => v + hoursOf(o),
        ifAbsent: () => hoursOf(o));
  }

  final lineAmounts = <(String, PayLineKind), double>{};
  final lineTypes = <String, DifferentialType>{};
  for (final o in shifts) {
    final rule = ruleOf[o.id]!;
    final wall = _localWallTimes(o);
    final bd = calculatePayBreakdown(
      input: PayInput(
        shiftHours: hoursOf(o),
        dailyHours: dailyHours[o.shiftDate] ?? hoursOf(o),
        weeklyHours: totalHours,
        isNightShift: _isNightShift(o),
        isWeekend: _isWeekend(o.shiftDate),
        // RC §B1: the shift's OWN local wall-clock — window differentials
        // price exactly like the money engine's PAY-013 overlap.
        shiftStartLocal: wall?.start,
        shiftEndLocal: wall?.end,
        assignedOvertimeHours: weekSchemeRule == null
            ? null
            : (allocation[o.id] ?? 0),
        assignedMultiplier: weekSchemeRule?.ot.multiplier,
      ),
      rule: rule,
    );
    for (final line in bd.lines) {
      lineAmounts.update(
        (line.label, line.kind),
        (v) => v + line.amount,
        ifAbsent: () => line.amount,
      );
      final t = line.differentialType;
      if (t != null) lineTypes[line.label] = t;
    }
  }

  return WeekIncomeEstimate(
    available: true,
    lines: [
      for (final e in lineAmounts.entries)
        IncomeLine(
          label: e.key.$1,
          kind: e.key.$2,
          amount: e.value,
          differentialType: lineTypes[e.key.$1],
        ),
    ],
    total:
        lineAmounts.values.fold(0.0, (sum, v) => sum + v),
    hoursWorked: totalHours,
  );
}

/// Local wall-clock start/end of the shift, derived from its RESOLVED UTC
/// instants in its OWN timezone (INVARIANT-002/007). The end carries the "+1"
/// marker when it falls on the next local day — exactly the shape the money
/// engine's windowOverlapHours consumes (PAY-013). Null when the zone is
/// unknown (never guess — the window differential then prices nothing, which
/// matches the engine receiving null locals).
({String start, String end})? _localWallTimes(ShiftOccurrence o) {
  try {
    final loc = tz.getLocation(o.timezone);
    final startLocal = tz.TZDateTime.from(
        DateTime.parse(o.startDateTimeUtc).toUtc(), loc);
    final endLocal = tz.TZDateTime.from(
        DateTime.parse(o.endDateTimeUtc).toUtc(), loc);
    String hhmm(tz.TZDateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    final dayDiff = DateTime.utc(endLocal.year, endLocal.month, endLocal.day)
        .difference(DateTime.utc(
            startLocal.year, startLocal.month, startLocal.day))
        .inDays;
    // Multi-day shifts (>24h) still express as a next-day end — the engine's
    // wrap convention only distinguishes same-day vs overnight.
    final end = dayDiff > 0 ? '${hhmm(endLocal)}+1' : hhmm(endLocal);
    return (start: hhmm(startLocal), end: end);
  } catch (_) {
    return null;
  }
}

/// Night qualifier (ALL_HOURS night differential): the shift STARTS in the
/// night band — 19:00 or later, or before 06:00 — on the occurrence's OWN
/// wall clock (derived from the stored UTC in its timezone, INVARIANT-007).
bool _isNightShift(ShiftOccurrence o) {
  try {
    final loc = tz.getLocation(o.timezone);
    final local = tz.TZDateTime.from(
        DateTime.parse(o.startDateTimeUtc).toUtc(), loc);
    final h = local.hour;
    return h >= 19 || h < 6;
  } catch (_) {
    return false; // unknown zone: never claim a night premium
  }
}

/// Weekend qualifier: the shift's civil date is a Saturday or Sunday.
bool _isWeekend(String isoDate) {
  final d = DateTime.parse(isoDate);
  return d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
}
