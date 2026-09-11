// =============================================================================
// Job detail (M1) — the job's shift templates and shift patterns, plus the
// two actions the DoD flow needs: build a pattern and open the week calendar.
// Templates carry time/UI semantics ONLY (INVARIANT-005): name/code/color/
// start/end/break — there is deliberately no pay field anywhere in this form.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/app/color.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/calendar/month_calendar_screen.dart';
import 'package:shiftease/features/export/ics_export.dart';
import 'package:shiftease/features/export/ics_saver.dart';
import 'package:shiftease/features/calendar/week_calendar_screen.dart';
import 'package:shiftease/features/common/write_guard.dart';
import 'package:shiftease/features/import/import_screen.dart';
import 'package:shiftease/features/pattern_builder/pattern_builder_screen.dart';
import 'package:shiftease/features/pay/pay_rule_edit_dialog.dart';
import 'package:shiftease/features/templates/template_edit_dialog.dart';

class JobDetailScreen extends StatefulWidget {
  final ScheduleService service;
  final String jobId;
  const JobDetailScreen({super.key, required this.service, required this.jobId});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final job = service.jobs().firstWhere((j) => j.id == widget.jobId);
    final templates = service.templates(widget.jobId);
    final patterns = service.patterns(widget.jobId);

    return Scaffold(
      appBar: AppBar(title: Text(job.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Timezone: ${job.defaultTimezone}',
              style: Theme.of(context).textTheme.bodyMedium),
          if (service.payEnabled) ...[_payRuleSection(context, job.id)],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.calendar_view_week),
                label: const Text('View week'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WeekCalendarScreen(
                      service: service, jobId: widget.jobId),
                )),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: const Text('View month'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MonthCalendarScreen(
                      service: service, jobId: widget.jobId),
                )),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.route),
                label: const Text('New pattern'),
                onPressed: templates.isEmpty
                    ? null
                    : () => _openPatternBuilder(context, null, null),
              ),
              if (service.importEnabled)
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_present),
                  label: const Text('Import roster'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ImportScreen(
                        service: service, jobId: widget.jobId),
                  )),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.ios_share),
                label: const Text('Export week (.ics)'),
                onPressed: () => _exportWeek(context),
              ),
            ],
          ),
          if (templates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Add at least one shift template before building a pattern.',
                style: TextStyle(color: Colors.blueGrey),
              ),
            ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Shift templates', 'Add', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => TemplateEditDialog(
                  service: service, jobId: widget.jobId),
            );
            if (ok == true && mounted) setState(() {});
          }),
          if (templates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No templates yet.', style: TextStyle(fontStyle: FontStyle.italic)),
            )
          else
            for (final t in templates)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 10,
                  backgroundColor: colorFromHex(t.color),
                ),
                title: Text('${t.name} (${t.startTime}–${t.endTime})'),
                subtitle: Text(
                    '${t.code}${t.breakDurationMinutes > 0 ? ' · ${t.breakDurationMinutes} min break' : ''}'),
              ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Shift patterns', null, null),
          if (patterns.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No patterns yet — build one to project shifts.',
                  style: TextStyle(fontStyle: FontStyle.italic)),
            )
          else
            for (final p in patterns)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                subtitle: Text(
                    'From ${p.effectiveFrom}${p.effectiveUntil == null ? ' (active)' : ' until ${p.effectiveUntil}'} · '
                    'cycle ${p.cycleLengthDays}d'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _openPatternSheet(context, p),
              ),
        ],
      ),
    );
  }

  /// Gate C B2 — basic pay-rule card: shows the rule active today and lets
  /// the user set/edit it. Income amounts in the app are always labelled as
  /// estimates (D-C6) — a rule here only makes the estimate possible.
  Widget _payRuleSection(BuildContext context, String jobId) {
    final today = DateTime.now();
    final todayIso = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final rules = widget.service.payRules(jobId);
    final active =
        widget.service.activePayRule(jobId: jobId, date: todayIso);
    final ruleText = active == null
        ? 'No pay rule yet — income cannot be estimated.'
        : 'Active from ${active.effectiveFrom}: '
            '\$${active.baseHourlyRate.toStringAsFixed(2)}/h'
            '${active.differentials.isNotEmpty ? ' · ' + active.differentials.map((d) => '${d.type.name} +${d.value.toStringAsFixed(0)}%').join(', ') : ''}'
            '${active.overtimeRules.isNotEmpty ? ' · OT ${active.overtimeRules.map((r) => '>${r.thresholdHours.toStringAsFixed(0)}h x${r.multiplier.toStringAsFixed(1)}').join(', ')}' : ''}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: const Text('Pay rule'),
        subtitle: Text(ruleText),
        isThreeLine: rules.isEmpty ? false : true,
        trailing: TextButton(
          onPressed: () async {
            final saved = await showDialog<bool>(
              context: context,
              builder: (_) => PayRuleEditDialog(
                  service: widget.service, jobId: jobId),
            );
            if (saved == true && mounted) setState(() {});
          },
          child: Text(active == null ? 'Set' : 'Edit'),
        ),
      ),
    );
  }

  /// Gate C B3 — export the CURRENT week (Mon..Sun) of this job to an offline
  /// .ics file. Every resolved occurrence becomes a UTC VEVENT; the file is
  /// written locally only — sharing it (if the user chooses) is outside the
  /// app (D-C7).
  Future<void> _exportWeek(BuildContext context) async {
    final service = widget.service;
    final now = DateTime.now();
    final mon = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final from = iso(mon);
    final to = iso(mon.add(const Duration(days: 6)));
    final job = service.jobs().firstWhere((j) => j.id == widget.jobId);
    final templates = {for (final t in service.templates(widget.jobId)) t.id: t};

    // RC plan §A1 — export is a write path: a render or file-save exception
    // must surface as a snackbar, never crash the job screen.
    final exportError = await runWriteAsync(() async {
      final rendered = service.renderJob(
          jobId: widget.jobId, rangeStart: from, rangeEnd: to, persist: false);
      final events = [
        for (final o in rendered.occurrences)
          IcsEvent(
            occurrence: o,
            jobName: job.name,
            templateName: templates[o.templateId]?.name ?? '',
          ),
      ];
      final ics = buildIcsCalendar(
        calendarName: '${job.name} week $from',
        events: events,
        generatedAtUtc: DateTime.now().toUtc().toIso8601String(),
      );
      final fileName =
          'shiftease_${widget.jobId}_$from.ics'.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
      final path = await saveIcsFile(fileName: fileName, content: ics);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Export failed — could not write the .ics file offline.'
            : 'Exported ${events.length} shift(s) to $path'),
      ));
    });
    if (exportError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $exportError')));
    }
  }

  /// Pattern tap → detail sheet with the roster-change (re-version) action.
  Future<void> _openPatternSheet(BuildContext context, ShiftPattern p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cycle: ${p.cycleLengthDays}d · anchor: ${p.anchorDate}'
                ' · type: ${p.type}'),
            const SizedBox(height: 4),
            Text('Effective: ${p.effectiveFrom}'
                '${p.effectiveUntil == null ? ' → now' : ' → ${p.effectiveUntil}'}'),
            const SizedBox(height: 4),
            Text('Work slots: '
                '${p.sequence.whereType<String>().length}/${p.sequence.length}'),
            const SizedBox(height: 12),
            const Text('“Change my roster from a date” closes this version and '
                'starts a new one — past shifts never change (INVARIANT-001), '
                'the cycle phase is kept (D9).',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.content_copy),
            label: const Text('New version from date…'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Pick the effective date (strictly after the version being closed).
    final earliest =
        DateTime.parse(p.effectiveFrom).add(const Duration(days: 1));
    final now = DateTime.now();
    final initial = now.isAfter(earliest) ? now : earliest;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    final from = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    await _openPatternBuilder(context, p, from);
  }

  Future<void> _openPatternBuilder(
      BuildContext context, ShiftPattern? existing, String? newEffectiveFrom) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PatternBuilderScreen(
        service: widget.service,
        jobId: widget.jobId,
        existing: existing,
        newEffectiveFrom: newEffectiveFrom,
      ),
    ));
    if (changed == true && mounted) setState(() {});
  }

  Widget _sectionHeader(BuildContext context, String title, String? actionLabel,
      VoidCallback? onAction) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
