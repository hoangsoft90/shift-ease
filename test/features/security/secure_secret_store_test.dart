// =============================================================================
// P7.3 / P7.4 — SecureSecretStore tests.
//
// In the test VM no platform channel is registered, so every
// FlutterSecureStorage call throws MissingPluginException — which is exactly
// the "platform secure storage unavailable" path the plan requires to be
// explicit. These tests prove:
//
//   1. every failure is wrapped as SecretStoreException naming the
//      OPERATION (never the stored value);
//   2. getOrCreateEncryptionKey PROPAGATES that failure — main.dart refuses
//      to start rather than opening the DB without a key;
//   3. the store never logs or echoes the secret (string checks).
//
// The happy-path behavior (Android Keystore / iOS Keychain persistence
// across restart/reboot) is DEVICE-verified — recorded honestly as BLOCKED
// in result_p7_production_verification.md, never claimed from these tests.
// =============================================================================

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:test/test.dart';

import 'package:shiftease/features/security/secure_secret_store.dart';

void main() {
  group('SecureSecretStore — platform storage unavailable (error path)', () {
    test('write wraps the failure as SecretStoreException(write)', () async {
      final store = SecureSecretStore();
      await expectLater(
        store.write(kDbMasterKeyId, 'some-secret'),
        throwsA(isA<SecretStoreException>()),
      );
    });

    test('read wraps the failure as SecretStoreException(read)', () async {
      final store = SecureSecretStore();
      await expectLater(
        store.read(kDbMasterKeyId),
        throwsA(isA<SecretStoreException>()),
      );
    });

    test('delete wraps the failure as SecretStoreException(delete)', () async {
      final store = SecureSecretStore();
      await expectLater(
        store.delete(kDbMasterKeyId),
        throwsA(isA<SecretStoreException>()),
      );
    });

    test('the exception message names the operation, never the secret',
        () async {
      final store = SecureSecretStore();
      try {
        await store.write(kDbMasterKeyId, 'the-master-key-value');
        fail('expected SecretStoreException');
      } on SecretStoreException catch (e) {
        expect(e.toString(), contains('write'));
        expect(e.toString(), isNot(contains('the-master-key-value')),
            reason: 'the stored value must never appear in errors/logs');
      }
    });
  });

  group('getOrCreateEncryptionKey — failure propagation', () {
    test('a failing store aborts key resolution (app refuses to start)',
        () async {
      final store = SecureSecretStore();
      await expectLater(
        getOrCreateEncryptionKey(store),
        throwsA(isA<SecretStoreException>()),
      );
    });

    test('options bind Keystore-encrypted prefs + non-roaming keychain',
        () {
      // Documented P7.3/P7.4 platform bindings, enforced by the default
      // constructor options (exposed read-only for exactly this assertion).
      // A regression here (e.g. dropping encryptedSharedPreferences) changes
      // what these defaults assert.
      final store = SecureSecretStore();
      // toMap() is the actual platform-channel payload, so asserting on it
      // pins exactly what reaches the native side.
      expect(store.androidOptions.toMap()['encryptedSharedPreferences'], 'true',
          reason: 'P7.3: Android must use Keystore-backed encrypted prefs');
      expect(
        store.iosOptions.toMap()['accessibility'],
        KeychainAccessibility.first_unlock_this_device.name,
        reason: 'P7.4: the key must not roam (this-device keychain '
            'accessibility, readable after first unlock)',
      );
    });
  });
}
