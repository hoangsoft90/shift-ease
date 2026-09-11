// =============================================================================
// Month view (M1b, D2). One job's month as a 7-column grid. Rendering goes
// through the same ScheduleService.renderJob (engine, overrides replayed)
// with persist:false — a read-only projection, never a DB write on build.
// Each day cell shows the count of shifts and up to two local start times;
// tapping a day pushes the WeekCalendar for that day's week (drill-down),
// where edits (override) and Quick Add live. Times shown are each
// occurrence's OWN local wall-clock (INVARIANT-007).
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/calendar/week_calendar_screen.dart';

const List<String> _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class MonthCalendarScreen extends StatefulWidget {
  final ScheduleService service;
  final String jobId;
  const MonthCalendarScreen(
      {super.key, required this.service, required this.jobId});

  @override
  State<MonthCalendarScreen> createState() => _MonthCalendarScreenState();
}

class _MonthCalendarScreenState extends State<MonthCalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day)
          .subtract(Duration(days: d.weekday - DateTime.monday));

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final first = DateTime(_month.year, _month.month, 1);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final gridStart = _mondayOf(first);

    final result = service.renderJob(
        jobId: widget.jobId,
        rangeStart: _iso(first),
        rangeEnd: _iso(last),
        persist: false);
    final byDay = <String, List<ShiftOccurrence>>{};
    for (final o in result.occurrences) {
      byDay.putIfAbsent(o.shiftDate, () => []).add(o);
    }

    final today = DateTime.now();
    final cells = <DateTime>[];
    for (var i = 0; i < 42; i++) {
      cells.add(gridStart.add(Duration(days: i)));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${_monthName(_month.month)} ${_month.year} · ${service.jobs().firstWhere((j) => j.id == widget.jobId).name}'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1)),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Today',
            onPressed: () => setState(() => _month = DateTime(today.year, today.month)),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              for (final name in _weekdayNames)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
          // Fixed 6×7 grid (no lazy building): every cell of the month is a
          // real widget — the whole month is a bounded view, no scrolling.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Column(
                children: [
                  for (var row = 0; row < 6; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: _dayCell(context,
                                  cells[row * 7 + col],
                                  byDay[_iso(cells[row * 7 + col])] ?? const [],
                                  today),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime day,
      List<ShiftOccurrence> occurrences, DateTime today) {
    final inMonth = day.month == _month.month && day.year == _month.year;
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    return InkWell(
      key: ValueKey('month-day-${_iso(day)}'),
      borderRadius: BorderRadius.circular(6),
      onTap: inMonth && occurrences.isNotEmpty
          ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WeekCalendarScreen(
                    service: widget.service,
                    jobId: widget.jobId,
                    initialDate: day),
              ))
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? Colors.blue.shade50 : null,
          border: Border.all(
              color: inMonth ? Colors.grey.shade300 : Colors.grey.shade200,
              width: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: inMonth
                    ? (isToday ? Colors.blue.shade800 : null)
                    : Colors.grey.shade400,
              ),
            ),
            if (occurrences.isNotEmpty) ...[
              const Spacer(),
              for (final o in occurrences.take(2))
                Text(_startLabel(o),
                    style: const TextStyle(fontSize: 9),
                    overflow: TextOverflow.ellipsis),
              if (occurrences.length > 2)
                Text('+${occurrences.length - 2} more',
                    style: const TextStyle(fontSize: 8, color: Colors.blueGrey)),
            ],
          ],
        ),
      ),
    );
  }

  String _startLabel(ShiftOccurrence o) {
    final wall = widget.service.localWallTime(o);
    return wall?.start ?? '--:--';
  }

  String _monthName(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];
}
