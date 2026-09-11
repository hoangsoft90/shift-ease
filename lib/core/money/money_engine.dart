// =============================================================================
// ShiftEase Money Engine — Core Implementation
// =============================================================================
//
// Locked decisions implemented here (plan2.md §5.2–§5.7):
//
// 1. Method B — Regular + Overtime separated. No double counting: the
//    overtime hours are excluded from regular hours and paid ONCE at
//    rate x multiplier (never (1 + multiplier)x).
// 2. Multi-rule OT: compute overtime hours per applicable rule and take the
//    MAX — never the sum (avoids paying the same hours twice). The multiplier
//    is the highest multiplier among the rules that produce that max.
// 3. Differentials apply to REGULAR hours only (never to overtime hours).
// 4. HOURS_IN_WINDOW differentials count the half-open wall-clock overlap
//    between the shift's local times and a (possibly midnight-wrapping)
//    daily window; the counted hours are capped at regular hours.
// 5. Overtime is the MAX of two independent components, never their sum:
//      a) SHIFT/DAY rules evaluated on this shift's own context;
//      b) the WEEK overage attributable to this shift — for a real
//         multi-shift week that is its LIFO share from allocateWeeklyOvertime
//         (PAY-014, authoritative including 0), for a single-shift context it
//         is the WEEK overage directly (PAY-005).
//    This composes daily-OT states (CA) with the weekly LIFO distribution
//    without double-counting OR under-counting.
// 6. INVARIANT-006: resolve the PayRule ACTIVE at the occurrence date via
//    getActivePayRule; historical pay is never re-priced by newer versions.
//
// NEVER:
// - double-count overtime (base + premium on the same hours)
// - apply differentials to overtime hours
// - reach into pattern/time internals — the caller supplies resolved hours
//   and qualifiers through PayInput
// =============================================================================

import 'package:shiftease/core/pattern/pattern_types.dart'
    show ShiftOccurrence;
import 'money_types.dart';

/// Compute the full pay breakdown for one shift under one active [rule].
///
/// [input.shiftHours] is the shift's true duration (UTC-derived upstream,
/// INVARIANT-002). [input.dailyHours]/[input.weeklyHours] are the contextual
/// totals used by DAY/WEEK overtime rules.
PayBreakdown calculatePayBreakdown({
  required PayInput input,
  required PayRule rule,
}) {
  final (otHours, otMultiplier) = _overtimeOf(input, rule);
  // Method B: regular hours exclude the overtime hours (no double-count).
  final regularHours = (input.shiftHours - otHours).clamp(0.0, input.shiftHours);

  final lines = <PayLine>[];

  // 1. Regular pay — regular hours only (Method B).
  lines.add(PayLine(
    label: 'Regular Pay',
    kind: PayLineKind.regular,
    hours: regularHours,
    rate: rule.baseHourlyRate,
    amount: regularHours * rule.baseHourlyRate,
  ));

  // 2. Differentials — regular hours only, never overtime (locked).
  for (final diff in rule.differentials) {
    final applicableHours = _applicableHours(diff, input, regularHours);
    if (applicableHours <= 0) continue;
    final rate = diff.mode == DifferentialMode.percent
        ? rule.baseHourlyRate * (diff.value / 100.0)
        : diff.value;
    final amount = diff.mode == DifferentialMode.percent
        ? applicableHours * rule.baseHourlyRate * (diff.value / 100.0)
        : applicableHours * diff.value;
    lines.add(PayLine(
      label: '${_diffLabel(diff.type)} Differential',
      kind: PayLineKind.differential,
      differentialType: diff.type,
      hours: applicableHours,
      rate: rate,
      amount: amount,
    ));
  }

  // 3. Overtime pay — full rate x multiplier on the overtime hours, once.
  if (otHours > 0) {
    lines.add(PayLine(
      label: 'Overtime Pay',
      kind: PayLineKind.overtime,
      hours: otHours,
      rate: rule.baseHourlyRate * otMultiplier,
      amount: otHours * rule.baseHourlyRate * otMultiplier,
    ));
  }

  final total = lines.fold(0.0, (sum, line) => sum + line.amount);
  return PayBreakdown(
    lines: lines,
    total: total,
    regularHours: regularHours,
    overtimeHours: otHours,
  );
}

