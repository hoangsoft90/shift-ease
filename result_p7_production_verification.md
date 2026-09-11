# result_p7_production_verification.md — P7 Production Verification Evidence

> Date: 2026-09-11 (rev 2 — SQLCipher implementation + P7_fix2 CI corrections) · Author: Buffy (Codebuff agent) · Phase: **P7 — Production Verification / Security / Real Devices**
> Source documents: `phases/PRODUCTION_REVIEW.md` (roadmap review) + `phases/P7_production_verification.md` (phase spec) + `production_roadmap.md` (source-of-truth roadmap) + `P7_fix1.md` / `P7_fix2.md` (correction directives).
>
> **Honesty rule applied throughout: a gate that was NOT executed is marked NOT RUN / BLOCKED — never PASS.**

---

## 1. Environment

| Item | Value |
|---|---|
| Source revision | `git` metadata unavailable in this sandbox (no `.git`); source tree = working directory 2026-09-11 |
| Flutter | 3.47.2 stable (framework d3b14c8769, 2026-08-26) · Dart 3.13.2 |
| Native SQLite | **SQLCipher 4.18.0 community**, linked via the `package:sqlite3` 3.x build hook (`pubspec.yaml` → `hooks.user_defines.sqlite3.source: sqlcipher`) — verified by `dart run tool/cipher_proof.dart` in this sandbox |
| Analyze | `flutter analyze --no-pub` → **No issues found!** |
| Full test suite | `flutter test test/` → **315/315 PASS** on the final source tree |
| Android device | **NOT RUN** — no device in sandbox (CI debug-APK pipeline wired instead) |
| iOS device | **NOT RUN** — no device/toolchain in sandbox |

## 2. P7.1 — the two RC-review blockers (both FIXED + TESTED)

### H1 — HIGH — Backup directory (FIXED + TESTED)

`phases/P7_production_verification.md` §2.1. Before: `SettingsScreen._dir => widget.backupDir ?? Directory.systemTemp` and the Jobs-screen wiring passed none → production backups landed in the purgeable cache dir.

Implementation (`lib/features/settings/settings_screen.dart`):
- No `Directory.systemTemp` fallback anywhere on the backup/restore path.
- `backupDir == null` (production wiring) → screen resolves **`getApplicationSupportDirectory()`** (path_provider) in `initState`, creates it if missing.
- Injectable seam `backupDirResolver` so the resolver itself is testable without the plugin.
- path_provider failure → **honest refusal**: `"Storage location unavailable — backup/restore disabled: …"` on BOTH backup and restore. Never a silent temp fallback.
- Injected `backupDir` (tests) still honored; backup naming unchanged; restore reads the same resolved directory; no migration/deletion of existing backups.

Tests (`test/ui/settings_flow_test.dart`, group "P7.1 H1"):
1. default path backs up into the resolved app-support directory; delete-all → restore round-trip reads the same place. ✅
2. unavailable storage → honest refusal on Backup AND Restore; snapshot asserts **no** `shiftease-backup-*.json` appears in `Directory.systemTemp`. ✅
3. Injected-dir tests (pre-existing §H flow) still pass — DI seam preserved. ✅

### M1 — MEDIUM — Income Impact drops unresolvable rows (FIXED + TESTED)

`phases/P7_production_verification.md` §2.2. Before: `estimateRosterDiffImpact` → `resolve()` did `if (!res.isSuccess) continue;` → an unresolvable row (DST gap, malformed times) silently vanished from the "After" leg → optimistic total.

Implementation (`lib/domain/schedule_service.dart`):
- `resolve(rows)` → `resolveAll(rows)` returning `(List<ShiftOccurrence>, String? error)`.
- Any row failing `resolveShift` → the WHOLE preview returns `IncomeImpact.unavailable()` with reason `Before:`/`After:` + **row date, start–end, timezone, engine error code**.
- OFF days (null start/end) remain legitimate roster content, not failures. No partial/optimistic total is ever produced.

Tests (`test/domain/income_estimate_test.dart`, group "P7.1 M1", `America/New_York`, 2026-03-08 spring gap, 02:00 nonexistent):
1. valid rows only (incl. a legitimate OFF day) → AVAILABLE (before $0, after $160, delta +$160). ✅
2. one DST-gap row → UNAVAILABLE naming the row (`After:`, `2026-03-08`, `could not be resolved`). ✅
3. mixed valid + unresolvable rows → UNAVAILABLE (never partial). ✅

## 3. P7.2 — SQLCipher is now REAL, not a claim (P7_fix1 directive)

Before this revision: `PRAGMA key` ran on **plain** sqlite3 — encryption was fake. Now:

