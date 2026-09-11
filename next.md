# ShiftEase — next.md: Lộ trình đến khi khai thác hết tính năng người dùng cần

> Điểm xuất phát (thời điểm M0 — nay core = 176/176): **core engines Gates 0–3 ✅**, UI/domain/platform baseline Gate C ✅ (207/207 tổng), **RC plan8 HOÀN TẤT A–J — 292/292 → P7.1: 297/297** (2026-09-10; xem mục RC bên dưới + `result16_rc.txt` + `result_p7_production_verification.md`).
> Roadmap gốc: M0 ✅ → M1 Basic Calendar → M2 Import → M3 Multi-Job + Pay → M4 Export & Share → **M4.5 OCR Spike** (gate) → M5 OCR Import → M6 Cloud.
> Trạng thái chi tiết: `.plan/features.md`. Mỗi bước = 1 gate: survey spec → viết spec `.plan/planN_*.md` → **user duyệt** → code → tests → báo cáo `result*.txt` kèm bằng chứng trên đĩa.

---

## Việc trước mắt (sắp tới — làm trước khi bước tiếp từ thời điểm này)

- [x] **Human review release-candidate** toàn bộ plan8 batch A–J (2026-09-10, `result17_review_rc.txt` — A–J PASS, 288/288 + analyze clean xác nhận)
- [x] **Code review phần code RC** (2026-09-10, `result18_code_review_rc.txt`): L1/L2/L3 fixed cùng lúc (+4 test → **292/292**, analyze clean); H1/M1/M2/L4 → backlog (`doc/mobile_readiness.md` mục Code-review backlog)
- [x] **P7.1 — Production verification phase mở (2026-09-10, `result_p7_production_verification.md`):** H1 backup dir → `getApplicationSupportDirectory()` (honest refusal thay vì temp fallback; test seam `backupDirResolver`) + M1 diff impact → UNAVAILABLE đặt tên row — +5 test → **297/297**, analyze clean. P7.8/P7.11/P7.12 PASS sandbox; còn lại P7 = device/CI gates
- [x] **P7.2/P7.3/P7.4 thực chất hoá + CI đúng project (2026-09-11, theo P7_fix1/P7_fix2, evidence rev 2):** SQLCipher thật 4.18.0 qua build hook — fail-closed, 17 gate test trên file mã hoá thật, migration/backup encrypted scope · `SecureSecretStore` (Keystore/Keychain) + recovery screen fail-closed trong `main.dart` · `tool/cipher_proof.dart` chạy làm named CI step · **test.yml viết lại: flutter test trên Flutter root** (bỏ 10× `dart test` + `libsqlite3-dev` lỗi thời) — **315/315**, analyze clean
- [ ] **Backlog code-review (trước store release — `result18` + `doc/mobile_readiness.md`):** ~~H1~~ ✅ CLOSED P7.1 · ~~M1~~ ✅ CLOSED P7.1 · M2 iOS permission status (MEDIUM, làm cùng device row 5) · L4 reminder window 13 ngày (LOW, documented-acceptable)
- [ ] **P8 nhóm B (human/device — `result_p8_release_candidate.md` §6):** push GitHub → CI green · keystore/certs (không commit) → signed AAB/iOS archive theo `doc/release/build_notes.md` · smoke + upgrade PASS thật (`doc/release/`) · internal → closed testing (P0/P1 = stop ship) · freeze cuối → **chỉ khi đó P9**. Nhóm A (prep) ✅ complete: freeze/version/checklists/store/privacy/protocols
- [ ] **P7 còn lại = device legs (BLOCKED ngoài sandbox):** push GitHub → CI green run (chứng cứ SQLCipher P7.2 qua `tool/cipher_proof.dart` + suite chạy trên cipher-linked build) → tải APK artifact từ `build-debug-apk.yml` → cài máy thật → đóng matrix `doc/mobile_readiness.md` (notification, lifecycle, backup/restore, DST/timezone, migration/encrypted DB rows 2/3/4/7) + negative test copy-DB→plain-SQLite + Keystore/Keychain kill/reboot — chạy chung chu kỳ device với P8 nhóm B
- [ ] **M4.5 OCR spike** (spec `.plan/plan11_ocr_spike.md` — CHỜ DUYỆT): ngưỡng đề xuất dates ≥70% / shift types ≥60%; cần user cung cấp 20–30 roster thật + ground truth; OCR chạy ngoài app, KHÔNG đụng code app; PASS → mở M5, FAIL → dừng ở CSV/paste
- [ ] (device/CI — **BLOCKED ngoài sandbox**, không build apk local) E3 notification permission flow thật · G SQLCipher native verify · I 15-row verification matrix — theo `doc/mobile_readiness.md`
- [ ] **Sau review RC**: mở deferred plan8 §14 (OCR/M4.5 spike — cần 20–30 roster thật · Cloud · Sharing) hoặc closed testing

