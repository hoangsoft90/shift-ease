// =============================================================================
// Income breakdown screen (RC plan §B3/B4). Full-screen estimate for ONE job
// over a selectable range (This week / This month / custom date range).
//
// Layout per plan §B3:
//   Date / Range
//   Hours
//   Regular Pay
//   Differentials (Night / Weekend / Holiday — as configured)
//   Overtime
//   --------------------------------
//   Estimated Total
//
// Honesty rules (locked):
//   - every amount ships with the disclaimer 'Ước tính — không phải bảng lương
//     chính thức' (D-C6);
//   - when the config cannot price the range accurately the screen shows
//     'Unable to calculate accurately' + the SPECIFIC reason — never a fake $0
//     (RC §B2: multi-version ranges with weekly OT, missing rule, …).
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/domain/income_estimate.dart';
import 'package:shiftease/domain/schedule_service.dart';

enum _RangePreset {
  thisWeek,
  thisMonth,
  custom,
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

(DateTime, DateTime) _rangeFor(_RangePreset preset, DateTime now) {
  switch (preset) {
    case _RangePreset.thisWeek:
      final mon = _dateOnly(now)
          .subtract(Duration(days: now.weekday - DateTime.monday));
      return (mon, mon.add(const Duration(days: 6)));
    case _RangePreset.thisMonth:
      return (
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 0),
      );
    case _RangePreset.custom:
      return (now, now);
  }
}

class IncomeBreakdownScreen extends StatefulWidget {
  final ScheduleService service;
  final String jobId;
  const IncomeBreakdownScreen({
    super.key,
    required this.service,
    required this.jobId,
  });

  @override
  State<IncomeBreakdownScreen> createState() => _IncomeBreakdownScreenState();
}

class _IncomeBreakdownScreenState extends State<IncomeBreakdownScreen> {
  _RangePreset _preset = _RangePreset.thisWeek;
  DateTime _customStart = _dateOnly(DateTime.now());
  DateTime _customEnd = _dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final job =
        widget.service.jobs().firstWhere((j) => j.id == widget.jobId);
    final now = DateTime.now();
    final (from, to) = _rangeFor(_preset, now);
    final start = _preset == _RangePreset.custom ? _customStart : from;
    final end = _preset == _RangePreset.custom ? _customEnd : to;

    final est = widget.service.estimateIncome(
      jobId: widget.jobId,
      rangeStart: _iso(start),
      rangeEnd: _iso(end),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Income · ${job.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_RangePreset>(
            segments: const [
              ButtonSegment(
                  value: _RangePreset.thisWeek, label: Text('This week')),
              ButtonSegment(
                  value: _RangePreset.thisMonth, label: Text('This month')),
              ButtonSegment(
                  value: _RangePreset.custom, label: Text('Custom…')),
            ],
            selected: {_preset},
            onSelectionChanged: (s) => setState(() => _preset = s.first),
          ),
          const SizedBox(height: 8),
          if (_preset == _RangePreset.custom)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickStart(),
                    child: Text('From ${_iso(_customStart)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickEnd(),
                    child: Text('To ${_iso(_customEnd)}'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_iso(start)} → ${_iso(end)}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (est.available) ...[
                    Text('Hours worked: ${est.hoursWorked.toStringAsFixed(1)}h',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    _line(context, 'Regular Pay', est.regularPay),
                    for (final line in est.lines)
                      if (line.kind == PayLineKind.differential)
                        _line(context, line.label, line.amount),
                    for (final line in est.lines)
                      if (line.kind == PayLineKind.overtime)
                        _line(context, 'Overtime', line.amount),
                    const Divider(height: 20),
                    _line(context, 'Estimated Total', est.total,
                        emphasize: true),
                  ] else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Unable to calculate accurately',
                            style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(est.unavailableReason ?? 'Unable to calculate.',
                            style: const TextStyle(color: Colors.blueGrey)),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(WeekIncomeEstimate.disclaimer,
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _customStart = _dateOnly(picked));
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _customEnd = _dateOnly(picked));
  }

  Widget _line(BuildContext context, String label, double amount,
      {bool emphasize = false}) {
    final style = emphasize
        ? Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: style ?? const TextStyle(color: Colors.blueGrey)),
          ),
          Text('USD \$${amount.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}