# Phase Design ↔ Code Audit — ShiftEase

> Auditor: Buffy (independent reviewer role) · Date: 2026-09-11 · Sandbox: `/home/dinhxhoang08/htdocs_apps/ShiftEase` (git: branch `ci/p8-flutter-ci-evidence`, commit `2253ea7`).
> Method: filesystem-first. Mọi claim trong checklist/result được đối chiếu với code mở trực tiếp (không tin result file). Greps bắt buộc đã chạy đủ 7 nhóm. Analyze/test/cipher_proof chạy thật trong session này.
> Verdict per finding: **CODE MATCH** · **CODE DRIFT** · **UNVERIFIED** (cần device/CI, không PASS giả) · **WAIVED** (user bỏ qua — không phải PASS) · **DOC LIE / STALE CLAIM**.

## 1. Executive summary

- **Overall: MOSTLY MATCH.** Không tìm thấy P0/P1 drift trong code: các invariant cốt (review-before-commit, atomic re-version, fail-closed SQLCipher, no systemTemp backup, UNAVAILABLE-not-partial income, append-only override) đều có thật trong code kèm test. Các claim sai trong docs đã được phát hiện và sửa trong các phiên P8_fix1/P9-review trước đó; audit này không tìm thấy claim sai còn tồn tại trên disk hiện tại.
- **Top 5 risks (thứ tự ưu tiên):**
  1. **CI chưa từng chạy trên GitHub** — mọi claim "CI green = proof" đều là tiềm năng, chưa thực tế (P2, blocker đầu tiên của human).
  2. **Device legs waived**: SQLCipher-negative-on-device, Keystore persistence, notification matrix, lifecycle — code ready nhưng chưa từng chạy trên máy thật (P2, user waiver, không phải PASS).
  3. **ICS saver còn fallback systemTemp** (F-001, P3) — hữu ý khác backup nhưng là 1 trong 2 chỗ systemTemp còn lại trong lib/.
  4. **SecretStore platform options chưa verify trên thiết bị thật** (P7.3/P7.4) — toMap() contract test chỉ证明 payload đúng, không证明 Keystore thật hoạt động (P3, waived).
  5. **Signed release config chưa có** — build.gradle.kts release còn debug-signing scaffold (P2, đã document trong build_notes).
- **Production-ready (honest)?** Chưa — vẫn thiếu: ≥1 CI run xanh, signed build, smoke/upgrade trên máy thật. Code tree thì đạt mức RC-clean; các bước còn lại đúng như final_release_gate.md §4.

## 2. Phase matrix

