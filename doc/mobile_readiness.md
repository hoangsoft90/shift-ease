# Mobile Release Readiness — RC plan §I

> Status: **STRUCTURE READY — DEVICE/CI VERIFICATION BLOCKED** (sandbox has no
> Android/iOS toolchain or device; nothing here claims a device PASS).

## Platform structure (present in repo)

| Item | Location | Status |
|---|---|---|
| Android host app | `android/app/src/main/kotlin/com/shiftease/shiftease/MainActivity.kt` | ✅ present |
| Android manifest | `android/app/src/main/AndroidManifest.xml` | ✅ present — incl. `POST_NOTIFICATIONS` (§E3, Android 13+) |
| Android build | `android/` (gradle wrapper, settings.gradle.kts, build.gradle.kts) | ✅ present |
| iOS host app | `ios/Runner/` (AppDelegate.swift, Runner.xcodeproj, Assets) | ✅ present |
| Notifications plugin | flutter_local_notifications (Android + iOS impls) | ✅ wired (§E) |
| DB opener seam | `lib/core/db/db.dart` `DatabaseOpener` — **SQLCipher 4.18.0 thật** (build hook `source: sqlcipher`, fail-closed; `tool/cipher_proof.dart` in CI) | ✅ wired (§G, P7.2 rev 2) |
| Encryption probe | `lib/core/db/security_gate.dart` `verifyEncryption` | ✅ wired (§G/H) |
| CI | `.github/workflows/test.yml` — rewritten for the Flutter root (P7_fix2): `flutter test` everywhere + `tool/cipher_proof.dart` named step + full-suite gate | ✅ present |

## Device/CI verification matrix — BLOCKED (must run on device or CI)

Each row is a manual/CI check that **cannot be executed in this sandbox**.
Per plan §12: BLOCKED is recorded, never PASS.

| # | Check | Android | iOS |
|---|---|---|---|
| 1 | Fresh install → first launch creates + migrates DB | BLOCKED | BLOCKED |
| 2 | Existing DB migration (v1 → v3) on upgrade | BLOCKED | BLOCKED |
| 3 | Encrypted DB: SQLCipher linked, key in Keystore/Keychain, `verifyEncryption` → null | BLOCKED | BLOCKED |
| 4 | Wrong key → probe reports "wrong key", app refuses | BLOCKED | BLOCKED |
| 5 | Notification permission granted/denied → Settings status reflects it | BLOCKED | BLOCKED |
| 6 | Reminder fires after app restart | BLOCKED | BLOCKED |
| 7 | Reminder after reboot (if semantics require) | BLOCKED | BLOCKED |
| 8 | Timezone change → shifts re-resolve | BLOCKED | BLOCKED |
| 9 | DST spring/fall on device (real tz database) | BLOCKED | BLOCKED |
| 10 | Backup → file lands in app support dir → Restore round-trip | BLOCKED | BLOCKED |
| 11 | CSV import + commit on device | BLOCKED | BLOCKED |
| 12 | Override CREATE/UPDATE/DELETE on device | BLOCKED | BLOCKED |
| 13 | PayRule save + income estimate on device | BLOCKED | BLOCKED |
| 14 | App lifecycle: background → resume resyncs reminder (§E2) | BLOCKED | BLOCKED |
| 15 | Force-kill / reopen → data intact (SQLite WAL) | BLOCKED | BLOCKED |

## How to unblock

1. **CI (WIRED — rewritten for this Flutter root project 2026-09-11 per P7_fix2; needs a GitHub push to activate):**
   - `.github/workflows/test.yml`: **all jobs run `flutter test` on this project** (the old `dart test` + `libsqlite3-dev` steps targeted a previous Dart-only project and are gone); per-engine jobs + Node golden cross-checks + dependency-rule guard + the **full-suite** gate (`flutter analyze --fatal-warnings` + `flutter test test/`) + `workflow_dispatch`.
   - **P7.2 proof without a device:** every CI run compiles/links libsqlcipher.so via the build hook, the persistence job runs `dart run tool/cipher_proof.dart` (fails CI if the linked build is plain sqlite3), and the suite includes 17 security-gate tests on real encrypted file DBs — a green CI run IS the native-encryption evidence.
   - `.github/workflows/build-debug-apk.yml` builds a **debug-signed APK** (JDK 17 temurin + stable Flutter; no keystore secrets needed) and uploads it as the `shiftease-debug-apk` artifact (14-day retention) — install it on a device and work through the matrix rows below with the Settings screen as the probe UI. **SQLCipher ships inside the APK via the build hook, so rows 2/3/4 (migration/encrypted DB) and 7 (reboot) are now unlocked by this artifact too.**
   - Both workflows are validated YAML; they run on the next push to main/develop (or via workflow_dispatch).
2. **Android device**: install the debug APK artifact → run the matrix rows
   with the app's Settings screen as the probe UI.
3. **iOS device**: `flutter build ios` / `flutter run -d` on macOS → same rows
   (no CI runner for iOS builds in this repo yet).

## Code-review backlog (result18_code_review_rc.txt — open, not device work)

> **Update 2026-09-11 (P7 rev 2 — `result_p7_production_verification.md`):** H1 and
> M1 are **CLOSED**; P7.2 is now REAL SQLCipher 4.18.0 (fail-closed opener,
> 17 encrypted-file gate tests, `cipher_proof` CI step), P7.3/P7.4 have the
> production `SecureSecretStore` + error-path tests — 315/315. M2 (iOS permission
> status) stays open for the device cycle together with matrix row 5; L4
> stays documented-acceptable (resume resync covers it).

These were found in the 2026-09-10 RC code review. L1/L2/L3 were fixed
immediately (see result18 ADDENDUM); the following remain OPEN by user
decision and must close before store release:

| ID | Severity | Item | Where | Status |
|---|---|---|---|---|
| H1 | HIGH | Production backups write to `Directory.systemTemp` (purgeable cache dir) when `backupDir` is not injected — Jobs screen wiring passes none. Resolve `getApplicationSupportDirectory()` in the screen (path_provider already a dependency); keep the injectable param for tests. BLOCKS store release. | `jobs_screen.dart:42` · `settings_screen.dart _dir` | ✅ **CLOSED P7.1** — screen resolves the support dir (injectable `backupDirResolver`); unavailable storage → honest refusal, never temp; 2 new tests |
| M1 | MEDIUM | `estimateRosterDiffImpact` silently DROPS rows that fail to resolve (DST gap etc.) from the "After" leg → optimistic preview. Return `IncomeImpact.unavailable(...)` naming the row instead. | `schedule_service.dart estimateRosterDiffImpact → resolve()` | ✅ **CLOSED P7.1** — `resolveAll` → UNAVAILABLE naming row/date/tz/engine reason; 3 new tests (DST-gap/mixed/valid+OFF) |
| M2 | MEDIUM | iOS notification permission status always reports Unknown (only the Android impl is queried) — honest but decorative on iOS. Close together with matrix row 5 device work. | `shift_reminder.dart permissionStatus()` | OPEN — device cycle |
| L4 | LOW | Reminder window is Mon..Mon+13d — shifts >13 days out get no reminder until the window slides (E2 resume resync covers it). Document next to row 6 or widen the window. | `today_screen.dart _resyncReminders` | OPEN — documented-acceptable |

Also relevant to the device matrix: row 5 (permission status) should be
verified on BOTH platforms once M2 closes; row 10 (backup round-trip)
should be re-run after H1 closes to confirm the file lands in the support
directory — H1 closed 2026-09-10 (P7.1): the screen now writes the support
directory by construction, so row 10 on device verifies the wiring end-to-end.