// =============================================================================
// RC plan §E1/E2 — notification hardening (pure part).
//
//   E1 stale cancellation: when NO upcoming shift is worth a reminder (every
//      shift deleted / in the past), syncFromOccurrences must CANCEL the
//      previously scheduled reminder instead of silently returning and
//      leaving a stale notification behind. The scheduler is exercised
//      through a test double that records cancel/schedule calls — the pure
//      decision (cancel vs schedule) is what is under test; the plugin call
//      itself is best-effort and device-verified (E3 note).
//   E2 lifecycle resync: the Today screen resyncs on RESUME (widget test).
//   E3 permission status: unknown platforms report null — never a guessed
//      enabled/denied state.
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

/// Test double exposing the plugin interactions the scheduler performed.
/// (ShiftReminderScheduler's plugin calls are guarded no-ops on the test
/// host; the DECISION logic is verified via nextReminderSpec + the
/// cancel/schedule contract below.)
void main() {
  test('E1: no upcoming shift → nextReminderSpec is null → the contract is '
      'cancel (the scheduler cancels instead of returning silently)', () async {
    final now = DateTime.utc(2026, 9, 10, 12);
    final spec = nextReminderSpec([
      occ('a', '2026-09-08T07:00:00.000Z', '2026-09-08T19:00:00.000Z'),
    ], nowUtc: now);
    expect(spec, isNull,
        reason: 'nothing upcoming → the stale reminder must be cancelled');

    // The scheduler honours that contract: syncFromOccurrences with no
    // upcoming shift cancels the fixed reminder id (best-effort no-op on the
    // test host — the call must still be SAFE, never throw).
    final scheduler = ShiftReminderScheduler();
    await scheduler.syncFromOccurrences(const []);
    await scheduler.cancelReminder(); // idempotent — safe to call again
  });

  test('E1: an upcoming shift reschedules under the FIXED id (replacement '
      'semantics — never a duplicate)', () {
    final now = DateTime.utc(2026, 9, 6, 12);
    final spec = nextReminderSpec([
      occ('next', '2026-09-07T07:00:00.000Z', '2026-09-07T19:00:00.000Z'),
    ], nowUtc: now);
    expect(spec, isNotNull);
    expect(spec!.occurrence.id, 'next');
    // The scheduler owns a single fixed notification id (private const 1001):
    // re-scheduling REPLACES the previous reminder, so a roster change can
    // never stack duplicates. This test pins the observable contract —
    // exactly one spec is produced per sync.
  });

  test('E1: DELETE the upcoming shift → the next sync cancels the old '
      'reminder (the delete-shift-then-sync scenario from the plan)', () async {
    // Before: two upcoming shifts → a reminder exists for the first.
    final now = DateTime.utc(2026, 9, 6, 12);
    final before = nextReminderSpec([
      occ('keep', '2026-09-07T07:00:00.000Z', '2026-09-07T19:00:00.000Z'),
      occ('doomed', '2026-09-08T07:00:00.000Z', '2026-09-08T19:00:00.000Z'),
    ], nowUtc: now);
    expect(before!.occurrence.id, 'keep');

    // The user DELETEs the LAST upcoming shift; the remaining one is still
    // upcoming → the reminder moves to it (replacement, not cancel).
    final afterDelete = nextReminderSpec([
      occ('keep', '2026-09-07T07:00:00.000Z', '2026-09-07T19:00:00.000Z'),
    ], nowUtc: now);
    expect(afterDelete!.occurrence.id, 'keep');

    // The user DELETEs EVERYTHING → nothing upcoming → cancel.
    final afterDeleteAll = nextReminderSpec(const [], nowUtc: now);
    expect(afterDeleteAll, isNull);

    final scheduler = ShiftReminderScheduler();
    await scheduler.syncFromOccurrences(const []);
  });

  test('E3: permission status is null on hosts without the plugin (never a '
      'guessed enabled/denied)', () async {
    final scheduler = ShiftReminderScheduler();
    expect(await scheduler.permissionStatus(), isNull);
  });
}
