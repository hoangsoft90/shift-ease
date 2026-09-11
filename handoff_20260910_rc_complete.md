# Handoff — ShiftEase — 2026-09-10 (plan8 RC batch HOÀN TẤT — đóng gói)

> Đọc file này trước tiên. Trạng thái: **plan8 Release Candidate batch A–J XONG** — full suite **288/288 pass, analyze clean** (verify lại 2026-09-10).
> Evidence chính thức: `result16_rc.txt` (2026-09-08) + `doc/mobile_readiness.md`. Phiên trước: `handoff_20260907_150715.md` (mid-batch — đã lỗi thời về tiến độ). Plan: `.plan/plan8_m3_income.md`.

## 1. Trạng thái cuối (evidence — không tin lời, tin file)

- `flutter analyze --no-pub` → **No issues found!** (chạy lại 2026-09-10, 19.3s)
- `flutter test test/` → **288/288 All tests passed! (exit=0)** — khớp `result16_rc.txt`
  - core **213** (time 32 · pattern_engine 48 · property 7 · money 24 · import 30 · db 39 · integration 26 · adversarial 17)
  - domain **18** (schedule_service 7 · income_estimate 10 · import_composition 1)
  - UI **33** (M1 2 · M1b 4 · M2 5 · DST 4 · Pay/Income 2 · write_error 4 · breakdown 3 · impact 2 · preset 1 · rc_csv_diff 4 · settings 3)
  - features **12** (ICS 2 · reminder 4 · reminder_rc 6)
- Baseline giữa batch: 249/249 → **+39 test, 0 regression**
- Files RC xác nhận trên đĩa (`ls -la`, mtime 2026-09-08): `lib/core/db/backup_restore.dart` · `lib/core/db/security_gate.dart` · `lib/features/settings/settings_screen.dart` · `doc/mobile_readiness.md` + 7 test file RC (`shift_reminder_rc` · `backup_restore` · `security_gate` · `settings_flow` · `rc_adversarial` · `rc_csv_diff_flow` · `dst_resolution_flow` rework).

## 2. RC batch — những gì đã đóng (chi tiết từng task: result16_rc.txt)

| Phase | Nội dung chính | Test |
|---|---|---|
| C1 | service `parseCsv` + ImportScreen CSV mode (preview → map columns → validate → review → commit) + validation card | 4 |
| C2 | `committedRosterRows` + diff card (+/−/~/= · hoursDelta · income impact persist:false) | (cùng file) |
| D | DST REAL resolution: RadioGroup chọn interpretation fall-back (không auto-select) → offsets persist vào override payload; spring gap vẫn chặn | 4 (1 rework) |
| E1/E2 | stale reminder CANCEL khi không còn upcoming (fixed id replace) · lifecycle RESUME → re-sync | 6 |
| E3 | POST_NOTIFICATIONS manifest + runtime request, honest status | **device BLOCKED** |
| F | `backup_restore.dart`: JSON doc schema+version+checksum+every table; restore validate → transactional (children-first) → rollback → verify row counts; `deleteAllData` | 7 |
| G | `security_gate.dart`: key gen 64-hex secure RNG · SecretStore seam · `verifyEncryption` probe (plain build báo "NOT encrypted" THẬT) | 7 · **device BLOCKED** |
| H | `settings_screen.dart` (General/Notifications/Data backup+restore+delete-all/Privacy+encryption/About) + gear icon Jobs | 3 |
| I | `doc/mobile_readiness.md` — structure checklist + 15-row device/CI matrix | **verify BLOCKED toàn bộ** |
| J | `rc_adversarial_test.dart` — migration fail · stale · ERROR→COMMIT · malformed date · CREATE→UPDATE→DELETE · negative rate · multi-version · no-upcoming cancel · backup corrupt/schema/key/rollback/round-trip | 13 |

## 3. Việc này làm gì (phiên đóng gói 2026-09-10 — không code mới)

1. Verify lại bằng chứng: analyze clean + 288/288 (khớp `result16_rc.txt`) + `ls` files RC.
2. Sync docs còn stale: `.project/state.md` · `.project/working.md` · `next.md` · `.project/openspec_entry.md` · `.project/ai-rules.md` (số test 249 → 288, tiến độ A–J ✅, M2b đóng).
3. Handoff này. Checklist.md + `.plan/features.md` đã đồng bộ từ phiên 2026-09-08.

## 4. Việc tiếp theo (chờ quyết định user — KHÔNG tự mở code mới)

1. **Human review release-candidate** toàn bộ batch A–J (độc lập, kiểu review plan10: đối chiếu source thực tế với plan + result16_rc.txt).
2. **Device/CI verification** theo `doc/mobile_readiness.md` (15 rows): fresh install · migration · encrypted DB · notification permission (Android 13+) · restart/reboot · timezone · DST · backup/restore · import · override · PayRule · lifecycle. Setup có thể cần: CI build workflow (GitHub Actions) trên máy user.
3. **Sau review RC**: mở deferred §14 (OCR/M4.5 spike — cần 20–30 roster thật · Cloud · Sharing) hoặc closed testing trước.

## 5. Kỷ luật (bám — các phiên trước đã vi phạm)

1. Không báo "xong" bằng lời — mỗi task: dòng code (file + vùng) + test pass (số cụ thể) + `ls` xác nhận file trên đĩa.
2. Viết result*.txt TRƯỚC khi sửa docs; số lịch sử giữ kèm "tại thời điểm …".
3. Tuyệt đối không `flutter build apk` local — build chỉ ở CI/máy user.
4. Không BEGIN lồng nhau trong SQLite — variant `*InTransaction` khi đã trong giao dịch.
5. E3/G/I **KHÔNG được claim PASS** trong docs/store cho đến khi device/CI verify xong — chỉ structure + honest status.
6. Khi widget test phát hiện code thiếu → sửa code thật, không sửa test cho qua.
7. Chạy analyze + nhóm test liên quan NGAY sau mỗi sửa; full suite trước khi chốt phase.

## 6. Ghi chú kỹ thuật / không chặn

- G chỉ là **structure + seam**: production cần SQLCipher native lib (sqlite3_flutter_libs với SQLCipher build hoặc equivalent) + Android Keystore / iOS Keychain cho SecretStore — ghi rõ trong `doc/mobile_readiness.md`.
- Backup/restore UI nằm trong Settings (H) — directory injected cho test (không path_provider trong widget harness).
- DST resolution D lưu `dstOffsetMinutes` vào override payload qua codec — restart vẫn giữ interpretation user đã chọn.
- Docs ngoài đã đồng bộ trạng thái RC complete: `checklist.md` · `.plan/features.md` · `next.md` · `.project/{state,working,openspec_entry,ai-rules}.md`.
