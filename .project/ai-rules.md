# AI Rules — ShiftEase Project

> Auto-generated rules capturing project conventions.
> Update this file whenever project structure or conventions change.

## Project Info

- **Project**: ShiftEase
- **Type**: Flutter (Dart) application
- **Path**: `/home/dinhxhoang08/htdocs_apps/ShiftEase`
- **Language**: Dart (Flutter 3.47.1 stable, Dart 3.13.1)
- **Description**: Personal Operating System for Shift Workers — Work/Life/Money pillars

## Code Location

- **Main code**: `lib/`
- **Core engines**: `lib/core/{time,pattern,money,import,db}/`
- **Domain layer**: `lib/domain/`
- **Features/UI**: `lib/features/{jobs,templates,pattern_builder,calendar,occurrence,today,import,common,pay,income,export,notifications,ads,settings}/`
- **Config**: `lib/config/ads_config.dart` (ads master flags — `ENABLE_ADS`/`TEST_ADS` override qua `--dart-define`)
- **App shell**: `lib/app/`
- **Tests**: `test/config/`, `test/core/`, `test/domain/`, `test/features/`, `test/ui/`
- **Android config**: `android/app/build.gradle.kts` (targetSdk 36, signingConfig release, proguardFiles), `android/app/proguard-rules.pro` (**required**: keep constructor Room)
- **CI**: `.github/workflows/{test,build-debug-apk,build-release-apk,build-release-aab}.yml` — build APK/AAB **chỉ trên CI**, không bao giờ ở local
- **Tooling**: `tool/` (build-hook & guard script Python/Dart), `doc/release/`, `store_assets/`

## Plan Files

- Plans: `.plan/plan1_final_v2.md` → `.plan/plan8_m3_income.md` (plan8 = Release Candidate batch, **HOÀN TẤT A–J 2026-09-08**)
- Documents: `.plan/features.md`, `.plan/plan_gate_c.md`, `doc/mobile_readiness.md`

## Result Files

- `result1.txt` through `result20_code_review_p9.txt` (16 = RC batch A–J; 17 = RC review; 18 = code review + polish addendum; 19 = P8 review; 20 = P9 review; `result16_rc_progress.txt` = snapshot giữa batch)
- Result phiên sau RC: `result_p0_db_path_mobile.md` · `result_p7_production_verification.md` · `result_p8_release_candidate.md` · `result_p9_launch.md` · `result_admob_integration.md` · `result_payrule_version_ux.md` · `result_phase_design_audit.md`
- Handoff mới nhất: `handoff_20260910_rc_complete.md` · `checklist.md`, `next.md` (⚠️ **chưa sync** từ 2026-09-12)
- `chplay.md` (Play submission pack) · `store_assets/` (icon/feature graphic/privacy/user guide)
- Trạng thái: `.project/state.md` + `.project/working.md` + `.project/openspec_entry.md`

## Coding Conventions

- Flutter widget tests use `flutter test`
- Core tests use `dart test test/core/`
- Domain tests: `test/domain/schedule_service_test.dart`
- UI tests: `test/ui/{m1,m1b,m2_import,dst_resolution,pay_income,pay_preset,income_breakdown,income_impact,write_error_boundary,rc_csv_diff,settings}_flow_test.dart`
- Use MaterialApp wrapper in widget tests
- Use real SQLite in-memory DB for tests
- Analyzer: `flutter analyze` — no warnings, no errors
- Golden test verification scripts: `scripts/verify_*_cases.mjs`

## Test Commands

```bash
# Local gate (KHÔNG build APK ở local — không có toolchain; build ở CI)
flutter analyze --no-pub --fatal-infos   # clean (15.4s @ 2026-09-12)
flutter test test/                       # 343/343 pass (exit=0)

# Per-directory (2026-09-12)
flutter test test/config/                # 12 tests
flutter test test/core/                  # 247 tests
flutter test test/domain/                # 28 tests
flutter test test/features/              # 16 tests
flutter test test/ui/                    # 40 tests
```

Device verification (khi có máy thật + adb): cài artifact release rồi `adb logcat -b crash -d` (phải rỗng) + `adb shell pidof com.shiftease.shiftease` + `dumpsys activity | grep ResumedActivity` — chi tiết trong `.agents/skills/shiftease-ci-apk/SKILL.md`.

## Roadmap Status

**Completed gates:**
- Gate 0: core/time (32 tests) + core/pattern (53 tests)
- Gate 1: core/money (24 tests)
- Gate 2: core/import engine (15 tests)
- Gate 3: core/db v2+v3 (14 tests) + integration 19 tests
- Gate M1: Flutter app + domain service + Jobs/Templates/PatternBuilder/Calendar/Occurrence (5 domain+UI tests)
- Gate M1b: Today/Month/Quick Add/re-version UI (4 widget tests)
- Gate M2: Import UI — Smart Paste → Review → Commit → calendar seam (5 widget tests)
- Gate A/B: production composition · atomic commit+rollback · window semantics · SWAP effectiveJobId · partial-commit dialog · version immutability (179)
- Gate C: integrity A1–A5 + product B1–B5 (DST dialog · income estimate + PayRule editor · ICS export · reminder baseline · platform folders) (207)
- RC plan8 (2026-09-08): A Integrity A1–A8 · B Income B1–B7 · C CSV UI + diff card · D DST real resolution · E notifications (E3 device BLOCKED) · F backup/restore · G security gate (device BLOCKED) · H settings · I mobile readiness doc (verify BLOCKED) · J adversarial +13
- RC review 2026-09-10: result17 (plan-conformance PASS) + result18 code review — L1/L2/L3 fixed (+4 test); H1/M1/M2/L4 tracked trong `doc/mobile_readiness.md` mục Code-review backlog (H1 = blocker trước store release)