/// Overtime (hours, multiplier) for this shift — the single composition
/// point that guarantees NO double-counting AND NO under-counting.
///
/// Two independent components, combined by MAX (never summed, plan2 §5.4):
///
///   1. SHIFT/DAY component — this shift's own context. Overtime from every
///      SHIFT and DAY rule, capped at the shift's duration.
///   2. WEEK component — the WEEK overtime attributable to THIS shift. In a
///      real multi-shift week the caller already distributed the week's
///      overage via allocateWeeklyOvertime (LIFO, PAY-014) and passes it as
///      [PayInput.assignedOvertimeHours]; that share is authoritative and
///      replaces any per-shift WEEK overage (assigned 0 means "this shift
///      absorbs none of the weekly overage"). In a single-shift context
///      (assigned == null) the WEEK overage is attributed to this shift
///      directly, as in PAY-005.
///
/// Component hours are capped at the shift's duration, so the max is too.
/// When two components tie on hours the higher multiplier wins.
///
/// Multiplier used when [assignedOvertimeHours] produced the WEEK component:
/// the caller's explicit multiplier, else the best WEEK multiplier in the
/// rule, else 1.0 — never an assumed 1.5.
double _assignedWeekMultiplier(PayInput input, PayRule rule) {
  final explicit = input.assignedMultiplier;
  if (explicit != null && explicit > 1) return explicit;
  double? best;
  for (final r in rule.overtimeRules) {
    if (r.period == OvertimePeriod.week &&
        (best == null || r.multiplier > best)) {
      best = r.multiplier;
    }
  }
  return best ?? 1.0;
}

/// Overtime hours above [threshold] for [period] (raw, uncapped — the caller
/// caps at the shift's duration).
double _periodOverHours(
  OvertimePeriod period,
  double threshold,
  PayInput input,
) {
  final base = switch (period) {
    OvertimePeriod.shift => input.shiftHours,
    OvertimePeriod.day => input.dailyHours,
    OvertimePeriod.week => input.weeklyHours,
  };
  return (base - threshold).clamp(0.0, double.infinity);
}

(double, double) _overtimeOf(PayInput input, PayRule rule) {
  var bestHours = 0.0;
  var bestMultiplier = 1.0;

  // MAX composition — never the sum (plan2 §5.4). Ties pick the higher
  // multiplier (plan2 §5.4 example: x1.0 and x1.5 rules both yielding 2h
  // pay at x1.5).
  void consider(double ot, double multiplier) {
    if (ot <= 0) return;
    if (ot > bestHours) {
      bestHours = ot;
      bestMultiplier = multiplier;
    } else if (ot == bestHours && multiplier > bestMultiplier) {
      bestMultiplier = multiplier;
    }
  }

  // Component 1: SHIFT/DAY rules — always evaluated from this shift's own
  // context, regardless of the WEEK allocation.
  for (final r in rule.overtimeRules) {
    if (r.period == OvertimePeriod.week) continue;
    consider(
      _periodOverHours(r.period, r.thresholdHours, input)
          .clamp(0.0, input.shiftHours),
      r.multiplier,
    );
  }

  // Component 2: WEEK overage attributable to this shift.
  final assigned = input.assignedOvertimeHours;
  if (assigned != null) {
    // LIFO share is authoritative — including 0 ("this shift absorbs none").
    consider(
      assigned.clamp(0.0, input.shiftHours),
      _assignedWeekMultiplier(input, rule),
    );
  } else {
    for (final r in rule.overtimeRules) {
      if (r.period != OvertimePeriod.week) continue;
      consider(
        _periodOverHours(r.period, r.thresholdHours, input)
            .clamp(0.0, input.shiftHours),
        r.multiplier,
      );
    }
  }

  return (bestHours, bestMultiplier);
}

/// Whether a differential applies to this shift, and how many hours it covers.
double _applicableHours(
  PayDifferential diff,
  PayInput input,
  double regularHours,
) {
  switch (diff.scope) {
    case DifferentialScope.allHoursInShift:
      final applies = switch (diff.type) {
        DifferentialType.night => input.isNightShift,
        DifferentialType.weekend => input.isWeekend,
        DifferentialType.holiday => input.isHoliday,
        DifferentialType.hazard ||
        DifferentialType.callback ||
        DifferentialType.custom =>
          input.extraTags.contains(diff.type),
      };
      return applies ? regularHours : 0;
    case DifferentialScope.hoursInWindow:
      final window = diff.window;
      final start = input.shiftStartLocal;
      final end = input.shiftEndLocal;
      if (window == null || start == null || end == null) return 0;
      final overlap = windowOverlapHours(
        shiftStartLocal: start,
        shiftEndLocal: end,
        window: window,
      );
      if (overlap <= 0) return 0;
      // Differentials never touch overtime hours — cap at regular hours.
      return overlap < regularHours ? overlap : regularHours;
  }
}

/// Half-open wall-clock overlap (hours) between an overnight-capable shift and
/// an overnight-capable daily window, both anchored at the shift's local day.
///
/// "03:00+1" end times and windows whose end precedes their start (22:00 →
/// 06:00) wrap past midnight. Overlap is computed on absolute minutes so the
/// result is DST-free wall-clock arithmetic: PAY-013, shift 15:00→03:00+1 vs
/// window 22:00→06:00 → overlap 5h (22:00–03:00).
double windowOverlapHours({
  required String shiftStartLocal,
  required String shiftEndLocal,
  required DifferentialWindow window,
}) {
  var shiftStart = _toMinutes(shiftStartLocal);
  var shiftEnd = _toMinutes(shiftEndLocal);
  var winStart = _toMinutes(window.startLocal);
  var winEnd = _toMinutes(window.endLocal);

  // Midnight wrapping, matching core/time overnight conventions:
  // an end no later than its start means the interval crosses midnight
  // (03:00+1 for shifts, 22:00 -> 06:00 for windows).
  if (shiftEnd <= shiftStart) shiftEnd += 1440;
  if (winEnd <= winStart) winEnd += 1440;

  if (shiftEnd <= shiftStart || winEnd <= winStart) return 0; // degenerate
  final overlap =
      _minDouble(shiftEnd, winEnd) - _maxDouble(shiftStart, winStart);
  return overlap > 0 ? overlap / 60.0 : 0.0;
}

