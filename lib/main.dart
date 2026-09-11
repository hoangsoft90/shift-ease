// =============================================================================
// ShiftEase — entrypoint
// =============================================================================
// INVARIANT-008 (offline-first): the calendar runs entirely on a LOCAL SQLite
// file — no cloud, no account. The database path is injectable; production
// paths are resolved in core/db/db_path.dart:
//   • mobile (Android/iOS): path_provider application-support directory
//     (app-private, writable — NEVER HOME-derived; the old `HOME ?? '.'`
//     fallback produced './.shiftease' → errno 30 on Android, P0 issue1.md)
//   • desktop: $HOME/.shiftease/shiftease.db (or SHIFTEASE_DB override)
// Widget tests construct ShiftEaseApp with an in-memory DB instead.
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
//
// 2026-09-11 — ONE deliberate exception to "nothing leaves the device":
// Sentry crash reporting (sentry_flutter) sends uncaught error reports
// (stack traces + error messages, NO database content, PII off) to sentry.io
// so production failures become visible. This is the app's only network
// consumer; doc/release/privacy.md audit basis was updated for it.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'package:shiftease/app/app.dart';
import 'package:shiftease/core/db/business_repository.dart';
import 'package:shiftease/core/db/db.dart';
import 'package:shiftease/core/db/db_path.dart';
import 'package:shiftease/core/db/pattern_repository.dart';
import 'package:shiftease/core/db/schedule_repository.dart';
import 'package:shiftease/core/time/time_engine.dart';
import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/security/secure_secret_store.dart';

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
/// storage I/O) a splash shows; failures land on the recovery screen —
/// classified per failure kind so the copy never blames the key when the
/// problem is the filesystem (or vice versa).
class _Bootstrap extends StatefulWidget {
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  ScheduleService? _service;
  _FailureClass _failureClass = _FailureClass.unexpected;
  String _failureDetail = '';

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
      // P0 fix: production path via core/db/db_path.dart — app-support
      // directory on mobile, never HOME-derived, never a CWD fallback.
      final dbPath = await resolveDbPath();
      // P7.2: keyed open. defaultOpener PROVES the result is SQLCipher
      // (cipher_version + ciphertext negative control) or throws
      // SqlCipherUnavailableError — no silent plain fallback.
      final db = openDatabase(
        opener: defaultOpener,
        path: dbPath,
        key: key,
      );
      if (!mounted) return;
      setState(() => _service = composeService(db, encryptionKeyHex: key));
    } on SecretStoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _failureClass = _FailureClass.secretStore;
        _failureDetail = e.toString();
      });
    } on SqlCipherUnavailableError catch (e) {
      if (!mounted) return;
      setState(() {
        _failureClass = _FailureClass.cipher;
        _failureDetail = describeOpenFailure(e);
      });
    } on FileSystemException catch (e) {
      // errno 30 (read-only CWD), creation failed, permission denied…
      if (!mounted) return;
      setState(() {
        _failureClass = _FailureClass.filesystem;
        _failureDetail = e.toString();
      });
    } on StateError catch (e) {
      // resolveDbPath desktop guard: HOME unset (its message names the fix).
      if (!mounted) return;
      setState(() {
        _failureClass = _FailureClass.filesystem;
        _failureDetail = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failureClass = _FailureClass.unexpected;
        _failureDetail = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service != null) {
      return ShiftEaseApp(service: service);
    }
    if (_failureDetail != '') {
      return _LockedApp(failureClass: _failureClass, detail: _failureDetail);
    }
    return const MaterialApp(
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

/// Which subsystem failed while opening the production store. Drives the
/// recovery copy so users are never told their data is lost when the real
/// problem is a read-only filesystem (P0 issue1.md) — or vice versa.
enum _FailureClass { filesystem, secretStore, cipher, unexpected }

/// Shown when the database cannot be opened. Deliberately honest AND
/// specific: the copy names the failing subsystem, and only the key/cipher
/// classes talk about keys and restore. No fake errors, no silent re-create,
/// no "uninstall/reinstall" framing for filesystem failures (prompt_fix1.md).
class _LockedApp extends StatelessWidget {
  final _FailureClass failureClass;
  final String detail;
  const _LockedApp({required this.failureClass, required this.detail});

  String get _title {
    switch (failureClass) {
      case _FailureClass.filesystem:
        return 'ShiftEase — storage problem';
      case _FailureClass.secretStore:
      case _FailureClass.cipher:
        return 'ShiftEase — locked';
      case _FailureClass.unexpected:
        return 'ShiftEase — unexpected error';
    }
  }

  String get _summary {
    switch (failureClass) {
      case _FailureClass.filesystem:
        return 'The app could not create or open its database file — the '
            'storage location is unavailable. This is a filesystem problem, '
            'NOT a lost key: your data is not gone.';
      case _FailureClass.secretStore:
        return 'The device secure storage (Keystore/Keychain) could not '
            'provide the database key, so the encrypted database cannot be '
            'opened. Your data is locked, not lost.';
      case _FailureClass.cipher:
        return 'The encrypted database could not be opened with its key '
            '(wrong key, or the file is not a ShiftEase encrypted store). '
            'Your data is locked, not lost.';
      case _FailureClass.unexpected:
        return 'An unexpected error occurred while opening the database.';
    }
  }

  String get _guidance {
    switch (failureClass) {
      case _FailureClass.filesystem:
        return 'What to do:\n'
            '  • Fully close the app and reopen it (transient storage '
            'state).\n'
            '  • Restart the device — app storage can fail transiently '
            'after an OS update.\n'
            '  • Check free storage space.\n'
            '  • If it persists, reinstalling creates a FRESH database; '
            'restore a backup afterwards (Settings → Data → Restore) — '
            'reinstalling alone does not recover data.\n\n'
            'ShiftEase will NOT write the database to an unsafe location.';
      case _FailureClass.secretStore:
        return 'What to do:\n'
            '  • Restart the device — secure storage can fail transiently '
            'after an OS update.\n'
            '  • Make sure the device lock screen is set (Keystore '
            'requirements).\n'
            '  • If you uninstalled and reinstalled the app, the old key is '
            'gone by design. Restore from a backup file (Settings → Data → '
            'Restore) once a fresh store is created.\n\n'
            'ShiftEase will NOT open the database without its key.';
      case _FailureClass.cipher:
        return 'What to do:\n'
            '  • Restart the app — a partially written file can fail to '
            'authenticate.\n'
            '  • If the store is unrecoverable, a fresh one can be created '
            'and a backup restored (Settings → Data → Restore).\n\n'
            'ShiftEase will NOT open the database without its key.';
      case _FailureClass.unexpected:
        return 'Restart the app. If it persists, report the technical '
            'detail below through the support channel.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_summary,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(_guidance),
                  const SizedBox(height: 16),
                  Text('Technical detail: $detail',
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
