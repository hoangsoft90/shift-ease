// =============================================================================
// Today screen (M1b, D1). Display-only aggregator across ALL jobs:
//   - what is happening NOW / what is next (countdown to start),
//   - the rest gap before the next shift,
//   - today's shifts (tap → the normal occurrence sheet to edit),
//   - total worked hours this week (Mon..Sun), computed from RESOLVED UTC
//     instants via the time engine (INVARIANT-002) — never local subtraction.
// Income is deliberately NOT here yet: there is no PayRule editor until M3,
// and the Correctness Contract forbids guessing a number from no rules.
// All renders use persist:false — reading never writes the DB.
// =============================================================================

import 'package:flutter/material.dart';

import 'dart:async';

import 'package:shiftease/app/color.dart';
import 'package:shiftease/core/db/pattern_repository.dart' show JobRecord;
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/income_estimate.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/income/income_breakdown_screen.dart';
import 'package:shiftease/features/notifications/shift_reminder.dart';
import 'package:shiftease/features/occurrence/occurrence_sheet.dart';

class TodayScreen extends StatefulWidget {
  final ScheduleService service;
  const TodayScreen({super.key, required this.service});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  final ShiftReminderScheduler _reminders = ShiftReminderScheduler();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // RC §E2 — lifecycle resync
    unawaited(_reminders.requestPermission().then((_) {
      _resyncReminders();
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// RC plan §E2 — app lifecycle: on every RESUME the effective schedule is
  /// reloaded, the next reminder recalculated, the stale one cancelled and
  /// the current one scheduled (syncFromOccurrences does both). Covers a
  /// roster change made while the app was backgrounded (or on another
  /// surface) — the reminder must follow the schedule, never lag behind it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resyncReminders();
    }
  }

  /// Gate C B4 — schedule the shift reminder once per Today-screen creation
  /// (app open / tab state build). Known limitation (non-blocking): an edit
  /// made in a pushed route does NOT re-trigger this until the screen is
  /// recreated; the fixed notification id keeps a stale reminder from
  /// duplicating in the meantime. Never crashes when the plugin is absent.
  void _resyncReminders() {
    final occurrences = <ShiftOccurrence>[];
    for (final job in widget.service.jobs()) {
      final now = DateTime.now();
      final monday =
          _dateOnly(now).subtract(Duration(days: now.weekday - DateTime.monday));
      final result = widget.service.renderJob(
          jobId: job.id,
          rangeStart: _iso(monday),
          rangeEnd: _iso(monday.add(const Duration(days: 13))),
          persist: false);
      occurrences.addAll(result.occurrences);
    }
    unawaited(_reminders.syncFromOccurrences(occurrences));
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final jobs = service.jobs();
    // "Today" and the week Monday are USER-LOCAL calendar dates; instant
    // comparisons (countdown, in-progress) use the UTC clock. Mixing the two
    // would shift the displayed day/week near midnight (review M1b, result12).
    final localNow = DateTime.now();
    final now = localNow.toUtc();
    final monday =
        _dateOnly(localNow).subtract(Duration(days: localNow.weekday - DateTime.monday));
    final weekStart = _iso(monday);
    final weekEnd = _iso(monday.add(const Duration(days: 6)));
    final todayIso = _iso(localNow);

    final weekShifts = <({String jobId, ShiftOccurrence occ})>[];
    final todayShifts = <({String jobId, ShiftOccurrence occ})>[];
    for (final job in jobs) {
      final result = service.renderJob(
          jobId: job.id, rangeStart: weekStart, rangeEnd: weekEnd, persist: false);
      for (final o in result.occurrences) {
        weekShifts.add((jobId: job.id, occ: o));
        if (o.shiftDate == todayIso) todayShifts.add((jobId: job.id, occ: o));
      }
    }
    weekShifts.sort((a, b) => a.occ.startDateTimeUtc.compareTo(b.occ.startDateTimeUtc));

    final inProgress = weekShifts
        .where((s) =>
            DateTime.parse(s.occ.startDateTimeUtc).isBefore(now) &&
            DateTime.parse(s.occ.endDateTimeUtc).isAfter(now))
        .toList();
    final upcoming = weekShifts
        .where((s) => DateTime.parse(s.occ.startDateTimeUtc).isAfter(now))
        .toList();
    final next = upcoming.isNotEmpty ? upcoming.first : null;
    final weekHours = service.sumHours(weekShifts.map((s) => s.occ));

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: jobs.isEmpty
          ? const Center(child: Text('No jobs yet — create one first.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_longDate(localNow),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (inProgress.isNotEmpty) ...[
                  _heroCard(
                    context,
                    icon: Icons.work,
                    title: 'Working now',
                    subtitle: _describe(inProgress.first, now),
                  ),
                  const SizedBox(height: 8),
                ],
                if (next != null) ...[
                  _heroCard(
                    context,
                    icon: Icons.schedule,
                    title: 'Next shift',
                    subtitle: _describe(next, now),
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 8),
                  _restCard(context, next.occ, now),
                  const SizedBox(height: 8),
                ] else if (inProgress.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No shifts coming up in the next 7 days.',
                        style: TextStyle(color: Colors.blueGrey)),
                  ),
                const SizedBox(height: 12),
                Text('Today · ${todayShifts.length} shift${todayShifts.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                if (todayShifts.isEmpty)
                  const Text('No shifts today.',
                      style: TextStyle(color: Colors.blueGrey))
                else
                  for (final s in todayShifts)
                    _shiftTile(context, s.jobId, s.occ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text('Hours this week (Mon–Sun)'),
                    trailing: Text(
                        '${weekHours.toStringAsFixed(1)}h',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
                if (service.payEnabled) ...[
                  const SizedBox(height: 12),
                  Text('Income this week (Mon–Sun) · estimate',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final job in jobs) ..._incomeCard(context, job, weekStart, weekEnd),
                  ..._incomeTotalCard(context, jobs, weekStart, weekEnd),
                ],
              ],
            ),
    );
  }

  /// RC plan §B3 — per-job income estimate card. Every amount ships with the
  /// disclaimer (D-C6: 'Estimate — not an official payroll figure'); when
  /// the config cannot price the week (no rule / multi-version) the card shows
  /// the reason instead of a guessed number. Tapping the card opens the full
  /// income breakdown screen (B3).
  List<Widget> _incomeCard(BuildContext context, JobRecord job,
      String weekStart, String weekEnd) {
    final est = widget.service.estimateIncome(
      jobId: job.id,
      rangeStart: weekStart,
      rangeEnd: weekEnd,
    );
    Widget card;
    if (est.available && est.hoursWorked == 0) return const []; // no shifts
    if (est.available) {
      card = Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(job.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text('USD \$${est.total.toStringAsFixed(2)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              for (final line in est.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Expanded(child: Text(line.label)),
                      Text('USD \$${line.amount.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              if (est.lines.isEmpty)
                Text('${est.hoursWorked.toStringAsFixed(1)}h worked',
                    style: const TextStyle(color: Colors.blueGrey)),
              const SizedBox(height: 6),
              Text(WeekIncomeEstimate.disclaimer,
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
      );
    } else {
      // Unavailable — show the reason verbatim with the disclaimer, never a 0.
      card = Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(est.unavailableReason ?? 'Unable to calculate.',
                  style: const TextStyle(color: Colors.blueGrey)),
              const SizedBox(height: 4),
              Text(WeekIncomeEstimate.disclaimer,
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
      );
    }
    return [
      InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => IncomeBreakdownScreen(
              service: widget.service, jobId: job.id),
        )),
        child: card,
      ),
      const SizedBox(height: 8),
    ];
  }

  /// RC plan §B7 — multi-job weekly total. Only AVAILABLE jobs contribute;
  /// the card states plainly that excluded jobs could not be calculated — a
  /// missing rule is NEVER silently turned into a $0 in the sum.
  List<Widget> _incomeTotalCard(BuildContext context, List<JobRecord> jobs,
      String weekStart, String weekEnd) {
    var availableTotal = 0.0;
    var unavailableCount = 0;
    var pricedJobs = 0;
    for (final job in jobs) {
      final est = widget.service.estimateIncome(
        jobId: job.id,
        rangeStart: weekStart,
        rangeEnd: weekEnd,
      );
      if (est.available && est.hoursWorked > 0) {
        availableTotal += est.total;
        pricedJobs++;
      } else if (!est.available) {
        unavailableCount++;
      }
    }
    if (pricedJobs == 0 && unavailableCount == 0) return const [];
    final excludeNote = unavailableCount > 0
        ? 'Total excludes $unavailableCount job(s) that could not be '
            'calculated.'
        : null;
    return [
      Card(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('All jobs · available total',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text('USD \$${availableTotal.toStringAsFixed(2)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              if (excludeNote != null) ...[
                const SizedBox(height: 4),
                Text(excludeNote,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.blueGrey)),
              ],
              const SizedBox(height: 6),
              Text(WeekIncomeEstimate.disclaimer,
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  // -- pieces ---------------------------------------------------------------

  Widget _heroCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      Color color = Colors.green}) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _restCard(BuildContext context, ShiftOccurrence nextOcc, DateTime now) {
    final gapMin =
        DateTime.parse(nextOcc.startDateTimeUtc).difference(now).inMinutes;
    if (gapMin <= 0) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.self_improvement, color: Colors.teal),
        title: Text('Rest before next shift: ${_fmtMinutes(gapMin)}'),
        subtitle: Text('INVARIANT-002 — rest is real elapsed time from UTC, '
            'never a local-clock guess.'),
      ),
    );
  }

