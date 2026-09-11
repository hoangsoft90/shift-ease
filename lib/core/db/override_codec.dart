// =============================================================================
// Override <-> JSON codec (Gate 3 persistence)
// =============================================================================
//
// Override rows store the operation's typed payload as canonical JSON so the
// engine's applyOverride can be REPLAYED byte-for-byte after a restart. Only
// the payload for the row's operation is encoded; decoding requires the
// operation (stored in its own column) to pick the right shape.
//
// NEVER used by core/pattern — the engine stays JSON-free; this codec lives
// only at the persistence boundary (mirrors how core/time and core/money
// libraries are JSON-free while the golden test runners parse JSON).
// =============================================================================

import 'dart:convert';

import 'package:shiftease/core/pattern/pattern_types.dart';

/// Canonical payload map for an override's own operation.
Map<String, dynamic> payloadToJson(Override o) {
  switch (o.operation) {
    case OverrideOperation.create:
      final p = o.createPayload!;
      return {
        'date': p.date,
        'templateId': p.templateId,
        'startTime': p.startTime,
        'endTime': p.endTime,
        'timezone': p.timezone,
        // RC plan §D — explicit DST interpretation (null when unambiguous).
        if (p.startOffsetMinutes != null)
          'startOffsetMinutes': p.startOffsetMinutes,
        if (p.endOffsetMinutes != null) 'endOffsetMinutes': p.endOffsetMinutes,
      };
    case OverrideOperation.update:
      final p = o.updatePayload!;
      return {
        if (p.startTime != null) 'startTime': p.startTime,
        if (p.endTime != null) 'endTime': p.endTime,
        if (p.templateId != null) 'templateId': p.templateId,
        if (p.startOffsetMinutes != null)
          'startOffsetMinutes': p.startOffsetMinutes,
        if (p.endOffsetMinutes != null) 'endOffsetMinutes': p.endOffsetMinutes,
      };
    case OverrideOperation.delete:
      return const {};
    case OverrideOperation.replace:
      final p = o.replacePayload!;
      return {
        'newTemplateId': p.newTemplateId,
        if (p.overrideTime != null)
          'overrideTime': {
            'startTime': p.overrideTime!.startTime,
            'endTime': p.overrideTime!.endTime,
          },
      };
    case OverrideOperation.split:
      final p = o.splitPayload!;
      return {
        'parts': [
          for (final part in p.parts)
            {
              'startTime': part.startTime,
              'endTime': part.endTime,
              'templateId': part.templateId,
              'dateOffsetDays': part.dateOffsetDays,
            }
        ],
      };
    case OverrideOperation.swap:
      return const {};
  }
}

/// Rebuild a typed Override from its DB row.
Override overrideFromRow({
  required String id,
  required String occurrenceId,
  required OverrideOperation operation,
  required String payloadJson,
  String? swapWithOccurrenceId,
  required String createdAt,
  String? reasonName,
}) {
  final map = (jsonDecode(payloadJson) as Map).cast<String, dynamic>();
  CreatePayload? create;
  UpdatePayload? update;
  ReplacePayload? replace;
  SplitPayload? split;
  switch (operation) {
    case OverrideOperation.create:
      create = CreatePayload(
        date: map['date'] as String,
        templateId: map['templateId'] as String,
        startTime: map['startTime'] as String,
        endTime: map['endTime'] as String,
        timezone: map['timezone'] as String,
        startOffsetMinutes: map['startOffsetMinutes'] as int?,
        endOffsetMinutes: map['endOffsetMinutes'] as int?,
      );
    case OverrideOperation.update:
      update = UpdatePayload(
        startTime: map['startTime'] as String?,
        endTime: map['endTime'] as String?,
        templateId: map['templateId'] as String?,
        startOffsetMinutes: map['startOffsetMinutes'] as int?,
        endOffsetMinutes: map['endOffsetMinutes'] as int?,
      );
    case OverrideOperation.delete:
      break;
    case OverrideOperation.replace:
      final ot = map['overrideTime'] as Map?;
      replace = ReplacePayload(
        newTemplateId: map['newTemplateId'] as String,
        overrideTime: ot == null
            ? null
            : ReplaceTime(
                startTime: ot['startTime'] as String,
                endTime: ot['endTime'] as String,
              ),
      );
    case OverrideOperation.split:
      split = SplitPayload(parts: [
        for (final part in (map['parts'] as List).cast<Map>())
          SplitPart(
            startTime: part['startTime'] as String,
            endTime: part['endTime'] as String,
            templateId: part['templateId'] as String,
            dateOffsetDays: part['dateOffsetDays'] as int,
          ),
      ]);
    case OverrideOperation.swap:
      break;
  }
  return Override(
    id: id,
    occurrenceId: occurrenceId,
    operation: operation,
    createPayload: create,
    updatePayload: update,
    replacePayload: replace,
    splitPayload: split,
    swapWithOccurrenceId: swapWithOccurrenceId,
    createdAt: createdAt,
    reason: reasonName == null
        ? null
        : OverrideReason.values.firstWhere(
            (rs) => rs.name == reasonName,
            orElse: () => OverrideReason.custom),
  );
}
