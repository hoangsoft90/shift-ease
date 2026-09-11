// =============================================================================
// ICS export (Gate C B3 / D-C7) — OFFLINE-ONLY vCalendar 2.0 generation.
//
// No server, no dynamic Webcal. Each RESOLVED occurrence becomes one VEVENT
// with DTSTART/DTEND in UTC (INVARIANT-002: instants are already resolved by
// core/time — the exporter never re-derives local times). The export carries
// the job + the occurrence's own timezone so a calendar app that needs a
// TZID can still interpret it; the timestamps themselves stay unambiguous UTC.
// =============================================================================

import 'package:shiftease/core/pattern/pattern_types.dart'
    show ShiftOccurrence;

/// One exported event (job context is attached for the SUMMARY line).
class IcsEvent {
  final ShiftOccurrence occurrence;
  final String jobName;
  final String templateName; // '' when the row has no matching template

  const IcsEvent({
    required this.occurrence,
    required this.jobName,
    required this.templateName,
  });
}

/// vCalendar 2.0 text. Line endings are CRLF per RFC 5545. Folding is not
/// applied (none of our lines exceed 75 octets in practice); content is
/// escaped. Pure — no I/O, no network.
String buildIcsCalendar({
  required String calendarName,
  required List<IcsEvent> events,
  required String generatedAtUtc, // ISO datetime for DTSTAMP
}) {
  final buffer = StringBuffer()
    ..writeln('BEGIN:VCALENDAR')
    ..writeln('VERSION:2.0')
    ..writeln('PRODID:-//ShiftEase//Offline Export//EN')
    ..writeln('CALSCALE:GREGORIAN')
    ..writeln('X-WR-CALNAME:${_escape(calendarName)}')
    ..writeln('X-WR-TIMEZONE:UTC');
  final stamp = _icsUtc(generatedAtUtc);
  for (final e in events) {
    final o = e.occurrence;
    final summary =
        e.templateName.isEmpty ? 'Shift on ${o.shiftDate}' : e.templateName;
    buffer
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:${_uidFor(o.id)}@shiftease')
      ..writeln('DTSTAMP:$stamp')
      ..writeln('DTSTART:${_icsUtc(o.startDateTimeUtc)}')
      ..writeln('DTEND:${_icsUtc(o.endDateTimeUtc)}')
      ..writeln('SUMMARY:${_escape(summary)}')
      ..writeln('DESCRIPTION:Shift at ${_escape(e.jobName)} '
          '(${_escape(o.timezone)}) — exported offline from ShiftEase')
      ..writeln('END:VEVENT');
  }
  buffer.writeln('END:VCALENDAR');
  // RFC 5545 mandates CRLF line endings (StringBuffer.writeln uses \n).
  return buffer.toString().replaceAll('\n', '\r\n');
}

/// "2026-09-07T11:00:00.000Z" -> "20260907T110000Z".
String _icsUtc(String iso) {
  final d = DateTime.parse(iso).toUtc();
  String p(int n, int w) => n.toString().padLeft(w, '0');
  return '${p(d.year, 4)}${p(d.month, 2)}${p(d.day, 2)}T'
      '${p(d.hour, 2)}${p(d.minute, 2)}${p(d.second, 2)}Z';
}

String _uidFor(String occurrenceId) {
  final clean = occurrenceId.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
  return clean.isEmpty ? 'occurrence' : clean;
}

String _escape(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\n', '\\n');
