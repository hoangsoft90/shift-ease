// =============================================================================
// Gate C B4 — shift reminder baseline (pure part): which upcoming shift to
// notify about and the exact fire time (start − 60 min), computed from stored
// UTC instants (INVARIANT-002). Plugin calls are guarded separately.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:shiftease/core/pattern/pattern_types.dart';
import 'package:shiftease/features/notifications/shift_reminder.dart';

ShiftOccurrence occ(String id, String startUtc, String endUtc) =>
    ShiftOccurrence(
      id: id,
      patternId: '',
      shiftDate: startUtc.substring(0, 10),
      templateId: 'st-day',
      startDateTimeUtc: startUtc,
      endDateTimeUtc: endUtc,
      timezone: 'UTC',
      source: OccurrenceSource.baseline,
    );

void main() {
  test('fires 60 minutes before the NEXT upcoming shift', () {
    final now = DateTime.utc(2026, 9, 6, 12, 0);
    final spec = nextReminderSpec([
      occ('past', '2026-09-06T11:00:00.000Z', '2026-09-06T23:00:00.000Z'),
      occ('next', '2026-09-07T07:00:00.000Z', '2026-09-07T19:00:00.000Z'),
    ], nowUtc: now);
    expect(spec, isNotNull);
    expect(spec!.occurrence.id, 'next');
    expect(spec.shiftStartUtc, DateTime.utc(2026, 9, 7, 7));
    expect(spec.fireAtUtc, DateTime.utc(2026, 9, 7, 6),
        reason: '60 minutes before start');
  });

  test('skips a shift already inside the lead window (past fire time)', () {
    final now = DateTime.utc(2026, 9, 7, 6, 30); // 30 min before 07:00
    final spec = nextReminderSpec([
      occ('soon', '2026-09-07T07:00:00.000Z', '2026-09-07T19:00:00.000Z'),
      occ('later', '2026-09-08T07:00:00.000Z', '2026-09-08T19:00:00.000Z'),
    ], nowUtc: now, leadMinutes: 60);
    expect(spec, isNotNull);
    expect(spec!.occurrence.id, 'later');
    expect(spec.fireAtUtc, DateTime.utc(2026, 9, 8, 6));
  });

  test('returns null when every upcoming shift has already passed', () {
    final now = DateTime.utc(2026, 9, 10, 12);
    final spec = nextReminderSpec([
      occ('a', '2026-09-08T07:00:00.000Z', '2026-09-08T19:00:00.000Z'),
      occ('b', '2026-09-09T07:00:00.000Z', '2026-09-09T19:00:00.000Z'),
    ], nowUtc: now);
    expect(spec, isNull);
  });

  test('sorts unsorted input before choosing', () {
    final now = DateTime.utc(2026, 9, 6, 12);
    final spec = nextReminderSpec([
      occ('later', '2026-09-09T07:00:00.000Z', '2026-09-09T19:00:00.000Z'),
      occ('earlier', '2026-09-07T07:00:00.000Z', '2026-09-07T19:00:00.000Z'),
    ], nowUtc: now);
    expect(spec!.occurrence.id, 'earlier');
  });
}
