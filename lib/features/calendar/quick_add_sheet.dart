// =============================================================================
// Quick Add (M1b, D3) — bottom sheet for a chosen day. Each template of the
// job is one tappable tile: a tap CREATES the shift immediately with the
// template's default start/end times (no form — 1-tap). The trailing
// "Custom time…" tile opens the full form for the same day. Template tiles
// never require DST knowledge from the user: if the created shift cannot be
// resolved (NONEXISTENT/AMBIGUOUS) the engine reports an issue and the
// calendar banner explains why — nothing is silently guessed.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/app/color.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/common/write_guard.dart';
import 'package:shiftease/features/occurrence/override_actions.dart';
import 'package:shiftease/features/occurrence/occurrence_sheet.dart';

/// [customRequested] is set to true when the user taps "Custom time…" so the
/// caller can open the full [OccurrenceSheet] for the same day afterwards.
Future<bool?> showQuickAddSheet(
  BuildContext context, {
  required ScheduleService service,
  required String jobId,
  required String date,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    builder: (_) => QuickAddSheet(
      service: service,
      jobId: jobId,
      date: date,
    ),
  );
  return result;
}

class QuickAddSheet extends StatefulWidget {
  final ScheduleService service;
  final String jobId;
  final String date;
  const QuickAddSheet({
    super.key,
    required this.service,
    required this.jobId,
    required this.date,
  });

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final templates = service.templates(widget.jobId);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick add on ${widget.date}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('One tap = shift with the template\'s default times.',
                style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
            const SizedBox(height: 12),
            if (templates.isEmpty)
              const Text('This job has no templates yet.')
            else
              for (final t in templates)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 10,
                    backgroundColor: colorFromHex(t.color),
                  ),
                  title: Text('${t.name} (${t.startTime}–${t.endTime})'),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => _create(t.id, t.startTime, t.endTime),
                ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune),
              title: const Text('Custom time…'),
              onTap: () => Navigator.of(context).pop(false),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  void _create(String templateId, String start, String end) {
    String? error;
    try {
      error = createShiftOnDate(
        widget.service,
        jobId: widget.jobId,
        date: widget.date,
        templateId: templateId,
        start: start,
        end: end,
      );
    } catch (e) {
      // RC plan §A1 — a write exception must never escape an event handler.
      error = writeErrorMessage(e);
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(true);
  }
}