  Widget _shiftTile(BuildContext context, String jobId, ShiftOccurrence o) {
    final wall = widget.service.localWallTime(o);
    final job = widget.service.jobs().firstWhere((j) => j.id == jobId);
    final templates = {for (final t in widget.service.templates(jobId)) t.id: t};
    final template = templates[o.templateId];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          radius: 10,
          backgroundColor: colorFromHex(template?.color ?? '#78909C'),
        ),
        title: Text(wall == null
            ? '${o.templateId}'
            : '${wall.start}–${wall.end} · ${template?.name ?? o.templateId}'),
        subtitle: Text('${job.name} · ${o.timezone}'),
        onTap: () async {
          final changed = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => OccurrenceSheet(
              service: widget.service,
              jobId: jobId,
              occurrence: o,
            ),
          );
          if (changed == true && mounted) {
            setState(() {});
            _resyncReminders(); // roster changed — reminder must follow
          }
        },
      ),
    );
  }

  // -- helpers --------------------------------------------------------------

  String _describe(({String jobId, ShiftOccurrence occ}) s, DateTime now) {
    final o = s.occ;
    final wall = widget.service.localWallTime(o);
    final jobName = widget.service
        .jobs()
        .firstWhere((j) => j.id == s.jobId)
        .name;
    final startUtc = DateTime.parse(o.startDateTimeUtc);
    final time = wall == null ? '' : '${wall.date} ${wall.start}–${wall.end}';
    if (startUtc.isBefore(now)) {
      final left = DateTime.parse(o.endDateTimeUtc).difference(now).inMinutes;
      return '$time · $jobName · ends in ${_fmtMinutes(left)}';
    }
    final inMin = startUtc.difference(now).inMinutes;
    return '$time · $jobName · starts in ${_fmtMinutes(inMin)}';
  }

  String _fmtMinutes(int total) {
    if (total < 1) return '<1m';
    final h = total ~/ 60;
    final m = total % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _longDate(DateTime now) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
  }
}
