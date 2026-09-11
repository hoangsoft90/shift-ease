# Working Memory — ShiftEase

> Auto-updated tracking file. Last updated: 2026-09-10
> Trạng thái project chi tiết: `.project/state.md`. Phiên này: **đóng gói plan8 RC batch (A–J) — verify + đồng bộ docs + handoff**.

## Session State (2026-09-10)

### Bối cảnh

RC batch A–J đã thực thi xong trong phiên trước (2026-09-08, xem `result16_rc.txt`), nhưng `.project/*` + `next.md` còn stale (ghi "249/249, C UI dở, D–J chưa làm"). Phiên này **verify lại bằng chứng rồi mới sync docs**.

### Verification (bằng chứng chạy 2026-09-10, sau khi `ls` xác nhận mọi file RC trên đĩa)

- `flutter analyze --no-pub` → **No issues found!** (19.3s)
- `flutter test test/` → **288/288 All tests passed! (exit=0)** — khớp `result16_rc.txt`
- Files RC xác nhận trên đĩa (`ls -la`, mtime 2026-09-08): `lib/core/db/backup_restore.dart` · `lib/core/db/security_gate.dart` · `lib/features/settings/settings_screen.dart` · `doc/mobile_readiness.md` · `test/core/adversarial/rc_adversarial_test.dart` · `test/ui/rc_csv_diff_flow_test.dart` · `test/ui/dst_resolution_flow_test.dart` · `test/features/shift_reminder_rc_test.dart` · `test/core/db/backup_restore_test.dart` · `test/core/db/security_gate_test.dart` · `test/ui/settings_flow_test.dart`

### Đã làm trong phiên này (đóng gói, không code mới)

- [x] Verify 288/288 + analyze clean (không tin lời — chạy lại)
- [x] Sync `.project/state.md` → RC hoàn tất A–J
- [x] Sync `.project/working.md` (file này)
- [x] Sync `next.md` (mục RC → hoàn tất; việc trước mắt = human review + device/CI)
- [x] Sync `.project/openspec_entry.md` + `.project/ai-rules.md`
- [x] Handoff mới: `handoff_20260910_rc_complete.md`

### Trạng thái RC plan8 (đã khóa — chi tiết trong result16_rc.txt)

- Phần A Integrity A1–A8 ✅ · Phần B Income B1–B7 ✅ (phiên 2026-09-07)
- C1/C2 UI (parseCsv + CSV mode + diff card) ✅ · D DST real resolution ✅ · E1/E2 notification ✅ · E3 structure (**device BLOCKED**) ✅ · F backup/restore ✅ · G security gate structure (**device BLOCKED**) ✅ · H settings ✅ · I mobile readiness doc (**verify BLOCKED toàn bộ**) ✅ · J adversarial 13 test ✅
- Evidence: `result16_rc.txt` · checklist.md/features.md/next.md đã đồng bộ · `doc/mobile_readiness.md`

## Pending Decisions / Cần hỏi user

1. **Human review RC** toàn bộ batch A–J (độc lập, như review plan10 trước đó)?
2. Sau review: **deferred §14** (OCR/M4.5 spike — cần 20–30 roster thật · Cloud · Sharing) hay **closed testing** trước?
3. **Device/CI verification** (E3/G/I — blocked ngoài sandbox): chạy trên máy user/CI khi nào; có cần setup CI build (GitHub Actions) không?

## Pending Work

**Immediate (chờ quyết định user):**
- [ ] Human review release-candidate → xử lý findings (nếu có)
- [ ] Device/CI verification theo `doc/mobile_readiness.md` (15-row matrix)

**Later (deferred plan8 §14 — sau review RC):**
- [ ] OCR/M4.5 spike (cần 20–30 roster thật) → M5 nếu đạt ngưỡng
- [ ] Cloud sync · Dynamic Webcal · Sharing · CalendarEvent model · Health AI · B2B · Tax/net-pay
- [ ] M3 backlog: work-week boundary/state OT rule mở rộng

## Known Issues / Notes

- E3/G/I chỉ là structure + honest status — KHÔNG được claim PASS trong docs hay store submission cho đến khi device/CI verify xong.
- Không build apk local (sandbox không toolchain) — build chỉ ở CI/máy user.
- Kỷ luật giữ nguyên: mỗi claim = bằng chứng đĩa (`ls`, output test); viết result* TRƯỚC khi sửa docs; không BEGIN lồng nhau trong SQLite.
- Lịch sử test số: 207 (Gate C) → 249 (A+B+C pure, 2026-09-07) → **288 (RC hoàn tất, 2026-09-08, verify lại 2026-09-10)**.