/// "HH:mm" (optionally "HH:mm+1") -> minutes from the local day's midnight.
double _toMinutes(String time) {
  final marker = time.contains('+1') ? 1440.0 : 0.0;
  final clean = time.replaceAll('+1', '');
  final parts = clean.split(':');
  final hour = double.parse(parts[0]);
  final minute = parts.length > 1 ? double.parse(parts[1]) : 0.0;
  return hour * 60 + minute + marker;
}

/// Resolve the [PayRule] ACTIVE for [jobId] on [date] (INVARIANT-006).
///
/// Query semantics match VersionedEntity: effectiveFrom <= date <=
/// effectiveUntil (null effectiveUntil = still active). Newest version wins
/// on equal effectiveFrom.
PayRule? getActivePayRule({
  required List<PayRule> rules,
  required String jobId,
  required String date,
}) {
  final sorted = List<PayRule>.from(rules)
    ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));
  for (final rule in sorted) {
    if (rule.jobId == jobId && rule.isActiveOn(date)) {
      return rule;
    }
  }
  return null;
}

/// LIFO distribution of WEEK overtime across the shifts of one week (plan2
/// §5.7). The caller supplies the week's shifts; hours come from each
/// occurrence's RESOLVED UTC instants (INVARIANT-002). Overtime is attributed
/// to the chronologically LAST shift first, walking backwards; if a shift is
/// too short to absorb the remainder, the overflow rolls to the previous one.
///
/// Returns a map occurrenceId -> overtimeHours (0 for untouched shifts).
Map<String, double> allocateWeeklyOvertime({
  required List<ShiftOccurrence> shifts,
  required double weeklyThreshold,
}) {
  return allocateWeeklyOvertimeHours(
    shifts: [
      for (final s in shifts)
        (
          id: s.id,
          shiftDate: s.shiftDate,
          hours: _durationHoursOf(s),
        )
    ],
    weeklyThreshold: weeklyThreshold,
  );
}

/// Duration of an occurrence derived from its resolved UTC instants.
double _durationHoursOf(ShiftOccurrence occurrence) {
  final start =
      DateTime.parse(occurrence.startDateTimeUtc).millisecondsSinceEpoch;
  final end =
      DateTime.parse(occurrence.endDateTimeUtc).millisecondsSinceEpoch;
  return (end - start) / 3600000.0;
}

/// LIFO distribution of WEEK overtime across the shifts of one week (plan2
/// §5.7) — DECOUPLED from any occurrence type.
///
/// The pattern engine feeds [ShiftOccurrence]s through allocateWeeklyOvertime;
/// the import pipeline feeds its UTC-resolved CommittedShift output through
/// this hours-based core (ids + shiftDate + duration hours only) — no one
/// fabricates another layer's types to reach the allocation.
///
/// Overtime is attributed to the chronologically LAST shift first, walking
/// backwards; a shift too short to absorb the remainder rolls the overflow to
/// the previous one.
Map<String, double> allocateWeeklyOvertimeHours({
  required List<({String id, String shiftDate, double hours})> shifts,
  required double weeklyThreshold,
}) {
  final ordered = List.of(shifts)
    ..sort((a, b) {
      final byDate = a.shiftDate.compareTo(b.shiftDate);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });

  final hoursById = <String, double>{
    for (final s in ordered) s.id: s.hours,
  };
  final totalHours = hoursById.values.fold(0.0, (sum, h) => sum + h);
  var remainingOt = (totalHours - weeklyThreshold).clamp(0.0, double.infinity);

  final allocation = <String, double>{
    for (final s in ordered) s.id: 0.0,
  };

  // Walk backwards — last chronological shift absorbs OT first (LIFO).
  for (var i = ordered.length - 1; i >= 0 && remainingOt > 0; i--) {
    final shift = ordered[i];
    final shiftHours = hoursById[shift.id]!;
    final assigned = shiftHours < remainingOt ? shiftHours : remainingOt;
    allocation[shift.id] = assigned;
    remainingOt -= assigned;
  }

  return allocation;
}

double _minDouble(double a, double b) => a < b ? a : b;
double _maxDouble(double a, double b) => a > b ? a : b;

String _diffLabel(DifferentialType type) {
  final raw = type.name;
  return '${raw[0].toUpperCase()}${raw.substring(1).toLowerCase()}';
}