| Phase | Design intent | Code status | Docs claim | Verdict | Evidence (paths) |
|---|---|---|---|---|---|
| P0 Time | UTC duration; DST không auto-pick sai | Engine resolve: nonexistent → lỗi tường minh; ambiguous → 2 candidates + preference chỉ áp khi ambiguous (không đoán) | DONE | **CODE MATCH** | `lib/core/time/time_engine.dart:46–159`; golden `test/golden/time_engine_cases.json` + Node cross-check trong CI |
| P0 Pattern | versioning, override append-only, no mutate | `_savePatternNoTxn` chặn same-id re-save khác payload (so cả sequence); version mới = row mới | DONE | **CODE MATCH** | `lib/core/db/pattern_repository.dart:157–199` |
| P0 Money | MAX-not-sum; thiếu rule → rõ ràng | Overtime = MAX 2 components (money_engine.dart:17,106,157); `WeekIncomeEstimate.unavailable(reason)` + `IncomeImpact.unavailable` | DONE | **CODE MATCH** | `lib/core/money/money_engine.dart`; `lib/domain/income_estimate.dart:50–90` |
| P0 Goldens | tồn tại + chạy trong CI | 3 Node scripts (time/money/import) chạy như named steps trong per-engine jobs | OK | **CODE MATCH** | `.github/workflows/test.yml` jobs core-time/money/import |
| P1 Seam | ScheduleService = seam duy nhất | UI import qua service.commitRoster; repos không bị UI gọi trực tiếp (dependency-rule guard trong CI chặn ngược) | DONE | **CODE MATCH** | `lib/domain/schedule_service.dart:569+`; dependency-rule step test.yml |
| P2 Re-version | atomic một transaction | changeRosterFrom: BEGIN → savePatternInTransaction ×2 → COMMIT/ROLLBACK; repo không tự BEGIN khi caller owns | DONE | **CODE MATCH** | `lib/domain/schedule_service.dart:670–694`; `pattern_repository.dart:147–156` |
| P3 Import gate | chỉ REVIEWING→COMMIT | `commitImport` throw illegalState nếu state != reviewing; UI `_canCommit` gate riêng; empty-actionable cũng từ chối | DONE | **CODE MATCH** | `lib/core/import/import_engine.dart:402–449`; `import_screen.dart:898–902` |
| P3 Atomic commit | session + occurrences một txn | commitRoster: engine fail-atomic trước; sau đó saveSession + replaceImportedOccurrences trong ONE transaction | DONE | **CODE MATCH** | `lib/domain/schedule_service.dart:565–609+` |
| P4 CSV/diff | UNAVAILABLE, không partial | resolveAll trả error → IncomeImpact.unavailable (P7.1 M1), reason nêu row/date; OFF hợp lệ | DONE (M1 closed) | **CODE MATCH** | `schedule_service.dart:186–200` |
| P5 Income | template no-pay; disclaimer; multi-job chỉ cộng AVAILABLE | INVARIANT-005 ở money_types + template UI; breakdown disclaimer 'Ước tính — không phải bảng lương chính thức'; multi-job = sum các estimate với available=true, unavailable → không cộng + reason giữ nguyên | DONE | **CODE MATCH** | `money_types.dart:7,143`; `income_breakdown_screen.dart:15`; `income_estimate.dart` |
| P6 Write boundary | không crash nuốt lỗi | write_guard.dart runWrite/runWriteAsync → message; QuickAdd + import commit test chứng minh exception không thoát handler | DONE | **CODE MATCH** | `lib/features/common/write_guard.dart:42–55`; `test/ui/write_error_boundary_test.dart` |
| P6 Override same-id | identical idempotent / different throw | business_repository: identical = no-op; khác payload = ImmutableHistoryError (comment dòng 83, 168, 326) | DONE | **CODE MATCH** | `lib/core/db/business_repository.dart:29–96,324–350` |
| P6 Backup | transactional + corrupt reject + không systemTemp | BEGIN/COMMIT/ROLLBACK (backup_restore.dart:180–203); production dir = getApplicationSupportDirectory, refusal khi resolver fail | DONE | **CODE MATCH** | `backup_restore.dart`; `settings_screen.dart:42–81` |
| P6 Encryption seam | fail-closed; InMemory chỉ test | defaultOpener refuse plain keyed path + cipher_version check; InMemorySecretStore chỉ trong lib/core/db (test double, không wire vào main); main.dart dùng SecureSecretStore + recovery screen | DONE (code) | **CODE MATCH** (device = UNVERIFIED→WAIVED) | `db.dart:54–134`; `security_gate.dart`; `main.dart:96–130` |
| P6 Reminder | cancel/resync, không claim device | cancelReminder swallow MissingPlugin có chủ ý (comment: "nothing to cancel"); E2 resync qua WidgetsBindingObserver (today_screen.dart:58–59) | DONE code | **CODE MATCH** (device UNVERIFIED→WAIVED) | `shift_reminder.dart:138–144`; `today_screen.dart:58` |
| P7 H1/M1 | đóng trong code | H1: no systemTemp fallback + resolver seam + refusal; M1: resolveAll + UNAVAILABLE | DONE | **CODE MATCH** | `settings_screen.dart`; `schedule_service.dart`; tests P7.1 |
| P7 SQLCipher | pubspec hook + refuse plain | hooks.user_defines `source: sqlcipher`; opener refuse plain keyed path; cipher_proof chạy thật (SQLCipher 4.18.0) | CODE READY | **CODE MATCH**; device leg UNVERIFIED→WAIVED | `pubspec.yaml:33–36`; `db.dart:73–134`; `tool/cipher_proof.dart` |
| P7 Device gates | ghi UNVERIFIED đúng | result_p7 ghi BLOCKED/WAIVED, không PASS | honest | **CODE MATCH** (docs) | `result_p7_production_verification.md` §5 |
| P8 CI | Flutter root, không source/ | 8 jobs, tất cả `flutter test`, 0 hit `dart test`/`source/` (chỉ comment lịch sử dòng 4) | on-disk PASS | **CODE MATCH**; **GitHub green = UNVERIFIED** | `.github/workflows/test.yml` |
| P8 build-debug-apk | tồn tại nếu claim | tồn tại (2558 bytes, 1 job, gate analyze+test trước build, không keystore) | exists | **CODE MATCH** | `.github/workflows/build-debug-apk.yml` |
| P8 Store/privacy | không quảng cáo feature chưa ship | store_assets + privacy chỉ nêu feature thật; sau review P8 (M1) đã sửa overclaim backup-sharing | PASS (draft) | **CODE MATCH** | `doc/release/store_assets.md`; `doc/release/privacy.md` |
| P8 Nhóm B | BLOCKED trừ có evidence | signed/smoke/closed = BLOCKED/waived trong result_p8 | honest | **CODE MATCH** (docs) | `result_p8_release_candidate.md` §6 |
| P9 Ops docs | đủ 9 files | 8/8 files trong doc/release + result_p9 tồn tại (loop verify OK toàn bộ) | LAUNCH PREP COMPLETE | **CODE MATCH** | `doc/release/*`; `result_p9_launch.md` |
| P9 Status | không claim LIVE | result_p9 ghi "PRODUCTION NOT LIVE"; NEVER-xóa-DB + no-feature-hotfix có trong docs | honest | **CODE MATCH** | `result_p9_launch.md:6,72` |

## 3. Findings

