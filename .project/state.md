# Project State — ShiftEase

> Trạng thái project tại thời điểm cập nhật. File chính thức theo dõi phiên: `.project/working.md`.
> Cập nhật: 2026-09-11 (**EN-language pass** — toàn bộ UI text user-facing chuẩn tiếng Anh, tests cập nhật theo; **AdMob App Open + Interstitial wired**: App Open cold start, Interstitial sau import commit, Rewarded chưa có placement; analyze sạch, 343/343. Trước đó: PayRule versioning UX (340/340), AdMob production Android IDs (test_ads=true), AdMob banner + UMP, P0 fix mobile DB path, CI-APK session (targetSdk 36, Sentry, icon), P8/P9 prep complete — KHÔNG claim PRODUCTION LIVE).

## 1. Vị trí trên roadmap

```
Gate 0–3 (core engines) ✅ → M1 ✅ → M1b ✅ → M2 ✅ → Gate A/B ✅ → Gate C ✅
  → plan8 RC batch (✅ HOÀN TẤT A–J) → human review RC → mở deferred §14 / closed testing
```

Plan file: `.plan/plan8_m3_income.md` — "Release Candidate Batch — M3 Income + Integrity + Production Readiness" (trạng thái: **THỰC THI XONG TOÀN BỘ §15 A→J**). Không mở OCR/Cloud/AI trong batch này (§14 deferred).

## 2. Tiến độ plan8 (thứ tự thực thi §15)

| Phase | Nội dung | Trạng thái |
|---|---|---|
| A — Integrity | A1 UI write error boundary · A2 imported-only CREATE · A3 materialized occurrence (scoped REPLACE) · A4 import state machine verify · A5 import conflict OFF+SHIFT/duplicate · A6 override reordered-payload compare · A7 atomic re-version fail-before/restart · A8 PayRule integrity | ✅ A1–A8 |
| B — Income engine + dashboard | B1 estimator parity (HOURS_IN_WINDOW, goldens PAY-013/overnight/DST) · B2 per-occurrence rule + multi-version WEEK→UNAVAILABLE · B3 income breakdown screen · B4 range/week/month · B5 template library presets (US-CA/US-NY/US-TX/UK-NHS/DE) · B6 Income Impact (persist:false) · B7 multi-job total | ✅ B1–B7 |
| C — CSV + re-import diff | C1 CSV mapping UI (service `parseCsv` + ImportScreen CSV mode: preview → map columns → validate → review → commit) · C2 re-import diff card (added/removed/modified/unchanged + hoursDelta + income impact) | ✅ C1/C2 (UI + service) |
| D — DST final UX | Real resolution: chọn interpretation fall-back (RadioGroup, không auto-select) → offsets persist vào override payload; spring gap vẫn chặn | ✅ |
| E — Notifications | E1 stale cancellation (no-upcoming → CANCEL, fixed id) · E2 lifecycle resync (RESUME → re-sync) · E3 POST_NOTIFICATIONS manifest + runtime request | ✅ E1/E2 code+test · E3 **device BLOCKED** |
| F — Backup/Restore | schema+version+checksum+every table; restore validate→txn rollback; verify row counts; deleteAllData | ✅ (7 test) |
| G — SQLCipher/key | key gen 64-hex secure RNG · SecretStore seam · `verifyEncryption` probe (plain build báo NOT encrypted THẬT) | ✅ structure (7 test) · **native device BLOCKED** |
| H — Settings screen | General/Notifications/Data (backup/restore/delete-all)/Privacy+encryption status/About + gear icon Jobs | ✅ (3 test) |
| I — Mobile readiness | `doc/mobile_readiness.md` — structure checklist + 15-row device/CI matrix | ✅ doc · **verify BLOCKED toàn bộ** (không claim PASS) |
| J — Adversarial/regression | rc_adversarial_test.dart (migration fail, stale, ERROR→COMMIT, malformed date, CREATE→UPDATE→DELETE, negative rate, multi-version, no-upcoming cancel, backup corrupt/schema/key/rollback/round-trip) | ✅ (13 test) |
| Evidence/docs/handoff | `result16_rc.txt` · checklist/features/next đồng bộ · handoff | ✅ (`result16_rc.txt` trên đĩa, `ls` xác nhận) |

## 3. Test hiện tại (bằng chứng chạy lại 2026-09-11, sau mọi thay đổi — gồm SQLCipher rev 2)

- `flutter analyze --no-pub` → **No issues found!**
- `flutter test test/` → **315/315 pass (exit=0)** — chi tiết delta: 288 → 292 (polish L1/L2/L3) → 297 (P7.1 H1/M1) → **315** (P7.2 security-gate viết lại 17 test trên file mã hoá thật +10, backup/restore encrypted +2, SecureSecretStore error-path +6; adversarial viết lại giữ nguyên 13)
- Suite chạy trên **SQLCipher 4.18.0 thật** (build hook — mọi test DB file là encrypted); `dart run tool/cipher_proof.dart` → `P7.2 OK`