---

## RC plan8 — Release Candidate batch (✅ HOÀN TẤT — plan8_m3_income.md, 2026-09-08; verify lại 2026-09-10)

Batch cuối trước review release-candidate: M3 Income + integrity hardening + production readiness. Không mở OCR/Cloud/AI trong batch (§14 deferred).

**Phần A — Integrity (A1–A8 ✅):**
- [x] A1 UI write error boundary (`write_guard.dart` — mọi write-path, exception → lỗi hiển thị, 4 test)
- [x] A2 imported-only roster CREATE (sentinel `__imported__:<jobId>`, 3 test)
- [x] A3 materialized occurrences scoped REPLACE (stale removal, 4 test)
- [x] A4 import state machine (ERROR/COMMITTED→COMMIT reject, +2 test) · A5 conflict OFF+SHIFT/duplicate → CONFLICT (+3 test)
- [x] A6 override reordered-payload compare (+1 test) · A7 atomic re-version fail-before/restart (+2 test)
- [x] A8 PayRule integrity unknown-jobId/negative/order-independent (+3 test)

**Phần B — Income engine + dashboard (B1–B7 ✅):**
- [x] B1 estimator parity HOURS_IN_WINDOW + goldens PAY-013/overnight/DST (+3) · B2 per-occurrence rule; WEEK OT multi-version → UNAVAILABLE (+2)
- [x] B3/B4 `income/income_breakdown_screen.dart` (Date/Range + Regular/Differentials/OT/Total + disclaimer, +2 UI)
- [x] B5 `pay/pay_presets.dart` template library (US-CA/US-NY/US-TX/UK-NHS/DE, +1 UI)
- [x] B6 Income Impact persist:false — sheet CREATE/EDIT/DELETE + re-version preview (+2 domain +2 UI)
- [x] B7 income card Today multi-job total (chỉ AVAILABLE + exclude nêu tên, +1 UI)

**Phần C — CSV + re-import diff (✅ pure + UI):**
- [x] C1 `import_validation.dart` + C2 `import_diff.dart` (+7 test)
- [x] C1 UI: service `parseCsv` + ImportScreen CSV mode (preview → map columns → validate → review → commit) + validation card — 4 test
- [x] C2 UI: committed-roster rows + diff card (+/−/~/= · Hours delta · income impact persist:false) trước Review — cùng file 4 test

**Phần D–J (✅ — bằng chứng `result16_rc.txt`):**
- [x] D — DST real resolution: chọn interpretation fall-back (RadioGroup, không auto-select) → offsets persist vào override payload; spring gap vẫn chặn — 4 test (1 rework)
- [x] E1 stale reminder cancellation (no-upcoming → CANCEL, fixed id) · E2 lifecycle resync (RESUME → re-sync) — 6 test · E3 POST_NOTIFICATIONS manifest + runtime request (**device BLOCKED**)
- [x] F — `core/db/backup_restore.dart` (schema+version+checksum; restore validate→txn rollback; verify row counts; deleteAllData) — 7 test
- [x] G — `core/db/security_gate.dart` (key gen 64-hex · SecretStore seam · verifyEncryption probe — plain build báo NOT encrypted THẬT) — 7 test (**device BLOCKED**)
- [x] H — `features/settings/settings_screen.dart` (General/Notifications/Data/Privacy/About) + gear icon Jobs — 3 test
- [x] I — `doc/mobile_readiness.md` structure checklist + 15-row device/CI matrix **BLOCKED toàn bộ** (không claim PASS)
- [x] J — `test/core/adversarial/rc_adversarial_test.dart` — 13 test

**Verification RC final:** analyze clean · **292/292 tests pass** (core 228 + domain 18 + UI 36 + features 10), 0 regression (249 → 288 → 292). Evidence: `result16_rc.txt` + ADDENDUM 1, `result17_review_rc.txt`, `result18_code_review_rc.txt`.

---

## M1 — Basic Calendar (UI + domain service) — ✅ Gate M1 XONG (2026-09-05, plan5 + result11)

