// =============================================================================
// Jobs screen (M1) — list + create job. A job = name + IANA timezone.
// The timezone is validated against the tz database before anything is
// stored (INVALID_TIMEZONE must never reach the engine as a stored zone).
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/jobs/job_detail_screen.dart';
import 'package:shiftease/features/notifications/shift_reminder.dart';
import 'package:shiftease/features/settings/settings_screen.dart';
import 'package:shiftease/features/today/today_screen.dart';

class JobsScreen extends StatefulWidget {
  final ScheduleService service;
  const JobsScreen({super.key, required this.service});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  @override
  Widget build(BuildContext context) {
    final jobs = widget.service.jobs();
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShiftEase — Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Today',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TodayScreen(service: widget.service),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(
                service: widget.service,
                reminders: ShiftReminderScheduler(),
              ),
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createJob(context),
        icon: const Icon(Icons.add),
        label: const Text('New job'),
      ),
      body: jobs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.work_outline, size: 64, color: Colors.blueGrey),
                  SizedBox(height: 12),
                  Text('No jobs yet.'),
                  Text('Create a job to start building your schedule.',
                      textAlign: TextAlign.center),
                ],
              ),
            )
          : ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (context, i) {
                final job = jobs[i];
                return ListTile(
                  leading: const Icon(Icons.business_center),
                  title: Text(job.name),
                  subtitle: Text('Timezone: ${job.defaultTimezone}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => JobDetailScreen(
                        service: widget.service, jobId: job.id),
                  )),
                );
              },
            ),
    );
  }

  Future<void> _createJob(BuildContext context) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _JobDialog(service: widget.service),
    );
    if (id != null && mounted) {
      setState(() {});
    }
  }
}

class _JobDialog extends StatefulWidget {
  final ScheduleService service;
  const _JobDialog({required this.service});

  @override
  State<_JobDialog> createState() => _JobDialogState();
}

class _JobDialogState extends State<_JobDialog> {
  final _name = TextEditingController();
  late final _tz = TextEditingController(text: commonTimezones.first);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _tz.dispose();
    super.dispose();
  }

  String get _timezone => _tz.text.trim();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New job'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Job name',
                  hintText: 'e.g. St. Mary Hospital',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tz,
                decoration: InputDecoration(
                  labelText: 'Timezone (IANA)',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Quick pick:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final z in commonTimezones)
                    ActionChip(
                      label: Text(z),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _tz.text = z);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _save() {
    final name = _name.text.trim();
    final tzError = widget.service.validateTimezone(_timezone);
    if (tzError != null) {
      setState(() => _error = tzError);
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Job name must not be empty.');
      return;
    }
    try {
      final id = widget.service.createJob(name: name, timezone: _timezone);
      Navigator.of(context).pop(id);
    } on ArgumentError catch (e) {
      setState(() => _error = e.message);
    }
  }
}