- **Native linkage**: `pubspec.yaml` declares `hooks.user_defines.sqlite3.source: sqlcipher`; the `package:sqlite3` 3.x build hook compiles/links **libsqlcipher.so into every build, including `flutter test` runs and CI**. If the hook cannot provide the SQLCipher asset the build fails — encryption cannot be silently dropped.
- **Fail-closed opener** (`lib/core/db/db.dart`): opener refuses (throws `SqlCipherUnavailableError`) when `PRAGMA cipher_version` returns nothing; keyed opens without a key on a non-memory path are refused; a wrong key surfaces SQLCipher's own `sqlite3Codec` error (loud, logged in test runs by design).
- **Honesty probe, upgraded** (`lib/core/db/security_gate.dart`): `verifyEncryption` requires BOTH (a) cipher-capable library AND (b) proof the connection is actually keyed via the documented caller contract (`expectedKeyHex`) — a cipher-capable build can no longer misreport a plain connection as encrypted.
- **Production key flow** (`lib/main.dart`): `getOrCreateEncryptionKey(SecureSecretStore())` → keyed open; `SqlCipherUnavailableError` → **recovery screen**, no plain fallback. Splash while resolving.
- **Positive proof available in CI without a device**: `tool/cipher_proof.dart` (pure Dart) asserts `PRAGMA cipher_version` is non-empty on the linked build; sandbox execution printed `P7.2 OK: linked native build is SQLCipher 4.18.0 community`. It runs as a named step in the CI persistence job.

Tests (real encrypted file DBs, not mocks):
- `test/core/db/security_gate_test.dart` — 17 tests: create/reopen with key, wrong-key refusal, ciphertext-header check (file bytes ≠ SQLite header), migration v1→v3 on an encrypted DB, key-lifecycle round-trip, `verifyEncryption` honesty contract.
- `test/core/adversarial/rc_adversarial_test.dart` — adversarial scenario updated to the honest negative: a caller CLAIMS a key the connection cannot use → probe must not claim encrypted.
- `test/core/db/backup_restore_test.dart` — 9 tests incl. **encrypted-file backup → restore round-trip** (P7.8/P7.9 upgrade to encrypted scope).
- File-DB restart-persistence harnesses (`test/domain/*`) converted to keyed opens — they now prove **encrypted** persistence (P7.8 upgrade).

## 4. P7.3/P7.4 — production SecretStore (Android Keystore / iOS Keychain)

`lib/features/security/secure_secret_store.dart` (Flutter plugin layer, per plan2 §1.1 layering):
- `flutter_secure_storage` (^9.2.4): Android `encryptedSharedPreferences: true` (Keystore-backed), iOS `KeychainAccessibility.first_unlock_this_device` (readable after first unlock — reminders work after reboot; never roams to iCloud Keychain).
- Every platform failure rethrows as `SecretStoreException` naming the **operation, never the stored value**; `getOrCreateEncryptionKey` propagates → app refuses to start on a locked store (no keyless open).
- Key written to secure storage BEFORE first use (no unstoreable-key window).

Tests (`test/features/security/secure_secret_store_test.dart`, 6 tests): in the test VM no platform channel exists → every call throws MissingPluginException → tests prove (1) each operation wraps as `SecretStoreException(operation)`, (2) the message never contains the secret, (3) `getOrCreateEncryptionKey` propagates the failure, (4) the platform-channel payload (`options.toMap()`) binds the P7.3/P7.4 guarantees exactly as documented. Happy-path persistence across restart/reboot remains a **device** gate (§5).

## 5. P7 gate matrix (honest, rev 2)

Legend: ✅ PASS (executed in sandbox) · ⚠️ PARTIAL · ❌ FAIL · ⛔ **NOT RUN — requires device outside sandbox**.

| # | Gate | Status | Evidence / note |
|---|---|---|---|
| P7.1 | H1 backup directory | ✅ PASS | §2 above |
| P7.1 | M1 income impact | ✅ PASS | §2 above |
| P7.2 | SQLCipher integration | ✅ PASS (sandbox scope) / ⛔ device leg | Real SQLCipher 4.18.0 linked in every build incl. tests (§3); 17 security-gate tests on real encrypted files; wrong-key + ciphertext-header + migration evidence. **Device leg NOT RUN**: copy-DB→plain-SQLite negative test on hardware, reinstall/recovery walk. |
| P7.2 CI proof | `cipher_version` on CI | ✅ wired | `test.yml` persistence job runs `dart run tool/cipher_proof.dart` as a named step (fails CI if plain sqlite3 returns) + the whole suite runs on the cipher-linked build. A green CI run IS the P7.2 native-encryption proof. |
| P7.3 | Android Keystore | ✅ code + error-path tests / ⛔ device | §4; device-verified persistence pending. |
| P7.4 | iOS Keychain | ✅ code + error-path tests / ⛔ device | §4; device-verified persistence pending. |
| P7.5 | Android notifications real-device | ⛔ NOT RUN (device) | Logic covered (E1/E2 + tests); debug APK via CI `build-debug-apk.yml` unblocks the physical matrix. |
| P7.6 | iOS notifications real-device | ⛔ NOT RUN (device) | Same; iOS permission status honestly `Unknown` (M2, by design). |
| P7.7 | Lifecycle kill/reopen walk | ⛔ NOT RUN (device) | Sandbox: append-only overrides + persist/restore covered by suite; physical walk pending. |
| P7.8 | Migration verification | ✅ PASS (now incl. encrypted DB) | v1→v3 plain + encrypted-file migration tests, fail-before/restart rollback (RC A7). |
| P7.9 | Backup/restore | ✅ PASS (sandbox scope, encrypted) / ⛔ device leg | Encrypted round-trip + corrupted rejection + H1 widget round-trip. Realistic multi-table dataset on hardware NOT RUN. |
| P7.10 | DST/timezone real-device | ⚠️ PARTIAL | Engine/UI + M1 spring-gap suite green; device timezone-change/reboot interpretation checks NOT RUN. |
| P7.11 | Security review | ✅ PASS (re-run on final tree 2026-09-11) | Grep over `lib/`: no print/debugPrint, no secrets, `Random.secure` key gen, key never logged/backed-up/echoed; SQLCipher bound in opener only. |
| P7.12 | Full regression | ✅ PASS | analyze clean + **315/315** on the final source tree. |
| — | APK build | ✅ CI-wired / ⛔ run pending | `build-debug-apk.yml` builds a debug-signed APK artifact (SQLCipher ships inside via the build hook); runs on push/manual dispatch. |