**Đã làm (bảng In/Out plan5, D-UI-1 A · D-UI-3 không dep · D-UI-4):**
- [x] Domain service `lib/domain/schedule_service.dart` — job/template/pattern/render/override qua repo, CREATE patternId convention, localWallTime INVARIANT-007, validate tz, changeRosterFrom (D9)
- [x] Jobs list + create (tz validated) · Job detail (templates + patterns) · Template dialog (INVARIANT-005 — không có pay field)
- [x] Pattern Builder — 4-on/4-off, 2-2-3, DuPont + per-slot template/OFF + preview engine + effectiveFrom
- [x] Calendar Week — 7 cột Mon..Sun, local time, nav tuần, issue banner
- [x] Occurrence sheet — UPDATE/REPLACE/DELETE/CREATE (ngày OFF) qua append-only override
- [x] DoD e2e widget test + 3 domain tests (restart persist file DB, CREATE full+sub-range, INVARIANT-007) — 5/5 pass; CI 7 jobs + dependency-rule guard

**M1b (✅ XONG 2026-09-05 — plan6 + result12):** Today screen (D1 — không income, M3) · Month view (D2, drill vào week) · Quick Add 1-tap (D3 + Custom) · Roster re-version UI (D1/D9 — pattern tile → "New version from date…"). **M1b còn lại:** DST dialog UI (A10/D4 — engine sẵn NONEXISTENT/AMBIGUOUS) · Pay Rules UI (M3).

**Definition of done M1 (đạt — chạy trong widget test, DB SQLite thật):** tạo job → tạo pattern → xem lịch tuần → sửa 1 ca (override) → render lại đúng → thoát/mở lại (persist) → vẫn đúng.

---

## M2 — Import UI — ✅ Gate M2 XONG (2026-09-05, plan7 + result13) · ✅ Gate A/B XONG (2026-09-06, result14)

**Đã làm (D-M2-1 A — import = nguồn chính · D-M2-2 · D-M2-3 v1 = Smart Paste + Review):**
- [x] Smart Paste screen (E1) — paste + reference date → candidates + Confidence badge/note → **Review bắt buộc** (✓/✎/✗ + Accept All High, INVARIANT-004) → COMMIT atomic → lỗi hiển thị rõ (không silent)
- [x] **Commit seam D-M2-1 A**: schema v3 — committed roster ghi `occurrences` (jobId, isImported) + `committedOffDatesJson`; render merge + suppress pattern cùng ngày; re-import replace window sau Review lại
- [x] Session audit mỗi bước (parse/review/commit persist) — E6
- [x] 5 widget tests (DoD e2e + restart file DB + edit MEDIUM + audit, reject, atomic DST-gap zero-change, INVARIANT-004, AC-5 pending-warning dialog); core 164 giữ nguyên; domain+UI = 15

**M2b (✅ hoàn tất trong RC C1/C2):** CSV import với UI mapping cột (E2) · Re-import "What changed?" diff screen (E7).

---

## Gate C — Integrity + Product baseline — ✅ XONG (2026-09-07, prompt_gate_c + result15)

**Phần A — Integrity (code + test):**
- [x] A1 `commitImport` chỉ REVIEWING→COMMIT; EXTRACTED reject; zero-approved reject (không silent empty commit) — 2 test mới
- [x] A2 `changeRosterFrom` 1 transaction (close-old + save-new); fail giữa chừng → rollback, không roster mồ côi — 2 test mới + ADV-2
- [x] A3 `saveOverride` immutability: same id + payload giống = idempotent; khác payload → `ImmutableHistoryError` — 3 test mới + ADV-3/4
- [x] A4 ImportSession COMMITTED immutable: khác payload → throw, row nguyên vẹn; giống = no-op — 3 test mới + ADV-5
- [x] A5 `test/core/adversarial/gate_c_adversarial_test.dart` (ADV-1..5) + full-suite regression 207/207

**Phần B — Product (code + test):**
- [x] B1 DST dialog UI (A10/D4): AMBIGUOUS hiện 2 candidate (không auto-pick), NONEXISTENT chặn + giải thích; acknowledging không ghi gì — wired OccurrenceSheet; 3 widget tests
- [x] B2 Pay/Income tối thiểu (C8/C10): `income_estimate.dart` + `estimateIncomeForDay` + PayRule editor dialog (base/NIGHT/WEEKEND/OT WEEK) + income card Today nhãn “Ước tính — không phải bảng lương chính thức”; không rule → lý do rõ, không số — 3 domain + 2 UI tests
- [x] B3 ICS export offline (D6): generator RFC 5545 thuần (UTC VEVENT, escape, CRLF) + saver path_provider + action Export week JobDetail — 2 tests
- [x] B4 Local notification (D7): `shift_reminder.dart` spec thuần (60′ lead, next shift) + wrapper guard `flutter_local_notifications`; wire TodayScreen — 4 tests
- [x] B5 Platform baseline: pubspec `path_provider` + `flutter_local_notifications`, tạo `android/` + `ios/` — **KHÔNG build apk local** (chỉ đạo user; sandbox không có toolchain)
- [x] B6 `result15_gate_c.txt` trên đĩa (`ls -la` xác nhận) · B7 docs đồng bộ (checklist/features/next)

