# Checklist — ShiftEase

Cập nhật: 2026-09-11 (**P8 prep complete — verified theo p8_fix1: disk đúng + 4/4 local PASS; release gates BLOCKED human/device; 315/315**; trước đó: P7.2/P7.3/P7.4 thực chất hoá + CI đúng project theo P7_fix1/P7_fix2). Chi tiết: `.plan/plan_p8.md`, `phases/P8_release_preparation.md`, `result_p8_release_candidate.md`, `doc/release_freeze.md`, `doc/release/` (smoke/upgrade/store/privacy/protocols/build_notes), `doc/mobile_readiness.md`, `next.md`.

## ✅ Đã làm (bằng chứng trên đĩa: result13_gate_m2.txt + result14_gate_a.txt + result15_gate_c.txt)

- [x] **Gate 0** `core/time` 32 tests · **Gate 0** `core/pattern` 55 tests (engine 48 + property 7) · **Gate 1** `core/money` 24 tests · **Gate 2** `core/import` engine · **Gate 3** `core/db` v3 + repos + render/import seam
- [x] **Gate M1** (plan5) — app Flutter + domain service + Jobs/Templates/PatternBuilder/Calendar/Occurrence; DoD e2e
- [x] **Gate M1b** (plan6) — Today · Month drill · Quick Add · re-version UI (D1/D9)
- [x] **Gate M2** (plan7) — Smart Paste → Review bắt buộc → Commit → seam D-M2-1 A (schema v3) + audit + chip xám D-M2-2; 5 widget tests
- [x] **Gate A/B** (prompt_gate_a_b.md) — result14: A1 composeService · A2 commit 1 transaction + rollback · A3 window semantics · A4 SWAP effectiveJobId · A5 partial-commit dialog · A6 version immutability — 179/179
- [x] **Gate C** (prompt_gate_c.md) — result15 (+ Addendum post-review 4 findings — xem handoff_20260907_093210): A1 chỉ REVIEWING→COMMIT · A2 changeRosterFrom 1 txn + rollback · A3 saveOverride idempotent/diff→throw · A4 session COMMITTED immutable · ADV-1..5 · B1 DST dialog · B2 income estimate + PayRule editor + nhãn ước tính · B3 ICS export · B4 reminder baseline · B5 pubspec deps + android/ios folders — 207/207
- [x] **RC plan8 — Phần A (Integrity) A1–A8** (code + test bằng chứng):
  - A1 `write_guard.dart` → mọi write-path UI (CREATE/UPDATE/REPLACE/DELETE/import-commit/export) bọc boundary, exception → lỗi hiển thị, không crash — 4 test
  - A2 imported-only roster CREATE: sentinel `__imported__:<jobId>` — không cần active pattern — 3 test (CREATE/restart/cross-job)
  - A3 `saveOccurrences` scoped REPLACE (stale removal trong scope, snapshot giữ) — 4 test
  - A4 import state machine verify: bổ sung ERROR→COMMIT + COMMITTED→COMMIT reject — 2 test
  - A5 import conflict: OFF+SHIFT cùng ngày + duplicate identity → CONFLICT, zero rows — 3 test
  - A6 override canonical compare reordered-payload (reorder-equivalent = idempotent) — 1 test
  - A7 atomic re-version: fail-before + survives restart — 2 test
  - A8 PayRule integrity: unknown jobId reject (bỏ auto-create), negative/malformed reject, children order-independent — 3 test
- [x] **RC plan8 — Phần B (Income) B1–B7** (code + test bằng chứng):
  - B1 estimator parity money engine: HOURS_IN_WINDOW + goldens PAY-013 (5h) / overnight (8h) / DST (7h) — 3 test
  - B2 per-occurrence PayRule resolve; WEEK OT multi-version → UNAVAILABLE + lý do — 2 test
  - B3/B4 `income/income_breakdown_screen.dart` (Date/Range + Hours + Regular/Differentials/OT/Total + disclaimer) — 2 test
  - B5 `pay/pay_presets.dart` template library (US-CA/US-NY/US-TX/UK-NHS/DE) prefill — 1 test
  - B6 Income Impact persist:false (`estimateIncomeImpact`/`estimateReversionImpact` + impact line OccurrenceSheet CREATE/EDIT/DELETE + re-version preview; sửa luôn thiếu sót CREATE chưa wire) — 4 test
  - B7 income card Today multi-job total (chỉ cộng AVAILABLE, ghi rõ exclude) — 1 test