| Nhóm | Số | Chi tiết |
|---|---|---|
| Core | **213** | time 32 · pattern_engine 48 · property 7 · money 24 · import 30 (engine 23 + rc_csv_diff_validation 7) · db 39 (Gate C + backup_restore 7 + security_gate 7 + A6/A8) · integration 26 (19 + rc_imported_create 3 + rc_materialized 4) · adversarial 17 (Gate C 4 + RC J 13) |
| Domain | **18** | schedule_service 7 · income_estimate 10 · import_composition 1 |
| UI | **33** | M1 2 · M1b 4 · M2 5 · DST 4 (1 rework) · Pay/Income 2 · write_error_boundary 4 · income_breakdown 3 · income_impact 2 · pay_preset 1 · rc_csv_diff_flow 4 · settings_flow 3 |
| Features | **12** | ICS 2 · shift_reminder 4 + shift_reminder_rc 6 |

So với baseline RC (249/249 giữa batch): **+39 test** (C UI 4 · D +1 rework · E1/E2 6 · F 7 · G 7 · H 3 · J 13 + phân bổ lại per-dir). Regression 0 (249 → 288).

## 4. File mới trong RC (lib, sau Phần A/B)

- `lib/core/db/backup_restore.dart` (F — backup JSON schema+version+checksum, restore transactional rollback)
- `lib/core/db/security_gate.dart` (G — generateEncryptionKey, SecretStore seam, verifyEncryption probe)
- `lib/features/settings/settings_screen.dart` (H — General/Notifications/Data/Privacy/About)
- `doc/mobile_readiness.md` (I — structure checklist + 15-row device/CI matrix BLOCKED)

## 5. File lib sửa đổi trong RC (phần sau, chính)

`schedule_service.dart` (C1 `parseCsv` + C2 `committedRosterRows`/`estimateRosterDiffImpact`), `import_screen.dart` (CSV mode + validation card + diff card), `time_engine.dart` + `dst_resolution_dialog.dart` + `occurrence_sheet.dart` + `override_actions.dart` + codec (D — real DST resolution, offsets persist), `shift_reminder.dart` (E1 cancel), `today_screen.dart` (E2 WidgetsBindingObserver resync), `AndroidManifest.xml` (E3 POST_NOTIFICATIONS).

## 6. Đang dở / chặn

- **Không có việc code dở trong batch** — mọi task §15 A→J đã code + test; P7 phần sandbox cũng xong (evidence rev 2).
- **BLOCKED (device ngoài sandbox):** E3 permission flow thật (Android 13+) · P7.2 device leg (negative test copy-DB→plain-SQLite, reinstall recovery) · P7.3/P7.4 persistence qua kill/reboot · I 15-row matrix (migration, encrypted DB, notification, restart/reboot, timezone, DST, backup/restore, import, override, PayRule, lifecycle). Chi tiết unblock: `doc/mobile_readiness.md` + `result_p7_production_verification.md` §9.
- **CI đã sửa đúng project (P7_fix2, P8.0 verify):** `test.yml` = `flutter test` trên Flutter root (+ `tool/cipher_proof.dart` named step — green CI run = chứng cứ SQLCipher P7.2) · `build-debug-apk.yml` APK artifact mở cả rows 2/3/4/7. Cần push GitHub để kích hoạt.
- **P9 launch prep complete (2026-09-11, `result_p9_launch.md` — waiver device/signed/closed do user phát hành trong `prompt_p9.md`, waiver ≠ PASS):** `doc/release/final_release_gate.md` (GATE OPEN — 4 điều kiện trước submit thật) · submission_record (checksum/no-rebuild) · staged_launch (halt criteria) · monitoring + triage (nguồn thật: store console/support/canary — không thêm analytics SDK) · hotfix_procedure (minimal, no feature) · data_loss_incident (NEVER xóa DB first response) · first_production_review template · post_production_backlog (9 items list-only) · **còn lại = P9 nhóm B (human): push → CI xanh → signed → submit → staged rollout → monitor → review → LIVE**
- **Git:** repo init 2026-09-11 (trước đó không có git) — branch `ci/p8-flutter-ci-evidence`, commit `2253ea7` (256 files; .gitignore loại build artifacts + signing secrets + result*.txt scratch)
- **P8 prep complete (2026-09-11, `result_p8_release_candidate.md` — verified lại theo p8_fix1):** reviewer p8_fix1 nghi "CI vẫn cũ `source/`" = checkout stale — disk của working tree xác nhận `test.yml` 8 jobs Flutter root (7286 bytes) + `build-debug-apk.yml`, 4 lệnh local PASS (analyze --fatal-infos sạch · **315/315** · cipher_proof SQLCipher 4.18.0) · freeze `doc/release_freeze.md` · version 1.0.0+1 + app name **ShiftEase** thống nhất 2 nền tảng (đã sửa lệch) + release path sạch · smoke/upgrade checklists `doc/release/` (NOT RUN honesty) · store/privacy drafts chỉ feature thật (không network permission = "no data collected" kiểm chứng được) · protocols P0–P3 · signed build **BLOCKED needs keys** · **CI: on disk ✅ / GitHub run chưa (đợi push)** · **P8 nhóm B = human/device: signed AAB/iOS, smoke/upgrade thật, internal + closed testing — đủ thì mới P9**.
- Kỷ luật giữ nguyên: **không build apk local**.

## 7. Cần hỏi user

1. **Human review release-candidate** toàn bộ batch A–J (bằng chứng: `result16_rc.txt` + 288/288) — review độc lập như plan10 đã làm?
2. Sau review: mở **deferred §14** (OCR/M4.5 spike — cần 20–30 roster thật · Cloud · Sharing) hay **closed testing** trước?
3. Device/CI verification (E3/G/I): chạy trên máy user/CI khi nào — cần hướng dẫn build CI (GitHub Actions) không?
