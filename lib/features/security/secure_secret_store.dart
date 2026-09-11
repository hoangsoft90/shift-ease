// =============================================================================
// P7.3 / P7.4 — PRODUCTION SecretStore (Android Keystore / iOS Keychain).
// =============================================================================
//
// The [InMemorySecretStore] in security_gate.dart is a TEST DOUBLE. This is
// the production implementation of the same seam:
//
//   - flutter_secure_storage stores the value with Android Keystore-backed
//     encryption (EncryptedSharedPreferences) on Android and the iOS Keychain
//     on iOS — the master key never lands in plaintext SharedPreferences, a
//     file, or the database.
//   - Values survive app restart and force kill (the Keystore/Keychain entry
//     is read again on the next launch).
//   - Defined reinstall behavior: the Android EncryptedSharedPreferences
//     entry is removed when the app is uninstalled, so the on-disk database
//     can no longer be decrypted after a reinstall; the app then shows its
//     recovery screen (main.dart) instead of guessing. On iOS the Keychain
//     entry MAY survive a reinstall depending on device/backup state — the
//     app therefore NEVER assumes the key exists and always proves the open
//     (fail-closed [SqlCipherUnavailableError] on mismatch).
//   - Error path is explicit: platform storage failures rethrow as
//     [SecretStoreException] — main.dart refuses to start on a locked store
//     rather than opening the database without a key.
//
// Nothing here logs the key or includes it in any backup/debug output.
// =============================================================================

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:shiftease/core/db/db.dart' show SqlCipherUnavailableError;
import 'package:shiftease/core/db/security_gate.dart'
    show SecretStore, generateEncryptionKey;

/// Raised when the platform secure storage itself fails (locked keystore,
/// device without secure hardware support for the requested options, …).
/// The error message names the OPERATION, never the stored value.
class SecretStoreException implements Exception {
  final String operation;
  final Object error;
  SecretStoreException(this.operation, this.error);
  @override
  String toString() =>
      'SecretStoreException: secure storage failed during $operation '
      '(${error.runtimeType}) — the app cannot access its encryption key.';
}

/// The key identifier the DB master key lives under. One app, one key — the
/// identifier is not a secret.
const String kDbMasterKeyId = 'shiftease.db.master_key';

/// Production [SecretStore]: Android Keystore (via EncryptedSharedPreferences)
/// / iOS Keychain. All methods are explicit about failure — there is no
/// in-memory fallback pretending the value was persisted.
class SecureSecretStore implements SecretStore {
  /// P7.3 defaults: Android Keystore-backed encrypted preferences.
  static const _defaultAndroidOptions =
      AndroidOptions(encryptedSharedPreferences: true);

  /// P7.4 defaults: the key must be readable on first unlock so the schedule
  /// (and reminders) work right after reboot, but it must not roam:
  /// this_device keeps it off iCloud Keychain sync.
  static const _defaultIosOptions = IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device);

  final FlutterSecureStorage _storage;

  /// Platform bindings, exposed read-only so tests can assert the P7.3/P7.4
  /// guarantees without reaching into privates.
  final AndroidOptions androidOptions;
  final IOSOptions iosOptions;

  SecureSecretStore({
    AndroidOptions? androidOptions,
    IOSOptions? iosOptions,
  })  : androidOptions = androidOptions ?? _defaultAndroidOptions,
        iosOptions = iosOptions ?? _defaultIosOptions,
        _storage = FlutterSecureStorage(
          aOptions: androidOptions ?? _defaultAndroidOptions,
          iOptions: iosOptions ?? _defaultIosOptions,
        );

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw SecretStoreException('write', e);
    }
  }

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw SecretStoreException('read', e);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      throw SecretStoreException('delete', e);
    }
  }
}

/// Key lifecycle (P7.2 required flow):
///
///   first launch → none stored → generate cryptographically random key →
///   store in secure storage → return it.
///
///   every launch after → read the stored key → return it.
///
/// The generated key is written BEFORE it is used: a crash between the two
/// steps below would otherwise leave a DB that no stored key opens. If the
/// write itself fails, [SecretStoreException] propagates — the app never
/// proceeds with an unstored key.
Future<String> getOrCreateEncryptionKey(SecretStore store) async {
  final existing = await store.read(kDbMasterKeyId);
  if (existing != null && existing.isNotEmpty) return existing;
  final key = generateEncryptionKey();
  await store.write(kDbMasterKeyId, key);
  return key;
}

/// The reason a keyed open failed, for the recovery screen. Separated from
/// [SqlCipherUnavailableError] so main.dart can translate it without string
/// matching.
String describeOpenFailure(SqlCipherUnavailableError e) => e.reason;