- [x] **RC plan8 — Phần C pure (C1/C2):** `core/import/import_validation.dart` (unmapped required/duplicate/missing times/DST gap) + `core/import/import_diff.dart` (RosterDiff + hoursDelta) — 7 test
- [x] **RC plan8 — C1/C2 UI + D + E + F + G + H + I + J** (bằng chứng: `result16_rc.txt`):
  - C1 UI `parseCsv` + ImportScreen CSV mode (preview → map columns → validate → review → commit) + validation card — 4 test
  - C2 UI committed-roster rows + diff card (+/−/~/= · Hours delta · income impact persist:false) — cùng file 4 test
  - D DST resolution THẬT: chọn interpretation fall-back (RadioGroup, không auto-select) → offsets lưu vào override payload; spring gap vẫn chặn — 4 test (1 rework)
  - E1 stale reminder cancellation (no-upcoming → CANCEL, fixed id replace) · E2 lifecycle resync (RESUME → re-sync) · E3 POST_NOTIFICATIONS manifest + runtime request (**device BLOCKED**) — 6 test
  - F `core/db/backup_restore.dart` (schema+version+checksum+every table; restore validate→preview→confirm→txn rollback; verify row counts) + `deleteAllData` — 7 test
  - G `core/db/security_gate.dart` (key gen 64-hex secure RNG · SecretStore seam · `verifyEncryption` probe — plain build báo NOT encrypted THẬT, không fake) — 7 test (**device BLOCKED**)
  - H `features/settings/settings_screen.dart` (General/Notifications/Data backup+restore+delete-all×2 confirm/Privacy+encryption status/About) + gear icon Jobs screen — 3 test
  - I `doc/mobile_readiness.md` — structure checklist + 15-row device/CI matrix **BLOCKED toàn bộ** (không claim PASS)
  - J `test/core/adversarial/rc_adversarial_test.dart` — migration fail giữ user_version · stale removal · ERROR→COMMIT reject · malformed date · CREATE→UPDATE→DELETE · negative rate · multi-version pricing · no-upcoming cancel · backup corrupt/schema/key/rollback/round-trip — 13 test
- [x] **Verification RC final:** `flutter analyze` clean · `flutter test test/` **288/288 pass** (core 213 + domain 18 + UI 33 + features 12), 0 regression (249 → 288, +39 test mới)
- [x] Hồ sơ: `result16_rc.txt` (mới — `ls` xác nhận) · `doc/mobile_readiness.md` (mới) · checklist/features/next + state.md đồng bộ · handoff mới

## ⏳ Chưa làm — sau RC (cần device/human)