### F-001
- **Phase:** P6/P7 · **Severity:** P3
- **Expected (design):** mọi file dữ liệu durable ghi vào persistent storage (H1 spirit)
- **Actual (code):** `lib/features/export/ics_saver.dart:21` — fallback `Directory.systemTemp` khi path_provider fail (ICS export)
- **Impact:** thấp — ICS được ghi rõ "NOT a backup" (settings_screen comment; privacy.md); mất file ICS không mất data app. Còn lại 1/2 systemTemp hit trong lib/ (backup path đã sạch).
- **Recommended fix:** nếu muốn đồng bộ chuẩn H1: đổi fallback thành return null + snackbar lỗi ("export unavailable") thay vì ghi vào cache. Không blocker.

### F-002
- **Phase:** P7/P8 · **Severity:** P2 (process)
- **Expected:** evidence "CI green" là proof P7.2 trên remote
- **Actual:** CI đúng trên disk nhưng **chưa có bất kỳ run nào trên GitHub** (remote chưa tồn tại) — mọi claim "green run IS proof" là điều kiện tương lai, không phải hiện thực
- **Path:** `.github/workflows/*`; `result_p8_release_candidate.md` KI-1 (đã ghi đúng)
- **Impact:** process — không ai được trích dẫn "CI đã chứng minh" cho tới khi run đầu tiên xanh
- **Recommended fix:** human push + xác nhận run xanh; cập nhật KI-1 sau đó.

### F-003
- **Phase:** P8.3 · **Severity:** P2 (process)
- **Expected:** signed release build tồn tại trước store
- **Actual:** `android/app/build.gradle.kts:36` buildType release còn `signingConfig = signingConfigs.getByName("debug")` (scaffold); chưa có keystore
- **Impact:** build release hiện tại sẽ bị Play từ chối; đã cảnh báo trong `doc/release/build_notes.md` §1.2 (review P8 M2)
- **Recommended fix:** human tạo keystore + signingConfigs.release từ key.properties (gitignored) trước build AAB đầu tiên.

## 4. Doc / claim mismatches

- Không tìm thấy DOC LIE / STALE CLAIM còn tồn tại trên disk hiện tại: các claim sai lịch sử (CI `source/` — p8_fix1; backup overclaim — P8 review M1; freeze date — L1) đều đã được sửa và audit này verify lại đĩa.
- Lưu ý đồng bộ: `checklist.md`/`next.md`/state.md có sửa chưa commit (3 files modified) + docs P9/untracked — **không phải mismatch**, chỉ là working tree chưa commit.
- Greps đối chiếu với claims legacy: "no debug endpoint/mock" — xác nhận sạch (match duy nhất là comment guard); "InMemory chỉ test" — xác nhận (main.dart wire SecureSecretStore).

## 5. CI & security snapshot

- **Workflows:** `test.yml` = Flutter root, 8 jobs (static-analysis + dependency-guard, 4 per-engine + 3 Node golden cross-checks, persistence với `dart run tool/cipher_proof.dart`, ui/domain, full-suite gate), `workflow_dispatch`, paths lib/test/pubspec/lock/android/ios/scripts/tool/workflows. `build-debug-apk.yml` = 1 job, gate analyze+test trước build, artifact 14 ngày, không secrets.
- **Cipher:** SQLCipher 4.18.0 community link qua build hook (pubspec `source: sqlcipher`); fail-closed opener; refuse plain keyed open; `PRAGMA key` chỉ trong opener seam; key không log/backup.
- **Backup path:** production = `getApplicationSupportDirectory()` (resolver seam, refusal khi fail); zero systemTemp trên backup/restore path; ICS = 1 residual (F-001).
- **Import commit gate:** chỉ REVIEWING→COMMITTED; empty-actionable từ chối; fail-atomic; session+occurrences một transaction.

## 6. Test snapshot

- **analyze:** `flutter analyze --no-pub` → **No issues found!** (kể cả `--fatal-infos` ở phiên trước)
- **test count / fail:** `flutter test test/` → **315/315 All tests passed!** (exit 0)
- **cipher_proof:** `dart run tool/cipher_proof.dart` → **P7.2 OK: linked native build is SQLCipher 4.18.0 community**

## 7. Recommended next actions (ordered)

1. **Commit working tree hiện tại** (docs P9 + audit + 3 sync files) lên branch `ci/p8-flutter-ci-evidence` — để submission revision sau này bao trùm toàn bộ evidence.
2. **Push lên GitHub + xác nhận CI run xanh** (F-002) — đóng KI-1, đồng thời là proof P7.2-on-remote.
3. **Human: keystore + signing config** (F-003) theo build_notes §1.2 — rồi mới build AAB.
4. **(Optional, F-001)** đổi ICS fallback systemTemp → null + error message; +1 test.
5. **Device cycle** theo final_release_gate §4: smoke + upgrade + SQLCipher negative test — ngay cả khi đã waiver, khuyến nghị mạnh chạy trước submit.
6. Sau submit: theo `doc/release/staged_launch.md` + `monitoring.md`; không trộn feature.
