// =============================================================================
// Gate C B3 — ICS export offline (pure generator). No server, no network:
// the output is self-contained vCalendar 2.0 text with resolved UTC instants.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/features/export/ics_export.dart';

void main() {
  test('renders every resolved occurrence as a UTC VEVENT with job context',
      () {
    final ics = buildIcsCalendar(
      calendarName: 'Hospital week',
      events: [
        IcsEvent(
          occurrence: ShiftOccurrence(
            id: 'occ-cand-1',
            patternId: '',
            shiftDate: '2026-09-07',
            templateId: 'st-day',
            startDateTimeUtc: '2026-09-07T11:00:00.000Z',
            endDateTimeUtc: '2026-09-07T23:00:00.000Z',
            timezone: 'America/New_York',
            source: OccurrenceSource.created,
          ),
          jobName: 'Hospital',
          templateName: 'Day',
        ),
        IcsEvent(
          occurrence: ShiftOccurrence(
            id: 'occ-2026-09-08',
            patternId: '',
            shiftDate: '2026-09-08',
            templateId: '',
            startDateTimeUtc: '2026-09-08T11:00:00.000Z',
            endDateTimeUtc: '2026-09-08T23:00:00.000Z',
            timezone: 'UTC',
            source: OccurrenceSource.baseline,
          ),
          jobName: 'Hospital',
          templateName: '',
        ),
      ],
      generatedAtUtc: '2026-09-06T12:00:00.000Z',
    );

    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics, contains('VERSION:2.0'));
    expect(ics, contains('X-WR-CALNAME:Hospital week'));
    expect(RegExp('BEGIN:VEVENT').allMatches(ics).length, 2);

    // First event: UTC instants, UID, summary, job + timezone in description.
    expect(ics, contains('UID:occ-cand-1@shiftease'));
    expect(ics, contains('DTSTART:20260907T110000Z'));
    expect(ics, contains('DTEND:20260907T230000Z'));
    expect(ics, contains('SUMMARY:Day'));
    expect(ics, contains('Shift at Hospital (America/New_York)'));

    // Template-less row falls back to a date summary.
    expect(ics, contains('SUMMARY:Shift on 2026-09-08'));
    expect(ics, contains('DTSTAMP:20260906T120000Z'));

    // Offline-only: nothing references a URL/server/webcal endpoint.
    expect(ics.toLowerCase(), isNot(contains('http')));
    expect(ics.toLowerCase(), isNot(contains('webcal')));
  });

  test('CSV-injection chars in names are escaped, not interpreted', () {
    final ics = buildIcsCalendar(
      calendarName: 'Semi;Colon Hospital, #1',
      events: [
        IcsEvent(
          occurrence: ShiftOccurrence(
            id: 'occ-a',
            patternId: '',
            shiftDate: '2026-09-07',
            templateId: 'st',
            startDateTimeUtc: '2026-09-07T11:00:00.000Z',
            endDateTimeUtc: '2026-09-07T23:00:00.000Z',
            timezone: 'UTC',
            source: OccurrenceSource.baseline,
          ),
          jobName: 'A',
          templateName: 'Night, pay',
        ),
      ],
      generatedAtUtc: '2026-09-06T12:00:00.000Z',
    );
    expect(ics, contains('X-WR-CALNAME:Semi\\;Colon Hospital\\, #1'));
    expect(ics, contains('SUMMARY:Night\\, pay'));
  });
}