- [x] **Independent RC review** (2026-09-10, `result17_review_rc.txt`): A–J PASS; headline 288/288 + analyze clean confirmed; 1 doc arithmetic error found & corrected (ADDENDUM 1 in `result16_rc.txt`); BLOCKED rows ghi đúng kỷ luật, không overclaim.
- [x] **Code review phần code RC** (2026-09-10, `result18_code_review_rc.txt`): L1 commit button REVIEWING-only + L2 hours 0h-edge + L3 restore picker filter — fixed kèm 4 test mới (rc_csv_diff 12, rc_csv_diff_flow 5, settings 4); H1/M1/M2/L4 tracked trong `doc/mobile_readiness.md` (mục Code-review backlog) + `next.md`.
- [x] **Verification sau polish:** `flutter analyze --no-pub` clean · `flutter test test/` **292/292 pass** (288 → 292, 0 regression).
- [x] **P7.1 — Production verification phase mở (2026-09-10, `result_p7_production_verification.md`):** H1 backup dir → `getApplicationSupportDirectory()` khi không inject (fallback hệ thống bị loại — storage hỏng → từ chối thành thật, KHÔNG rơi về temp) + M1 diff impact → UNAVAILABLE đặt tên row/date khi có row không resolve được — +5 test → **297/297**, analyze clean, 0 regression. P7.8 migration + P7.11 security review + P7.12 regression PASS (sandbox); SQLCipher/Keystore/Keychain/notification/lifecycle/DST-device = **BLOCKED device/CI** (ghi đúng kỷ luật trong evidence file)
- [x] **P7.2/P7.3/P7.4 thực chất hoá + CI theo P7_fix1/P7_fix2 (2026-09-11, evidence rev 2):** SQLCipher **thật 4.18.0** link qua build hook (`source: sqlcipher`, fail-closed, refuse plain keyed open) chạy trong mọi build/test — 17 security-gate test trên file mã hoá thật (reopen, wrong-key, ciphertext header, migration encrypted, probe contract) · `SecureSecretStore` production (Keystore/Keychain, error path 6 test) + `main.dart` fail-closed recovery screen · backup/restore round-trip **encrypted** · `tool/cipher_proof.dart` + named CI step (chứng cứ SQLCipher-on-CI không cần device) · **test.yml viết lại đúng Flutter root** (flutter test toàn bộ, bỏ dart test + libsqlite3-dev lỗi thời, workflow_dispatch) · build-debug-apk.yml đúng, matrix note cập nhật rows 2/3/4 mở khoá · **315/315**, analyze clean, 0 regression
- [ ] **Backlog code-review trước store release (`result18_code_review_rc.txt`):** ~~H1~~ ✅ CLOSED P7.1 · ~~M1~~ ✅ CLOSED P7.1 · M2 iOS permission status (MEDIUM — device cycle) · L4 reminder window 13 ngày (LOW — documented-acceptable)
- [ ] **P7 còn lại = device legs (BLOCKED ngoài sandbox):** copy-DB→plain-SQLite negative test trên máy thật · Keystore/Keychain persistence qua kill/reboot · notification matrix · lifecycle walk · DST device timezone — push GitHub → CI (green run = chứng cứ SQLCipher P7.2) → cài APK artifact → đóng `doc/mobile_readiness.md`
- [x] **P8 PREP COMPLETE (2026-09-11, `result_p8_release_candidate.md` — nhóm A đủ, nhóm B BLOCKED):** P8.0 CI verify (đã đúng Flutter root từ P7_fix2 — claim stale trong plan_p8; mở rộng paths android/ios/pubspec.lock) · P8.1 `doc/release_freeze.md` (schema v3 + 7 engine frozen, intake chỉ P0–P2/security/compliance) · P8.2 version 1.0.0+1 + ids `com.shiftease.shiftease` + **app name ShiftEase thống nhất cả 2 nền tảng** (sửa lệch shiftease/Shiftease) + release path sạch (không debug/mock/seed) · P8.5 smoke checklist 19 bước NOT RUN · P8.6 upgrade plan · P8.7 store copy chỉ feature thật · P8.8 privacy audit-based (không network permission — "no data collected" kiểm chứng được) · P8.9/10 protocols P0–P3 · P8.3/4 signed build **BLOCKED needs keys** · P8.11 evidence + kết luận **KHÔNG sang P9** cho tới nhóm B xong
- [ ] **CI activation (on disk ✅ / GitHub run chưa — p8_fix1 §3.2):** workflow Flutter root đã verify (test.yml 8 jobs + build-debug-apk.yml; 4 lệnh local PASS 315/315 + cipher_proof SQLCipher 4.18.0) — cần push → Actions xanh → APK artifact. Chỉ ghi PASS CI green sau khi thấy run xanh.
- [ ] **P8 nhóm B (human/device — không agent tự PASS):** push → CI xanh · signed AAB + iOS archive · smoke/upgrade PASS thật · internal + closed testing · zero P0/P1 → chỉ khi đó P8 DONE → P9
- [ ] **Device/CI verification (BLOCKED ngoài sandbox — `doc/mobile_readiness.md`):** E3 permission flow thật (Android 13+) · G SQLCipher native + secure key storage thật · I 15-row matrix (fresh install, migration, encrypted DB, notification, restart/reboot, timezone, DST, backup/restore, import, override, PayRule, lifecycle)
- [ ] Deferred plan8 §14 (sau review RC): OCR/M4.5 spike · Cloud sync · Dynamic Webcal · Sharing · CalendarEvent model · Health AI · B2B · Tax/net-pay

## ❓ Chưa rõ — cần hỏi

- [x] **Tiếp tục RC §15?** — HOÀN TẤT (2026-09-08, result16) + review PASS (result17) + code review polish (result18)
- [x] **E3/G/I device/CI**: giữ trong RC dạng structure + note BLOCKED — đúng kỷ luật; CI wired 2026-09-10 (full-suite job + debug APK artifact) để bắt đầu đóng matrix
- [ ] **M4.5 OCR spike**: spec `.plan/plan11_ocr_spike.md` CHỜ DUYỆT (ngưỡng 70/60) — cần user cung cấp 20–30 roster thật + ground truth; OCR chạy ngoài app
- [ ] **Sau RC**: closed testing trước hay song song với M4.5 spike? (device/CI verification vẫn là điều kiện publish-ready — plan §13)
- [ ] **M3 template library nội dung**: presets RC đã seed US-CA nurse/US-NY/US-TX/UK-NHS/DE làm starting point — có cần thêm quốc gia/ngành khác (AU? CA?) không