**Tổng:** **207/207 tests pass** (core 176 + domain 9 + UI 16 + features 6), analyze clean, 0 regression (179/179 cũ).

---

## M3 — Multi-Job + Pay mở rộng (dùng engine Gate 1 ✅ + nền Gate C B2) — nội dung chính đã chuyển vào RC plan8 (xem mục RC ở đầu file)

- [x] Pay Rule editor UI mức cơ bản (base rate + NIGHT/WEEKEND + OT WEEK, versioned) — ✅ Gate C B2
- [x] Income card Today + nhãn “Ước tính — không phải bảng lương chính thức” + từ chối tính khi thiếu rule (C10) — ✅ Gate C B2
- [x] Income breakdown dashboard UI đầy đủ (C8 — base + từng differential + OT + tổng) — ✅ RC B3/B4 (`income_breakdown_screen.dart`)
- [x] Template library picker (US CA nurse, US NY/TX, UK NHS, DE — C7) — ✅ RC B5 (`pay_presets.dart` — prefill starting point)
- [x] Weekly income view + Income Impact khi đổi roster/override — ✅ RC B6/B7 (impact line sheet CREATE/EDIT/DELETE + re-version preview + multi-job total)
- [ ] Chống thiếu config mở rộng: work-week boundary/state OT rule chưa đủ → hiện lý do cụ thể — một phần ✅ RC B2 (WEEK OT multi-version → UNAVAILABLE + lý do); cấu hình work-week boundary/state OT mở rộng = backlog sau RC

---

## M4 — Export & Share

- [x] **.ics export offline** (D6) — ✅ Gate C B3 (generator + saver + action)
- [ ] Sharing 3 modes FULL / BUSY_ONLY / RECOVERY (G1) + anonymous UUID link + revoke (G2)
- [x] Basic notifications — thông báo ca bắt đầu (D7) — ✅ Gate C B4 (baseline; permission flow thật trên device)
- [ ] (device) share sheet cho ICS + notification permission flow
- [ ] CalendarEvent model (F1–F4): TimeOff, PersonalEvent, AvailabilityBlock — **bổ sung model + persistence (backlog Gate 3)**
- [ ] (P2) Partner/Family overlay read-only (G3), Availability Finder (F5)

---

## M4.5 — OCR Spike Test (GATE — không phải kiến trúc lớn) — 📋 SPEC SẴN SÀNG (`plan11_ocr_spike.md`, chờ duyệt)

- [ ] User duyệt spec + ngưỡng: dates **≥70%**, shift types **≥60%** (ghi rõ trong spec)
- [ ] Thu thập **20–30 roster thật** + ground truth (user cung cấp) → chạy OCR (Tesseract/PaddleOCR, ngoài app) → **báo cáo % correct dates / shift type / start-end** vào `result19_ocr_spike.txt`
- [ ] Chỉ tiến hành M5 nếu đạt ngưỡng (E3 — plan1 mandate, không commit kiến trúc OCR đầu cơ)

---

## M5 — OCR Import (chỉ khi M4.5 đạt)

- [ ] Pipeline ảnh/PDF → OCR → regex parser → candidates → review → commit (tái dùng toàn bộ M2)

---

## M6 — Cloud (P1+, tùy chọn)

- [ ] Cloud backup E2E encrypted (H4), dynamic Webcal (G6), SQLCipher local + AES-GCM (G7)

---

## Moat & stickiness (P2/P3 — sau khi core luồng chạy đủ)

- [ ] Shift change detection (H1) — employer đổi lịch → cảnh báo
- [ ] Wellness rule-based (H2) — chuỗi ca dài, recovery sau night shift
- [ ] Widgets home screen (H3)
- [ ] Health AI (H5), B2B team (H6) — ngoài MVP

---

## Nguyên tắc xuyên suốt (đừng quên — user rất khắt khe)

1. Mỗi gate: spec → **user duyệt** → code → test → báo cáo kèm **bằng chứng trên đĩa** (`ls`, dòng code, output test) — không báo cáo bằng lời.
2. Không tự ý làm nhẹ deviation — trình bày + chờ duyệt.
3. Invariants INVARIANT-001..008 + NEVER list (plan1 §10) là rào cứng — UI/domain không được phép phá.
4. Tiếng Việt hồ sơ: sửa thủ công từng chỗ, cẩn thận encoding (có tiền lệ mất dấu đổi nghĩa).
5. Khi gặp bug: `systematic-debugging`; trước claim "xong": `verification-before-completion`.