- Release packaging 2026-09-12 (`main` @ `a1d9b0c`): 4 workflow GH Actions (test · debug APK · release APK · release AAB ký keystore cố định) — 5/5 run xanh; guard `check_manifest_ads.py` + `check_r8_keep.py`; 2 crash P0 lúc mở app (**chỉ hiện ở release**) đã fix + verify trên máy thật (Pixel 3a/Android 12)

**Total: 343 tests pass** (core 247 + config 12 + domain 28 + UI 40 + features 16) — verify 2026-09-12 bằng `flutter analyze --no-pub --fatal-infos` (sạch) + `flutter test test/` (exit=0).

**Next steps:**
- **Play Console**: điền form theo `chplay.md` → bump `versionCode` → upload **AAB ký release**
- Device matrix 15 dòng (`doc/mobile_readiness.md`): E3 permission · G SQLCipher native · P7.2–P7.4 persistence · I matrix — **không claim PASS** khi chưa chạy
- iOS P8.4 (cần macOS + certs) · sau đó deferred §14 (OCR/M4.5 spike · Cloud · Sharing) hoặc closed testing

## Key Decisions (locked)

1. **Platform**: Flutter app (root → Flutter)
2. **No UI dependencies** — only Flutter SDK, no riverpod/bloc
3. **Architecture**: 5-layer (platform/features/domain/data/core), `core/` UI-free
4. **Import = primary source** for days it covers (D-M2-1 A)
5. **Review mandatory** before commit (INVARIANT-004)
6. **Correctness Contract**: deterministic results, no silent guesses
7. **Time**: UTC for all calculations, local civil time for display
8. **Pattern never mutates** (INVARIANT-001)
9. **Pay**: Method B (separate regular + OT), LIFO weekly allocation, max() for multi-rule OT
10. **Offline-first**: SQLite local DB, no cloud/account in core
11. **Platform folders** `android/` + `ios/` đã tạo (Gate C B5) kèm `path_provider` + `flutter_local_notifications`; **KHÔNG build apk ở local** (sandbox không toolchain) — verify device/CI ngoài sandbox
12. **Backup/Restore** (RC F): restore = validate → transaction (children-first drop + re-insert + user_version bump) → rollback khi fail → verify row counts
13. **Security honesty** (RC G): `verifyEncryption` probe báo THẬT trạng thái encryption — plain build phải báo "NOT encrypted", không bao giờ fake "secure"
14. **Commit UI gate** (RC review L1): nút Commit chỉ enable ở state REVIEWING — engine từ chối EXTRACTED→COMMIT nên UI không được mời user bấm vào lỗi chắc chắn
15. **Review-findings discipline**: finding của code review phải vào backlog docs (`doc/mobile_readiness.md` mục Code-review backlog + next.md) nếu không fix ngay — không để mất trong result*.txt
16. **Ads có 2 công tắc độc lập, chỉ ở Dart** (`--dart-define`): `ENABLE_ADS=false` = không init SDK; `TEST_ADS=true` = dùng unit test của Google. **Manifest LUÔN mang `APPLICATION_ID` hợp lệ** — làm rỗng không phải là "tắt ads" mà là crash mọi lần mở app (ContentProvider của SDK validate trước `Application.onCreate()`)
17. **R8 minify luôn BẬT cho release** (Flutter plugin set `isMinifyEnabled = true`); cấm `isMinifyEnabled=false` để "cho build qua". Thiếu keep rule → thêm vào `android/app/proguard-rules.pro`. Rule bắt buộc hiện tại: `-keep class * extends androidx.room.RoomDatabase { <init>(); }` (WorkManager/Room vào qua ads SDK, auto-init qua `androidx.startup`)
18. **Build xanh ≠ đã verify.** Gate release = cold-start artifact **ký release** trên máy thật/máy user + crash buffer rỗng. Mọi bug "cài được nhưng mở là crash" phải debug bằng `adb logcat -b crash` với máy thật, không suy luận từ code
19. **Verify artifact bằng parse giá trị thật** (attribute AXML/protobuf manifest, `usage.txt` của R8) — KHÔNG dùng `strings | grep` (string pool UTF-16 → báo OK giả; đã để lọt bug 2 lần)
20. **Đừng "cho qua" bằng cách bịt triệu chứng** (blank value, tắt minify): sửa nguyên nhân + thêm guard CI để lớp bug đó fail build về sau

## Invariants

- INVARIANT-001: Pattern never mutates because an occurrence is edited
- INVARIANT-002: Duration always from resolved UTC instants
- INVARIANT-003: Local civil time is basis for recurrence
- INVARIANT-004: Imported data never commits without user confirm
- INVARIANT-005: ShiftTemplate only time/UI — no pay semantics
- INVARIANT-006: Historical pay estimates are immutable snapshots
- INVARIANT-007: Occurrence keeps original timezone
- INVARIANT-008: Core calendar works completely offline

## Working Memory

See `.project/working.md` for current task status, pending decisions, and session tracking.
