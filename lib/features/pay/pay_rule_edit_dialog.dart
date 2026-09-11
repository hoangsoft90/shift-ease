// =============================================================================
// Pay rule editor (Gate C B2 — minimum usable): base hourly rate + NIGHT and
// WEEKEND percent differentials (ALL hours of the shift) + ONE weekly
// overtime rule (threshold hours × multiplier). Saved as a VERSIONED PayRule
// with an effectiveFrom date (INVARIANT-006 — a later version never rewrites
// past earnings; a rule is resolved by the date it is active on).
//
// This is deliberately NOT a full payroll product: no tax/net, no multi-
// country library, no hazard/callback editor. PayRule children that are not
// exposed here (day/shift OT, window-scoped differentials) still round-trip
// through the repo when loaded from a saved rule.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/core/money/money_types.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/pay/pay_presets.dart';

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class PayRuleEditDialog extends StatefulWidget {
  final ScheduleService service;
  final String jobId;

  const PayRuleEditDialog({
    super.key,
    required this.service,
    required this.jobId,
  });

  @override
  State<PayRuleEditDialog> createState() => _PayRuleEditDialogState();
}

class _PayRuleEditDialogState extends State<PayRuleEditDialog> {
  late final TextEditingController _base = TextEditingController();
  late final TextEditingController _night = TextEditingController();
  late final TextEditingController _weekend = TextEditingController();
  late final TextEditingController _otThreshold = TextEditingController(text: '40');
  late final TextEditingController _otMultiplier = TextEditingController(text: '1.5');
  DateTime _effectiveFrom = DateTime.now();
  String? _error;
  PayPreset? _activePreset;
  /// Id of the version being edited — in-memory ONLY. Never re-saved when
  /// the payload changed (a change mints a new id via the domain API).
  String? _existingRuleId;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the rule active today. Editing an EXISTING version keeps
    // that version's effectiveFrom as the default: an unchanged Save is an
    // idempotent no-op (Gate A §A6 surfaces in the UI). A NEW version is an
    // explicit act — the user picks a later "From" date.
    final active = widget.service
        .activePayRule(jobId: widget.jobId, date: _isoDate(_effectiveFrom));
    if (active != null) {
      _existingRuleId = active.id;
      _effectiveFrom = DateTime.parse(active.effectiveFrom);
      _base.text = active.baseHourlyRate.toStringAsFixed(2);
      for (final d in active.differentials) {
        if (d.type == DifferentialType.night &&
            d.mode == DifferentialMode.percent) {
          _night.text = d.value.toStringAsFixed(0);
        }
        if (d.type == DifferentialType.weekend &&
            d.mode == DifferentialMode.percent) {
          _weekend.text = d.value.toStringAsFixed(0);
        }
      }
      if (active.overtimeRules.isNotEmpty) {
        final r = active.overtimeRules.first;
        _otThreshold.text = r.thresholdHours.toStringAsFixed(0);
        _otMultiplier.text = r.multiplier.toStringAsFixed(2);
      }
    }
  }

  /// RC plan §B5 — apply a library preset as a STARTING point: prefill the
  /// fields; the user reviews/edits and explicitly saves (nothing is saved
  /// implicitly). The verify-against-your-policy disclaimer is shown.
  void _applyPreset(PayPreset p) {
    setState(() {
      _activePreset = p;
      _base.text = p.baseRate.toStringAsFixed(2);
      _night.text = p.nightPercent.toStringAsFixed(0);
      _weekend.text = p.weekendPercent.toStringAsFixed(0);
      _otThreshold.text = p.otThresholdHours.toStringAsFixed(1);
      _otMultiplier.text = p.otMultiplier.toStringAsFixed(2);
      _error = null;
    });
  }

  @override
  void dispose() {
    _base.dispose();
    _night.dispose();
    _weekend.dispose();
    _otThreshold.dispose();
    _otMultiplier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double? numOf(TextEditingController c, String label) {
      final v = double.tryParse(c.text.trim());
      if (v == null || v < 0) {
        _error = '$label must be a number >= 0.';
        return null;
      }
      return v;
    }

    return AlertDialog(
      title: const Text('Pay rule (estimate)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Versioned from a date — past earnings are never re-priced '
                '(INVARIANT-006).', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            // RC plan §B5 — preset template library. A preset ONLY prefills;
            // the actual save is the user's explicit 'Save rule' press.
            DropdownButtonFormField<String>(
              key: const ValueKey('pay-preset'),
              initialValue: null,
              decoration: const InputDecoration(
                  labelText: 'Preset template (starting point)',
                  isDense: true),
              items: [
                for (final p in payPresets)
                  DropdownMenuItem<String>(value: p.name, child: Text(p.name)),
              ],
              onChanged: (name) {
                final p =
                    payPresets.firstWhere((x) => x.name == name);
                _applyPreset(p);
              },
            ),
            if (_activePreset != null) ...[
              const SizedBox(height: 4),
              Text(_activePreset!.note,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.blueGrey)),
              Text(PayPreset.disclaimer,
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pay-base'),
                    controller: _base,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Base hourly rate (\$)'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _effectiveFrom,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2040),
                    );
                    if (picked != null) {
                      setState(() {
                        _effectiveFrom =
                            DateTime(picked.year, picked.month, picked.day);
                      });
                    }
                  },
                  child: Text('From: ${_isoDate(_effectiveFrom)}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pay-night'),
                    controller: _night,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Night diff %'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('pay-weekend'),
                    controller: _weekend,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Weekend diff %'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pay-ot-threshold'),
                    controller: _otThreshold,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'OT threshold (h/week)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('pay-ot-multiplier'),
                    controller: _otMultiplier,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'OT multiplier'),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pay-save'),
          onPressed: () {
            final base = numOf(_base, 'Base hourly rate');
            if (base == null) {
              setState(() {});
              return;
            }
            final night = double.tryParse(_night.text.trim()) ?? 0;
            final weekend = double.tryParse(_weekend.text.trim()) ?? 0;
            final otT = double.tryParse(_otThreshold.text.trim());
            final otM = double.tryParse(_otMultiplier.text.trim());
            // Never silently coerce an input (Correctness Contract): a
            // multiplier below 1 would PAY LESS for overtime — refuse loudly
            // instead of quietly substituting 1.5.
            if (otM != null && otM < 1) {
              setState(() => _error =
                  'OT multiplier must be >= 1 (e.g. 1.5). Nothing was saved.');
              return;
            }
            final differentials = <PayDifferential>[
              if (night > 0)
                PayDifferential(
                  type: DifferentialType.night,
                  mode: DifferentialMode.percent,
                  value: night,
                ),
              if (weekend > 0)
                PayDifferential(
                  type: DifferentialType.weekend,
                  mode: DifferentialMode.percent,
                  value: weekend,
                ),
            ];
            final overtimeRules = <OvertimeRule>[
              if (otT != null && otT > 0)
                OvertimeRule(
                  thresholdHours: otT,
                  period: OvertimePeriod.week,
                  multiplier: otM ?? 1.5,
                ),
            ];
            final from = _isoDate(_effectiveFrom);
            // plan_payrule_version_ux.md D2/D4: Save goes through the
            // smart-versioning use-case — an edited rule transparently
            // becomes a NEW version (old one closed); an unchanged save is
            // a no-op. Raw persistence errors (A6 etc.) never surface.
            try {
              final outcome = widget.service.savePayRuleFromEditor(
                rule: PayRule(
                  // The id is minted by the domain for changed payloads;
                  // this id field is only used for first-create / no-op.
                  id: _existingRuleId ??
                      slugId('payrule', [widget.jobId, from]),
                  jobId: widget.jobId,
                  baseHourlyRate: base,
                  differentials: differentials,
                  overtimeRules: overtimeRules,
                  effectiveFrom: from,
                ),
                existingId: _existingRuleId,
              );
              if (!mounted) return;
              // Capture the messenger BEFORE pop (the dialog context is
              // torn down right after) — success copy: one honest line.
              // 'no changes' is silent success (no version spam). D5: a
              // preset only prefilled the form; this save is the explicit act.
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop(true);
              if (outcome == 'versioned' || outcome == 'created') {
                messenger.showSnackBar(SnackBar(
                    content: Text('Pay rule saved. Applies from $from.')));
              }
            } on ArgumentError catch (e) {
              if (!mounted) return;
              setState(() => _error = e.message?.toString() ??
                  'Could not save the pay rule. Try again.');
            } on StateError {
              // Belt-and-braces: A6 StateError is an Error (not Exception)
              // and would otherwise escape this handler and crash. The
              // domain translates its own known cases; anything here is a
              // persistence-level surprise — generic copy, detail to Sentry.
              if (!mounted) return;
              setState(() => _error =
                  'Could not save the pay rule. Try again.');
            } on Exception {
              if (!mounted) return;
              // Unexpected (DB etc.): short, actionable — no internals.
              // (D-P9.x honesty: detail stays available for Sentry.)
              setState(() => _error =
                  'Could not save the pay rule. Try again.');
            }
          },
          child: const Text('Save rule'),
        ),
      ],
    );
  }
}
