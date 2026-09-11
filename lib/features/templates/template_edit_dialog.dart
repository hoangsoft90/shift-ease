// =============================================================================
// Shift Template edit dialog (M1).
// INVARIANT-005: a template carries time/UI semantics only — name, code,
// color, start/end, break. There is NO pay field here, by design.
// Start/end are civil "HH:mm" — overnight is expressed by endHour < startHour
// and resolved to UTC by core/time (INVARIANT-002). The form validates the
// clock format strictly; invalid input never reaches the engine.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/features/common/write_guard.dart';

const List<Color> _palette = [
  Color(0xFF1565C0),
  Color(0xFF00838F),
  Color(0xFF2E7D32),
  Color(0xFF6A1B9A),
  Color(0xFFE65100),
  Color(0xFFC62828),
  Color(0xFF283593),
  Color(0xFF00695C),
];

final RegExp _clock = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Hex helper kept local (single import site); matches app/color semantics.
String _hex(Color c) {
  final v = c.toARGB32();
  return '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class TemplateEditDialog extends StatefulWidget {
  final ScheduleService service;
  final String jobId;
  const TemplateEditDialog({super.key, required this.service, required this.jobId});

  @override
  State<TemplateEditDialog> createState() => _TemplateEditDialogState();
}

class _TemplateEditDialogState extends State<TemplateEditDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _start = TextEditingController(text: '07:00');
  final _end = TextEditingController(text: '19:00');
  final _break = TextEditingController(text: '0');
  Color _color = _palette.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _start.dispose();
    _end.dispose();
    _break.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New shift template'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Name', hintText: 'e.g. Day shift'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                decoration: const InputDecoration(
                    labelText: 'Code (short)', hintText: 'e.g. D'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _start,
                      decoration: const InputDecoration(labelText: 'Start (HH:mm)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _end,
                      decoration: const InputDecoration(labelText: 'End (HH:mm)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _break,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Break (minutes)', suffixText: 'min'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final c in _palette)
                    InkWell(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 2,
                            color: c == _color
                                ? Colors.black54
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final name = _name.text.trim();
    final code = _code.text.trim().isEmpty ? name : _code.text.trim();
    final start = _start.text.trim();
    final end = _end.text.trim();
    final brk = int.tryParse(_break.text.trim());

    if (name.isEmpty) return setState(() => _error = 'Name is required.');
    if (!_clock.hasMatch(start) || !_clock.hasMatch(end)) {
      return setState(
          () => _error = 'Start/end must be HH:mm (e.g. 07:00, 22:00).');
    }
    if (brk == null || brk < 0 || brk > 24 * 60) {
      return setState(
          () => _error = 'Break must be a whole number of minutes (0–1440).');
    }
    if (start == end) {
      return setState(() => _error = 'Start and end must differ.');
    }

    final t = ShiftTemplate(
      id: slugId('tpl', [name, code, start, end]),
      jobId: widget.jobId,
      name: name,
      code: code,
      color: _hex(_color),
      startTime: start,
      endTime: end,
      breakDurationMinutes: brk,
    );
    final error = runWrite(
        () => widget.service.saveTemplate(jobId: widget.jobId, template: t));
    if (error != null) {
      // RC plan §A1 — a template-save failure must show, never crash; the
      // dialog stays open so the user can retry (nothing was written).
      return setState(() => _error = error);
    }
    Navigator.of(context).pop(true);
  }
}
