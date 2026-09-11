// =============================================================================
// Week Calendar (M1). A 7-column grid (Mon..Sun). Every render goes through
// ScheduleService.renderJob → ScheduleRepository.renderJobSchedule (active
// versions + append-only override replay through the pure engine, then the
// resulting occurrences are persisted). Issues the engine raised are shown in
// a banner — the calendar never shows a phantom shift and never hides a
// failure. Shift cards display the occurrence's OWN local wall-clock from its
// stored UTC (INVARIANT-007/002); the pattern/override rules that produced
// them are invisible here by design (INVARIANT-001).
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/app/color.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/calendar/quick_add_sheet.dart';
import 'package:shiftease/features/occurrence/occurrence_sheet.dart';

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class WeekCalendarScreen extends StatefulWidget {
  final ScheduleService service;
  final String jobId;

  /// Any date inside the week to show first (Month view drills into the week
  /// containing the tapped day). Defaults to the current week.
  final DateTime? initialDate;

  const WeekCalendarScreen(
      {super.key, required this.service, required this.jobId,
      this.initialDate});

  @override
  State<WeekCalendarScreen> createState() => _WeekCalendarScreenState();
}

class _WeekCalendarScreenState extends State<WeekCalendarScreen> {
  late DateTime _weekStart =
      _mondayOf(widget.initialDate ?? DateTime.now());

  static DateTime _mondayOf(DateTime d) {
    final base = DateTime(d.year, d.month, d.day);
    return base.subtract(Duration(days: base.weekday - DateTime.monday));
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final days = List.generate(
        7, (i) => _weekStart.add(Duration(days: i)));
    final from = _iso(days.first);
    final to = _iso(days.last);

    final result = service.renderJob(
        jobId: widget.jobId, rangeStart: from, rangeEnd: to);
    final templates = {for (final t in service.templates(widget.jobId)) t.id: t};

    final byDay = <String, List<ShiftOccurrence>>{
      for (final d in days) _iso(d): [],
    };
    for (final o in result.occurrences) {
      byDay.putIfAbsent(o.shiftDate, () => []).add(o);
    }
    // Deterministic per-day order (same as engine: shiftDate then id).
    byDay.forEach((_, list) => list.sort((a, b) => a.id.compareTo(b.id)));

    return Scaffold(
      appBar: AppBar(
        title: Text(_weekLabel(days)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous week',
          onPressed: () => setState(
              () => _weekStart = _weekStart.subtract(const Duration(days: 7))),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
            onPressed: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7))),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Today',
            onPressed: () =>
                setState(() => _weekStart = _mondayOf(DateTime.now())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (result.issues.isNotEmpty) _issuesBanner(result.issues),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _dayColumn(context, days[i], byDay[_iso(days[i])]!,
                        templates),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _weekLabel(List<DateTime> days) {
    final fmt = List.generate(7, (i) => _iso(days[i]));
    return '${fmt.first}  →  ${fmt.last}';
  }

  Widget _issuesBanner(List<RenderIssue> issues) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Unable to schedule some days:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          for (final issue in issues.take(4))
            Text('• ${issue.code}: ${issue.message}',
                style: const TextStyle(fontSize: 11)),
          if (issues.length > 4)
            Text('…and ${issues.length - 4} more',
                style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _dayColumn(BuildContext context, DateTime day,
      List<ShiftOccurrence> occurrences, Map<String, ShiftTemplate> templates) {
    final iso = _iso(day);
    final isToday = iso == _iso(DateTime.now());
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.shade300, width: 0.5),
          left: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey('day-$iso'),
            onTap: () => _onDayHeaderTap(context, iso),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: isToday ? Colors.blue.shade50 : null,
              child: Column(
                children: [
                  Text(_weekdays[day.weekday - DateTime.monday],
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  Text('${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      )),
                  const Icon(Icons.add_circle_outline, size: 14),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(2),
              itemCount: occurrences.length,
              itemBuilder: (context, i) =>
                  _shiftCard(context, occurrences[i], templates),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shiftCard(BuildContext context, ShiftOccurrence o,
      Map<String, ShiftTemplate> templates) {
    final wall = widget.service.localWallTime(o);
    final template = templates[o.templateId];
    final name = template?.name ?? o.templateId;
    return Card(
      margin: const EdgeInsets.only(bottom: 3),
      color: template == null
          ? Colors.grey.shade200
          : colorFromHex(template.color).withValues(alpha: 0.15),
      child: InkWell(
        key: ValueKey('card-${o.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openSheet(context, o, null),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wall == null ? '--:--' : '${wall.start}–${wall.end}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              Text(name,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  /// Tap on an empty day header → Quick Add: 1-tap template tiles first; the
  /// "Custom time…" tile falls through to the full CREATE form for that day.
  Future<void> _onDayHeaderTap(BuildContext context, String date) async {
    final choice = await showQuickAddSheet(
      context,
      service: widget.service,
      jobId: widget.jobId,
      date: date,
    );
    if (choice == true) {
      if (mounted) setState(() {});
      return;
    }
    if (choice == false && mounted) {
      await _openSheet(context, null, date);
    }
  }

  Future<void> _openSheet(
      BuildContext context, ShiftOccurrence? occurrence, String? date) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OccurrenceSheet(
        service: widget.service,
        jobId: widget.jobId,
        occurrence: occurrence,
        date: date,
      ),
    );
    if (changed == true && mounted) setState(() {});
  }
}