## 6. CI corrections per P7_fix2.md

P7_fix2 found that `.github/workflows/test.yml` still targeted an old Dart-only project. Status of the three directives:

1. **Fix `test.yml` → Flutter root** — ✅ DONE (this session). All 10 `dart test` invocations → `flutter test`; obsolete `apt-get install libsqlite3-dev` steps removed (the SQLCipher build hook compiles the native lib; system sqlite is not used); per-engine jobs, Node golden cross-checks (`scripts/*.mjs`), dependency-rule enforcement, and the `full-suite` gate retained; `workflow_dispatch` added; path filters widened to `lib/**`, `test/**`, `scripts/**`.
2. **Add debug-APK workflow** — file **exists on disk** (`.github/workflows/build-debug-apk.yml`; the P7_fix2 reviewer had a stale checkout). Its matrix-row note was updated: rows 2/3/4 (migration/encrypted DB/reboot) are now unlocked by this artifact too, because SQLCipher ships inside the debug APK via the build hook.
3. **SQLCipher proof on CI without a device** — ✅ DONE (§5 "P7.2 CI proof").

Both YAML files validated to parse clean (`yaml.safe_load`): jobs `static-analysis, core-time-tests, core-pattern-tests, core-money-tests, import-tests, persistence-tests, ui-tests, full-suite` + `build-debug-apk`.

## 7. Known limitations / unresolved issues

- **M2** (iOS notification permission status) — deliberately `Unknown` unless the API provides exact state; device cycle.
- **L4** (13-day reminder resync window) — accepted per `PRODUCTION_REVIEW.md` §3 (E2 resume resync correct + tested).
- **Device-only legs** of P7.2–P7.7/P7.9/P7.10 — exactly as listed in §5; cannot be honestly claimed from a sandbox.
- Release signing / Play-Console artifacts remain out of scope for the debug-APK pipeline (later phase).

## 8. P7 Definition of Done (§15 of the phase spec)

- [x] H1 fixed and tested
- [x] M1 fixed and tested
- [x] SQLCipher real and verified — sandbox scope ✅ (17 gate tests + cipher proof; device negative test pending)
- [x] Android secure key storage — code + error-path tests ✅ (device persistence pending)
- [x] iOS Keychain — code + error-path tests ✅ (device persistence pending)
- [ ] Android notification physical-device tests PASS — ⛔ device
- [ ] iOS notification physical-device tests PASS — ⛔ device
- [ ] lifecycle tests PASS — ⛔ device (kill/reopen walk)
- [x] migration tests PASS (plain AND encrypted scope)
- [ ] real-device backup/restore PASS — ⛔ device (sandbox encrypted round-trip ✅)
- [x] corrupted backup is safely rejected (sandbox evidence; device leg pending)
- [x] DST spring/fall logic tests PASS (device timezone-change check pending)
- [ ] timezone-change tests PASS — ⛔ device
- [x] security review PASS (re-run on final tree)
- [x] final analyze PASS
- [x] final full test suite PASS (315/315)
- [x] evidence matches final source tree (regenerated this session)
- [x] CI targets this Flutter project; APK artifact pipeline wired; SQLCipher proof greppable in CI log

**P7 overall: NOT COMPLETE — by design. Every code-level item implementable without a device is implemented and tested (P7.1 both blockers, P7.2 real SQLCipher with fail-closed semantics, P7.3/P7.4 production SecretStore, CI per P7_fix2). The remaining unchecked boxes are exactly the physical-device gates; they cannot be honestly claimed from this sandbox.**

## 9. Next actions to close P7

1. Push to GitHub → `test.yml` (green run = P7.2 CI proof) + `build-debug-apk.yml` (APK artifact).
2. Install the debug APK on a physical Android 13+ device → work the rows of `doc/mobile_readiness.md` (now including migration/encrypted-DB/reboot rows 2/3/4/7).
3. Close the P7.2 device leg: copy DB → plain SQLite → unreadable; wrong-key open on device; kill/reopen with Keystore key.
4. iOS: same on an iPhone (dev build/TestFlight); record M2 status honestly.
5. Regenerate this evidence file after the device cycle; only then proceed to P8.
