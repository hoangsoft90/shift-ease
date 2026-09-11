// =============================================================================
// Shift reminder (Gate C B4 — baseline). Pure part:
//   nextReminderSpec() — given the upcoming occurrences of a job, which shift
//   to notify about and the local notification fire time (start minus the
//   lead time). No timezone guessing: fire time is computed from the stored
//   UTC instants (INVARIANT-002) and converted through the same tz database.
//
// Plugin part (ShiftReminderScheduler) wraps flutter_local_notifications with
// a default lead of 60 minutes. Every call is guarded: on platforms/test
// harnesses without the plugin the schedule is skipped silently — scheduling
// a reminder must never crash the calendar. There is no server, no commute
// logic (out of scope).
// =============================================================================

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:shiftease/core/pattern/pattern_types.dart'
    show ShiftOccurrence;

/// What to notify about and when (all UTC instants).
class ReminderSpec {
  final ShiftOccurrence occurrence;
  final DateTime shiftStartUtc;
  final DateTime fireAtUtc;

  const ReminderSpec({
    required this.occurrence,
    required this.shiftStartUtc,
    required this.fireAtUtc,
  });
}

/// Pick the NEXT shift worth a reminder and its fire time.
///
/// - [leadMinutes] is the notice window (default 60).
/// - A shift whose start is already inside the lead window is skipped (it
///   would fire in the past); the one after it is returned instead.
/// - Returns null when nothing is worth scheduling.
ReminderSpec? nextReminderSpec(
  List<ShiftOccurrence> occurrences, {
  DateTime? nowUtc,
  int leadMinutes = 60,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc());
  final sorted = List<ShiftOccurrence>.from(occurrences)
    ..sort((a, b) => a.startDateTimeUtc.compareTo(b.startDateTimeUtc));
  for (final o in sorted) {
    final start = DateTime.parse(o.startDateTimeUtc).toUtc();
    if (start.isBefore(now)) continue; // already started
    final fireAt = start.subtract(Duration(minutes: leadMinutes));
    if (fireAt.isBefore(now)) continue; // too late to schedule
    return ReminderSpec(
      occurrence: o,
      shiftStartUtc: start,
      fireAtUtc: fireAt,
    );
  }
  return null;
}

/// Local-notification scheduling for the next shift (baseline, Gate C B4).
/// All plugin interactions are guarded so the calendar never crashes when the
/// plugin is unavailable (widget tests, unsupported desktop, permission denied).
class ShiftReminderScheduler {
  final FlutterLocalNotificationsPlugin _plugin;
  final bool _available;
  bool _tzReady = false;

  /// Fixed notification id: the plugin keys pending notifications by id, so
  /// re-scheduling with the SAME id REPLACES the previous ShiftEase reminder
  /// (roster change → old reminder must not survive) instead of stacking a
  /// duplicate every time the Today screen syncs.
  static const int _reminderId = 1001;

  ShiftReminderScheduler()
      : _plugin = FlutterLocalNotificationsPlugin(),
        _available = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.linux ||
                defaultTargetPlatform == TargetPlatform.windows);

  /// Request notification permission (RC plan §E3). Android 13+ requires the
  /// runtime POST_NOTIFICATIONS permission — requestNotificationsPermission is
  /// invoked alongside the iOS alert/badge/sound request; both are no-ops on
  /// platforms that do not need them. Returns false when the plugin cannot
  /// run here (test harness, unsupported desktop, plugin failure).
  Future<bool> requestPermission() async {
    if (!_available) return false;
    try {
      tzdata.initializeTimeZones();
      _tzReady = true;
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// RC plan §E3 — the permission status as the Settings screen reports it:
  /// true = notifications enabled, false = denied, null = unknown (the
  /// platform/plugin cannot answer — tests, desktop). The caller renders
  /// "unknown" rather than a guessed state.
  Future<bool?> permissionStatus() async {
    if (!_available) return null;
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  /// RC plan §E1 — CANCEL the ShiftEase reminder entirely. Called when no
  /// upcoming shift is worth a reminder (deleted shift, no schedule, ...) so
  /// a stale notification can never survive a roster change. Best-effort:
  /// a missing plugin just means there was nothing to cancel.
  Future<void> cancelReminder() async {
    if (!_available) return;
    try {
      await _plugin.cancel(_reminderId);
    } catch (_) {
      // No plugin on this host: nothing to cancel.
    }
  }

  /// Schedule (or reschedule) the notification for [spec]. Any previously
  /// scheduled ShiftEase reminder is replaced — a roster change (commit /
  /// override / re-version) must never leave a stale reminder behind.
  Future<void> scheduleFor(ReminderSpec spec, {String jobName = ''}) async {
    if (!_available || !_tzReady) return;
    try {
      final location = tz.getLocation(spec.occurrence.timezone);
      final at = tz.TZDateTime.from(spec.fireAtUtc.toUtc(), location);
      await _plugin.zonedSchedule(
        _reminderId,
        'Shift starting soon',
        spec.occurrence.templateId.isEmpty
            ? '${spec.occurrence.shiftDate}${jobName.isEmpty ? '' : ' · $jobName'}'
            : '${spec.occurrence.templateId} · '
                '${spec.occurrence.shiftDate}${jobName.isEmpty ? '' : ' · $jobName'}',
        at,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'shiftease_reminders',
            'Shift reminders',
            channelDescription: 'Reminder before a shift starts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // No plugin on this host: reminder is best-effort only.
    }
  }

  /// Best-effort full reschedule from the jobs' upcoming occurrences.
  ///
  /// RC plan §E1 — STALE REMINDER CANCELLATION: when NO upcoming shift is
  /// worth a reminder (every shift deleted / all in the past), the previously
  /// scheduled notification is CANCELLED — the early `return` that used to
  /// leave a stale reminder behind is exactly the bug this closes. With an
  /// upcoming shift, re-scheduling under the FIXED id replaces whatever was
  /// scheduled before (roster change → old reminder gone).
  Future<void> syncFromOccurrences(
    List<ShiftOccurrence> occurrences, {
    int leadMinutes = 60,
  }) async {
    final spec = nextReminderSpec(occurrences, leadMinutes: leadMinutes);
    if (spec == null) {
      await cancelReminder();
      return;
    }
    await scheduleFor(spec);
  }
}
