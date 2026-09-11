// =============================================================================
// ShiftEase — entrypoint
// =============================================================================
// INVARIANT-008 (offline-first): the calendar runs entirely on a LOCAL SQLite
// file — no cloud, no account. The database path is injectable; when running
// as a real app the default resolves to $HOME/.shiftease/shiftease.db.
// Widget tests construct ShiftEaseApp with an in-memory DB instead.
//
// 2026-09-11 — ONE deliberate exception to "nothing leaves the device":
// Sentry crash reporting (sentry_flutter) sends uncaught error reports
// (stack traces + error messages, NO database content, PII off) to sentry.io
// so production failures become visible. This is the app's only network
// consumer; doc/release/privacy.md audit basis was updated for it.
//
// P7.2/P7.3/P7.4 (production verification, P7_fix1.md): the production
// database is ENCRYPTED with SQLCipher (pubspec build hook `source:
// sqlcipher`). The master key is generated once, stored in platform secure
// storage (Android Keystore / iOS Keychain — SecureSecretStore) and proven on
// every launch. If the store or the key fails, the app DOES NOT degrade to a
// plain database: it shows the recovery screen and explains exactly what to
// do (restore a backup into a fresh encrypted store). composeService stays
// injectable so the composition test keeps running the same wiring with a
// plain test database.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:shiftease/app/app.dart';
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/security/secure_secret_store.dart';

/// Path of the local database. Overridable via SHIFTEASE_DB (used by the
/// desktop/CLI run); falls back to $HOME/.shiftease/shiftease.db.
String defaultDbPath() {
  final env = Platform.environment['SHIFTEASE_DB'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'] ?? '.';
  final dir = Directory('$home/.shiftease');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return '${dir.path}/shiftease.db';
}

/// Production composition (Gate A §A1): all repositories share ONE database
/// connection so a transaction genuinely spans them — the import commit is
/// atomic across session + occurrences, never two separate connections.
/// This is the single source of wiring truth: main() and the composition test
/// both call it, so the test can never drift from what the app really runs.
/// [encryptionKeyHex] is the master key of the (encrypted) database when one
/// was used — it only feeds the Settings §G probe.
ScheduleService composeService(Database db, {String? encryptionKeyHex}) {
  final patterns = PatternRepository(db);
  final schedule = ScheduleRepository(db, patterns);
  final imports = ImportRepository(db, patterns);
  return ScheduleService(
    patterns: patterns,
    schedule: schedule,
    db: db,
    imports: imports,
    pay: PayRuleRepository(db, patterns),
    encryptionKeyHex: encryptionKeyHex,
  );
}

void main() {
  initializeTimezoneDatabase(); // core/time — must run before any resolve
  // Sentry wraps the whole app so uncaught Flutter errors AND uncaught errors
  // inside _Bootstrap's async open (key store, DB open) both get reported.
  // appRunner defers runApp until SDK setup finishes; sendDefaultPii=false —
  // no device identifiers attached. Error reporting only: tracing disabled.
  SentryFlutter.init(
    (options) {
      options.dsn =
          'https://4ba7f0242a15f45cbd863312820e4806@o4505474077753344.ingest.us.sentry.io/4512066544533504';
      options.tracesSampleRate = 0;
      options.sendDefaultPii = false;
    },
    appRunner: () => runApp(_Bootstrap()),
  );
}

/// Root widget that resolves the encryption key and opens the encrypted
/// database BEFORE building the real app. While that runs (platform secure
/// storage I/O) a splash shows; failures land on the recovery screen.
class _Bootstrap extends StatefulWidget {
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  ScheduleService? _service;
  String? _failureReason;

  @override
  void initState() {
    super.initState();
    _openProductionDatabase();
  }

  Future<void> _openProductionDatabase() async {
    try {
      // P7.3/P7.4: read (or first-launch generate) the master key from
      // Android Keystore / iOS Keychain. Throws SecretStoreException on a
      // platform-storage failure — that is the explicit error path.
      final key = await getOrCreateEncryptionKey(SecureSecretStore());
      // P7.2: keyed open. defaultOpener PROVES the result is SQLCipher
      // (cipher_version + ciphertext negative control) or throws
      // SqlCipherUnavailableError — no silent plain fallback.
      final db = openDatabase(
        opener: defaultOpener,
        path: defaultDbPath(),
        key: key,
      );
      if (!mounted) return;
      setState(() => _service = composeService(db, encryptionKeyHex: key));
    } on SecretStoreException catch (e) {
      if (!mounted) return;
      setState(() => _failureReason = e.toString());
    } on SqlCipherUnavailableError catch (e) {
      if (!mounted) return;
      setState(() => _failureReason = describeOpenFailure(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _failureReason =
          'Unexpected failure opening the encrypted database: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service != null) {
      return ShiftEaseApp(service: service);
    }
    if (_failureReason != null) {
      return _LockedApp(reason: _failureReason!);
    }
    return const MaterialApp(
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

/// Shown when the database cannot be opened with its key. Deliberately
/// honest and specific: the data is NOT gone, it is locked — and the user
/// has backups (Settings → Data). No fake error, no silent re-create.
class _LockedApp extends StatelessWidget {
  final String reason;
  const _LockedApp({required this.reason});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ShiftEase — locked')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The encrypted database could not be opened.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'Reason: $reason\n\n'
                  'Your data is locked, not lost. Options:\n'
                  '  • Restart the device — secure storage can fail '
                  'transiently after an OS update.\n'
                  '  • If you uninstalled and reinstalled the app, the old '
                  'key is gone by design. Restore from a backup file '
                  '(Settings → Data → Restore) once a fresh store is '
                  'created.\n\n'
                  'ShiftEase will NOT open the database without its key.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
