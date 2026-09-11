// =============================================================================
// ShiftEase — production database path resolution
// =============================================================================
// P0 fix (issue1.md / prompt_fix1.md, 2026-09-11): the DB path must NEVER be
// derived from HOME on mobile. Android apps have no HOME and a read-only
// working directory — the old `HOME ?? '.'` fallback produced './.shiftease'
// and errno 30 (Read-only file system) on every phone.
//
// Path strategy (ONE convention, documented):
//   1. SHIFTEASE_DB env var wins when set (desktop/CLI + env-driven tests).
//   2. Android / iOS: path_provider getApplicationSupportDirectory() —
//      app-private, always writable, no permissions needed (the backup/ICS
//      exports already live there, so all app files share one root).
//   3. Desktop (linux/mac/windows): $HOME/.shiftease/shiftease.db, creating
//      the directory inside a REAL HOME only — never a '.' fallback.
//
// Invariant (unit-tested): the computed path is absolute and never has the
// errno-30 shape ('/./' or a bare relative path).
// =============================================================================

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Injectable platform probe so tests can exercise every branch without
/// mocking path_provider platform channels.
abstract class PlatformProbe {
  bool get isAndroid;
  bool get isIOS;
  String? env(String key);
  String? get homeDir;
  Future<Directory> applicationSupportDirectory();
}

class DefaultPlatformProbe implements PlatformProbe {
  const DefaultPlatformProbe();

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  bool get isIOS => Platform.isIOS;

  @override
  String? env(String key) => Platform.environment[key];

  @override
  String? get homeDir => Platform.environment['HOME'];

  @override
  Future<Directory> applicationSupportDirectory() =>
      getApplicationSupportDirectory();
}

/// Resolves the production database file path.
///
/// [probe] is injectable for tests; production uses [DefaultPlatformProbe].
/// Never returns a relative path on its own (the only way to get one is an
/// explicit relative SHIFTEASE_DB override, which is the caller's choice).
Future<String> resolveDbPath({
  PlatformProbe probe = const DefaultPlatformProbe(),
}) async {
  // 1. Explicit override always wins (desktop/CLI + env-driven tests).
  final override = probe.env('SHIFTEASE_DB');
  if (override != null && override.isNotEmpty) return override;

  // 2. Mobile: app-support directory (writable, app-private, no permissions).
  if (probe.isAndroid || probe.isIOS) {
    final dir = await probe.applicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/shiftease.db';
  }

  // 3. Desktop: HOME-based dotdir. HOME must exist — failing loudly beats
  //    silently writing to a read-only CWD (the exact P0 bug shape).
  final home = probe.homeDir;
  if (home == null || home.isEmpty) {
    throw StateError(
      'ShiftEase desktop: HOME is not set; cannot resolve the database '
      'directory. Set SHIFTEASE_DB to an explicit file path.',
    );
  }
  final dir = Directory('$home/.shiftease');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/shiftease.db';
}
