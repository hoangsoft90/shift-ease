# ShiftEase — Danh mục tính năng (App + UI)

> Nguồn: `plan1_final_v2.md` (spec đã khóa) + `plan2.md` (kỹ thuật chi tiết) + trạng thái code hiện tại.
> Ký hiệu trạng thái: ✅ Đã implement | 🔧 Đang implement | ⏳ Đã chốt thiết kế, chưa code | 📋 Đã lên kế hoạch (P1/P2/P3)

---

## 1. Tổng quan sản phẩm

| Mục | Giá trị |
|---|---|
| Định vị | **Personal Operating System for Shift Workers** — 3 trụ cột: Work – Life – Money |
| Target persona | Nurse/Healthcare 25–45, Mỹ/Anh/Đức, ca xoay 3 kíp, đa nguồn thu nhập, có gia đình |
| Phạm vi MVP | Mỹ, Anh, Đức |
| Đối thủ | Supershift, MyShiftPlanner (pattern/roster = table stakes, không phải USP) |
| 3 trục differentiation | (1) Nhập liệu nhanh, (2) Correctness Contract (tính đúng về mặt kỹ thuật), (3) UX đơn giản |
| Monetization | Free / Pro; Lifetime $39.99 ưu tiên giai đoạn đầu |
| Hook marketing | *"Screenshot your hospital roster. ShiftEase does the rest."* / *"Know when you're working, when you're free, and what you'll earn."* / *"Your shifts. Your life."* |

### Correctness Contract (áp dụng mọi module)

> Cùng input hợp lệ + cùng timezone database version + cùng pay rule version → kết quả **deterministic**.
> Không silent đưa ra kết quả khi input/rule không đủ → phải báo **"Unable to calculate accurately"** kèm lý do.
> Triết lý: *"Không biết" tốt hơn "tính sai"*. Mọi số tiền hiển thị kèm nhãn **"Ước tính — không phải bảng lương chính thức"**.

---

## 2. Trạng thái tổng quan

| Khối | Trạng thái | Chi tiết |
|---|---|---|
| `core/time` | ✅ Implement (Gate 0) | `lib/core/time/` — resolver DB-driven (bỏ ±1h), validation INVALID_* (M1), END_BEFORE_START (M2); 32 tests pass |
| `core/pattern` | ✅ Implement (Gate 0) | `lib/core/pattern/` — resolved-only pipeline (P0-1..6), provenance tại nguồn, chain atomicity, SPLIT invariants (H-1), D9 anchorDate; SWAP `effectiveJobId`/`INCOMPLETE_SWAP` (Gate A §A4); 55 tests pass (pattern_engine_test 48 + property 7) + 5 pattern→time integration |
| `core/money` | ✅ Implement (Gate 1) | `lib/core/money/` — PayRule versioned, PayBreakdown Cách B, multi-rule OT max(), LIFO weekly allocation (`allocateWeeklyOvertimeHours` decoupled core), PayRuleTemplate seeds, MAX-composition fix (review Gate 1); **24 tests pass** (golden PAY-001..014 + unit) |
| Import pipeline | ✅ Core engine (Gate 2) | `lib/core/import/` — parser PASTE_TEXT/CSV, date resolution, confidence matrix, state machine, review/bulk/commit (atomic + UTC via core/time), audit, re-import diff, OCR gated M4.5; CSV header không có cột dùng được → PARSE_FAILED rõ ràng (không đoán LOW); **16 tests pass** (golden IMPORT-001..008 + unit + D-2 CSV `?` + no-usable-columns) |
| Persistence | ✅ Implement (Gates 3 + M2 + A/B) | `lib/core/db/` — SQLite `sqlite3` FFI, migration `PRAGMA user_version` **v3** (v2: `overrides.patternId` — CREATE convention chính thức; v3: `occurrences.jobId` + `isImported` + `import_sessions.jobId`/`committedOffDatesJson`/`windowStart`/`windowEnd` — import-commit seam D-M2-1), typed repos, override log append-only + replay, INVARIANT-006 snapshot, `renderJobSchedule` từ active versions + log + imported-roster merge/suppress (OFF per-day window, Gate A §A3), version immutability Pattern/PayRule (Gate A §A6, D9 close allowed); **18 tests pass** |
| Golden tests (Time) | ✅ | `test/golden/time_engine_cases.json` (28 cases: +DST-009/010 Lord Howe 30′, VALID-001..004, LH-001) |
| Integration suite | ✅ | `test/core/integration/` — **19 tests**: pattern→time (5), pattern→money (3), import→money (3), db→money (3), db→pattern (5) |
| Core tests tổng | ✅ | `flutter test test/core/` — **176/176 pass** (time 32 + pattern 48 + property 7 + money 24 + import 18 + db 24 + integration 19 + adversarial 4 — Gate C) |
| UI / features / domain (M1) | ✅ Gate M1 (2026-09-05) | Repo → Flutter app (pubspec + `flutter` sdk, core giữ nguyên). `lib/domain/schedule_service.dart` + `lib/features/{jobs,templates,pattern_builder,calendar,occurrence}` + `lib/app`. DoD e2e widget test + domain tests; **Gate A §A1**: `main.dart` `composeService` (production wiring — ImportRepository reachable từ app thật) — chi tiết `plan5_m1_ui.md`, `result11_gate_m1.txt`, `result14_gate_a.txt` |
| Domain service | ✅ | `ScheduleService` — jobs/templates/patterns/render/override qua repos, CREATE patternId convention, `localWallTime` (INVARIANT-007), validate tz, `changeRosterFrom` (D9) |
| CI | ✅ | `.github/workflows/test.yml` — **7 jobs** (core-time, core-pattern, core-money, import, persistence-tests incl. db→money + db→pattern integration, **ui-tests** domain+widget, static-analysis `flutter analyze --fatal-warnings` + dependency-rule guard plan2 §1.1), paths thật |
| Core tests tổng (Gate A/B) | ✅ | `flutter test test/core/` — 164/164 tại Gate A/B (thêm db 4: AC-2 rollback, AC-3 window A/B, AC-6 immutability ×2; pattern engine 2: AC-4 SWAP; import 1: CSV no-usable-columns → PARSE_FAILED) |
| Domain + UI tests | ✅ Gate A/B (2026-09-06) → Gate C (2026-09-07) | Gate A/B: 15 tests (domain 4 + UI 11). Gate C: **25 tests** — domain 9 (M1 3 + AC-1 1 + changeRosterFrom 2 + income estimate 3) + UI 16 (M1 2 · M1b 4 · M2 5 · DST 3 · Pay/Income 2) |
| Feature tests (Gate C) | ✅ | `test/features/` — **6 tests**: ICS export 2 (VEVENT UTC + CSV-injection escape) · shift reminder 4 (60′ lead, skip-past, null, sort) |
| Core tests tổng (RC plan8) | ✅ | `flutter test test/core/` — **199/199 pass** (time 32 + pattern_engine 48 + property 7 + money 24 + db 28 + import 30 + integration 26 + adversarial 4) — A1–A8 integrity |
| Domain + UI + features (RC plan8) | ✅ | domain **18** (svc 7 + income_estimate 10 + composition 1) · UI **26** · features **6** — B1–B7 income/dashboard · C1/C2 pure modules; tổng **249/249** · analyze clean |
| UI M1b | ✅ Gate M1b (2026-09-05) | `features/today` (giờ tuần từ UTC — income để M3), `features/calendar/month` (6×7 grid, drill tuần), `calendar/quick_add` (1-tap template → CREATE), re-version UI (D1/D9: close X−1, anchor giữ) — chi tiết `plan6_m1b.md`, `result12_m1b.txt` |
| UI M2 Import | ✅ Gate M2 (2026-09-05) + Gate A/B (2026-09-06) | `features/import/import_screen.dart` — Smart Paste → parse → **Review bắt buộc** ([✓][✎][✗] + Accept All High, INVARIANT-004) → COMMIT atomic → **D-M2-1 A**: committed roster ghi `occurrences` (jobId, isImported) + `committedOffDates`, render merge/suppress pattern cùng ngày; template không khớp → chip xám (D-M2-2); session audit mỗi bước; partial-commit warning + dialog (Gate A §A5); **5 widget tests** (4 M2 cũ + 1 AC-5) — chi tiết `plan7_m2_import_ui.md`, `result13_gate_m2.txt`, `result14_gate_a.txt` |

---

## 3. Tính năng theo nhóm

### A. Time Engine — Độ chính xác thời gian (✅ core/time)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| A1 | **Civil Time Architecture** | 3 khái niệm tách bạch: Local Civil Time (cơ sở recurrence/UI), UTC Instant (sắp xếp/reminder), Elapsed Duration (đầu vào Pay Engine) | P0 | ✅ |
| A2 | **Resolve local → UTC** | Chuyển đổi local civil time sang UTC instant, có xử lý overnight (`+1` / endHour < startHour); **Gate 0:** thuật toán DB-driven enumerate `loc.zones` (bỏ hoàn toàn ±1h heuristic — sai cho Lord Howe 30′) | P0 | ✅ |
| A2b | **Strict input validation** (M1/D7) | Round-trip date (`2026-02-31` → `INVALID_DATE`), time range (`25:90` → `INVALID_TIME`), timezone lookup riêng (`INVALID_TIMEZONE`) — INVALID_* không bao giờ lẫn vào DST error; `END_BEFORE_START` trên UTC đã resolve (M2) | P0 | ✅ (VALID-001..004) |
| A3 | **Tính duration từ UTC** (INVARIANT-002) | Duration luôn từ `utcEnd - utcStart`, không trừ giờ local — ca bắc DST spring-forward = 7h, fall-back = 9h | P0 | ✅ |
| A4 | **DST non-existent time** (D4) | Giờ không tồn tại (spring-forward) → **không tự quyết**, trả lỗi `NONEXISTENT_LOCAL_TIME` → UI hiện dialog | P0 | ✅ (engine) |
| A5 | **DST ambiguous time** (D4) | Giờ bị lặp (fall-back) → trả `AMBIGUOUS_LOCAL_TIME` kèm danh sách 2 options (EDT/EST...) → UI hiện dialog cho user chọn | P0 | ✅ (engine) |
| A6 | **Ambiguous end-time** | End time bị lặp cũng không auto-select — xử lý y hệt start time (sửa bug DST-008) | P0 | ✅ |
| A7 | **Timezone retention** (INVARIANT-007) | Occurrence giữ nguyên timezone gốc kể cả khi user đổi timezone thiết bị | P0 | ✅ |
| A8 | **Recurrence theo local time** (INVARIANT-003) | Ca 22:00 chạy xuyên đêm DST không bị lệch giờ hiển thị | P0 | ✅ |
| A9 | **Golden Test Suite** | `time_engine_cases.json`: DST Mỹ/UK/Đức/Úc + **Lord Howe 30′** (DST-009/010), southern hemisphere, ranh giới tháng/năm, error cases, **VALID-001..004**, LH-001 (+10:30); round-trip property 1 năm × 3 zone (H-4) | P0 | ✅ |
| A10 | **DST resolution dialog (UI)** | Khi giờ không tồn tại/bị lặp: dialog xác nhận, user chọn diễn giải — **không tự làm tròn/đoán** | P0 | ✅ Gate C (B1 — `features/common/dst_resolution_dialog.dart`, wired OccurrenceSheet; 3 widget tests) |

### B. Pattern → Occurrence → Override (✅ core/pattern)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| B1 | **Shift Template** | Chỉ chứa time/UI: `startTime`, `endTime`, `breakDurationMinutes`, `color` — **không chứa pay** (INVARIANT-005, D5) | P0 | ✅ (type) |
| B2 | **Shift Pattern** | Cycle lặp: `FIXED_CYCLE` (4-on/4-off, 2-2-3, DuPont) + chừa `ALTERNATING_WEEKS` / `CUSTOM`; sequence chứa `null` = OFF day | P0 | ✅ |
| B3 | **Project occurrences** | Sinh baseline occurrences từ pattern trong date range; OFF day không sinh ca; template thiếu → issue `MISSING_TEMPLATE` (không silent skip); **resolved-only** — ngày không resolve được chỉ tồn tại trong `.issues`, không phải object UTC rỗng (P0-3/D1) | P0 | ✅ |
| B4 | **Pattern versioning** (D1 + D9) | Đổi roster từ ngày X → tạo pattern bản mới (`effectiveFrom`/`effectiveUntil`), **không mutate bản cũ**; **anchorDate bất biến qua version** (phase continuity) | P0 | ✅ engine · ✅ **UI re-version M1b** (pattern tile → "New version from date…" → builder prefill → changeRosterFrom) |
| B5 | **Override — 6 operations** (D2, Gate 0) | `CREATE` (có `timezone` bắt buộc, resolve đầy đủ UTC) / `UPDATE` (đổi giờ/template; **preserve UTC khi civil time không đổi** — P0-2) / `DELETE` (không soft-delete, D6) / `REPLACE` / `SPLIT` (parts theo thứ tự, không overlap, trong envelope — H-1; fail atomic) / `SWAP` (cùng job+timezone — D5; giữ id/timezone mỗi bên); target thiếu → `OCCURRENCE_NOT_FOUND` (P0-4); mọi op trả `OverrideResult{occurrences, issues}` | P0 | ✅ (6/6) |
| B5b | **Override chain semantics** (P0-6) | Mỗi override áp độc lập theo thứ tự trên state kế thừa; override fail không rollback override trước, không chặn override sau; override sau có thể nhắm vào ID do override trước tạo (VD UPDATE part của SPLIT) | P0 | ✅ |
| B6 | **Effective Schedule = baseline + overrides** | Render theo yêu cầu, không lưu cứng → `ScheduleRenderResult{occurrences, issues}`; `source` (baseline/created/modified) gán **tại nơi operation chạy**, `sourceOverrideId` chỉ làm audit trail (P0-5); duplicate id → issue (M3); không silent-drop | P0 | ✅ |
| B7 | **Override isolation** (INVARIANT-001) | Sửa occurrence #N không đổi pattern, không ảnh hưởng occurrence #N+1 trở đi | P0 | ✅ (property test) |
| B8 | **Override reason** | `reason: SWAP / OVERTIME / LEAVE / CUSTOM` — ghi chú lý do sửa ca | P0 | ✅ (type) |
| B9 | **Pattern builder UI** | Tạo pattern 4-on/4-off, 2-2-3, DuPont + **preview** schedule trước khi lưu (features/pattern_builder) | P0 | ✅ M1 |
| B10 | **Override UI** | Edit giờ (UPDATE) / đổi template (REPLACE) / xóa (DELETE) / thêm ca ngày OFF (CREATE) qua bottom sheet; SPLIT/SWAP UI = P2 | P0/P2 | ✅ M1 (UPDATE/REPLACE/DELETE/CREATE) · ⏳ SPLIT/SWAP |

### C. Pay Engine — Tiền (✅ core/money — Gate 1, UI chưa code)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| C1 | **PayRule versioned** (D6) | Base rate + differentials + overtime rules, theo `jobId`, `effectiveFrom/Until`; `getActivePayRule` query theo ngày | P0 | ✅ |
| C2 | **PayBreakdown — Cách B** | Tách bạch: `Regular Pay` (giờ không phải OT) + `Differentials` + `Overtime Pay` — **không double-count** (PAY-001..008 pass) | P0 | ✅ |
| C3 | **Pluggable Differential** | `NIGHT / WEEKEND / HOLIDAY / HAZARD / CALLBACK / CUSTOM`; mode `PERCENT/FLAT`; appliesTo `ALL_HOURS_IN_SHIFT` hoặc `HOURS_IN_WINDOW` (window wrap midnight, half-open overlap — PAY-013 5h) | P0 | ✅ |
| C4 | **Overtime multi-rule** | `SHIFT/DAY/WEEK` threshold + multiplier; nhiều rule cùng lúc → lấy **max()**; tie → multiplier cao hơn (plan2 §5.4); không cộng dồn | P0 | ✅ |
| C5 | **Weekly OT Allocation — LIFO** (5.7) | `allocateWeeklyOvertime` — OT gán cho ca cuối theo thứ tự thời gian; tràn sang ca trước; minh họa PAY-014 (3×14h=42h → Fri 2h OT, $1,505) + unit test overflow 14/14/14/1 | P0 | ✅ |
| C6 | **PayRule Snapshot** (INVARIANT-006) | PAY-011: v1 ($385) / v2 ($480) theo ngày ca; query lại ngày cũ luôn ra v1 | P0 | ✅ |
| C7 | **PayRuleTemplate Library** (5.6) | `payrule_templates.dart`: tpl-us-ca-nurse (SHIFT>8h + WEEK>40h ×1.5) — dùng trong PAY-010, + us-ny, us-tx, uk-nhs (WEEK>39h), de (DAY>8h + WEEK>40h) | P0 | ✅ |
| C8 | **Income breakdown dashboard** | Chi tiết: base + từng differential + OT + tổng, kèm disclaimer "Estimate — not official payroll" | P1 | ✅ Gate C (B2 mức tối thiểu: card Today + nhãn ước tính) · ✅ RC B3/B4 — `income/income_breakdown_screen.dart` (Date/Range · Hours · Regular/Differentials/OT/Total · disclaimer) · ✅ RC B6 Income Impact (preview persist:false, sheet CREATE/EDIT/DELETE + re-version) · ✅ RC B7 multi-job total |
| C9 | **Golden Test Suite (Money)** | `money_engine_cases.json` 14 case + `scripts/verify_money_cases.mjs` (15 check, Errors: 0); **PAY-013 expected đã sửa 6h→5h** (human approve) | P0 | ✅ |
| C10 | **Từ chối tính khi thiếu config** | Chưa cấu hình work-week boundary / state OT rule → hiện *"Cannot determine overtime because: ..."*, không đoán | P0 | ✅ Gate C (B2 — không có active PayRule → UNAVAILABLE kèm lý do, không bao giờ hiện số; test domain + UI) |

### D. Calendar & Màn hình chính (P0 — UI chưa code)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| D1 | **Today screen** | Ca hôm nay + ca tiếp theo, đếm ngược + giờ nghỉ trước ca sau, tổng giờ tuần (từ UTC); **thu nhập → M3** (chưa có PayRule editor; không đoán — Correctness Contract) | P0 | ✅ M1b (display; income M3) |
| D2 | **Calendar view** | **Week** grid 7 cột (local time, issue banner) + **Month** grid 6×7 (per job, drill vào week) | P0 | ✅ M1 + M1b |
| D3 | **Quick Add (1-tap template)** | Tap ngày → sheet liệt kê template job; tap template = CREATE ngay (giờ mặc định) · "Custom time…" = form đầy đủ | P0 | ✅ M1b |
| D4 | **Add Shift UI** | Chọn template/job, ngày, giờ (CREATE qua + trên cột ngày — M1); DST dialog khi giờ không tồn tại/bị lặp | P0 | ✅ CREATE cơ bản (M1) · ✅ DST dialog (Gate C B1) |
| D5 | **Multi-job cơ bản** | Jobs screen (tạo job + tz validated) + Job detail (templates, patterns, mỗi job timezone riêng) — PayRule per job = M3 | P0 | ✅ M1 (Jobs) |
| D6 | **.ics export (offline)** | Export lịch offline, không cần server (D8 — P0) | P0 | ✅ Gate C (B3 — generator RFC 5545 thuần + saver path_provider + action Export week ở JobDetail; 2 tests) |
| D7 | **Basic notifications** | Thông báo ca bắt đầu | P0 | ✅ Gate C (B4 — reminder baseline: spec thuần + wrapper guard flutter_local_notifications, wire TodayScreen; 4 tests; permission flow thật = device) |
| D8 | **Offline-first** (INVARIANT-008) | Calendar core (view/add/edit shifts) hoạt động hoàn toàn offline — SQLite file local (main.dart: `$HOME/.shiftease/shiftease.db` hoặc `SHIFTEASE_DB`), không cloud/account | P0 | ✅ M1 (local DB) |

### E. Import Pipeline (core engine ✅ Gate 2; OCR gated M4.5)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| E1 | **Smart Paste** | Paste text → regex + heuristics → schedule entries; ưu tiên **bậc 2** | P0 | ✅ engine + **UI M2** |
| E2 | **CSV/Excel import** | UI mapping cột → parser; ưu tiên **bậc 3** | P0/P1 | ✅ engine · 🔧 RC C1 — pure `import_validation.dart` (unmapped/duplicate/missing-times/DST gap) + 7 tests xong; UI mapping cột + service `parseCsv` chưa làm |
| E3 | **OCR + PDF import** | Tesseract/PaddleOCR → regex parser; **có gate**: chỉ build kiến trúc lớn sau spike-test 20–30 roster thật (M4.5 ≥70% dates, ≥60% shift types) | P1 | ⏳ OCR_PENDING_SPIKE gate |
| E4 | **Confidence Scoring** | Từng candidate shift có `HIGH/MEDIUM/LOW` theo date format, time format, template match, shift type | P0/P1 | ✅ engine + **UI M2** (badge + note) |
| E5 | **User Review UI (bắt buộc)** (D7, INVARIANT-004) | Mỗi candidate: `[✓ Accept] [✎ Edit] [✗ Reject]` + Confidence bar; bulk "Accept All High", "Review Remaining"; **không auto-commit** | P0/P1 | ✅ UI M2 (Review bắt buộc trước Commit) |
| E6 | **ImportSession audit** | Lưu raw extraction + candidates + committed IDs → truy vết nguồn gốc mọi ca ("Tại sao Sep 03 là Night?") | P1 | ✅ engine (candidateForOccurrenceId) |
| E11 | **Import→Money seam (integration)** | Commit xong → LIFO WEEK allocation (decoupled `allocateWeeklyOvertimeHours`) → Method B breakdown theo active PayRule; test: 3x14h $1505 (WEEK-only), $1785 (CA composition), INVARIANT-006 qua rate bump v1→v2 | P0 | ✅ test |
| E7 | **Re-import "What changed?"** | So sánh roster mới vs cũ: `added/removed/modified` (swap-pairing) + impact (hours, days; income cần PayRule ở calendar layer) | P1 | ✅ engine · 🔧 RC C2 — pure `import_diff.dart` (RosterDiff added/removed/modified/unchanged + hoursDelta) + 7 tests xong; UI diff card chưa làm |
| E8 | **Pattern auto-detection** | Tự phát hiện pattern từ lịch đã import | P1/P2 | ⏳ |
| E9 | **State machine import** | `IDLE → PARSING → EXTRACTED/ERROR → REVIEWING → COMMITTED`; parse fail → hiện lỗi, user sửa lại input | P0 | ✅ engine (history audit) |
| E10 | **Golden Test Suite (Import)** | `import_pipeline_cases.json`: happy path, INVARIANT-004 (no auto-commit), commit flow, CSV, re-import diff, medium confidence, parse failure, bulk accept | P0 | ✅ runner + verify script |
| E12 | **Import→Calendar seam (D-M2-1)** | Commit approved roster → ghi `occurrences` (jobId, isImported) + OFF dates; render: roster là nguồn chính cho ngày nó phủ (suppress pattern cùng ngày); re-import = replace window sau Review lại; template không khớp → templateId '' chip xám (D-M2-2) | P0 | ✅ UI M2 (schema v3) |

### F. Sự kiện ngoài ca làm (Calendar Event Model)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| F1 | **CalendarEvent supertype** | `type: SHIFT/TIME_OFF/PERSONAL/AVAILABILITY_BLOCK`; `source: user/partner/colleague`; `status: pending/accepted/declined`; `refId` | P0/P2 | ⏳ |
| F2 | **TimeOff** | PTO / Sick / Holiday / Unpaid / Personal Leave; nhiều ngày; `halfDay: NONE/AM/PM`; notes | P0/P1 | ⏳ |
| F3 | **PersonalEvent** | Sự kiện cá nhân: title, start/end, location, recurrence (DAILY/WEEKLY/MONTHLY) | P0/P1 | ⏳ |
| F4 | **AvailabilityBlock** | Khối FREE/BUSY/RECOVERY → dùng cho Availability Finder | P1 | ⏳ |
| F5 | **Availability Finder** | Tìm khung thời gian rảnh dựa trên ca + availability blocks + overlay | P1 | ⏳ |

### G. Sharing & Privacy (P1/P2)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| G1 | **Granular sharing — 3 modes** | `FULL` (ca + giờ + loại ca — gia đình/quản lý) / `BUSY_ONLY` (chỉ free/busy — đồng nghiệp) / `RECOVERY` (ca + recovery windows sau night shift) | P1 | ⏳ |
| G2 | **Share link** | Link anonymous UUID; người nhận chỉ thấy nội dung theo mode; revoke bất cứ lúc nào | P1 | ⏳ |
| G3 | **Partner/Family overlay** | Overlay lịch gia đình read-only lên lịch user (Privacy mode: Busy/Free/Recovery) | P1 | ⏳ |
| G4 | **Partner reverse-sharing** | Đối tác đề xuất sự kiện → user duyệt (pending/accepted/declined) | P2 | ⏳ |
| G5 | **Colleague sharing** | Read-only + "open to swap" (không approval flow) | P2 | ⏳ |
| G6 | **Dynamic Webcal** (D8) | Link tự cập nhật, subscribe được; server + token (64 chars random, expire 90 ngày, revoke trong Settings, 410 Gone khi hết hạn) | P1+ | ⏳ |
| G7 | **Data encryption** | SQLCipher local; AES-256-GCM E2E cho cloud sync + backup export (password) | P1+ | ⏳ |

### H. P2/P3 — Moat & Stickiness

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| H1 | **Shift change detection** | Employer đổi lịch → cảnh báo ảnh hưởng availability/thu nhập | P2 | 📋 |
| H2 | **Wellness nhẹ (rule-based)** | Cảnh báo chuỗi ca dài, recovery window sau night shift, thống kê giờ làm/nghỉ | P2 | 📋 |
| H3 | **Widgets** | Home screen widget hiển thị ca tiếp theo | P1 | 📋 |
| H4 | **Cloud backup** | Optional, E2E encrypted | P1 | 📋 |
| H5 | **Health AI** (circadian, nutrition, workout) | Ngoài phạm vi MVP | P3 | 📋 |
| H6 | **B2B / Team management** (duyệt nghỉ, admin, báo cáo) | Ngoài phạm vi MVP | P3 | 📋 |

---

## 4. Danh mục màn hình UI

| Màn hình | Nội dung chính | Phase |
|---|---|---|
| **Today** | Ca hôm nay, ca tiếp theo, đếm ngược giờ nghỉ trước ca sau, thu nhập hôm nay/tuần | P0 |
| **Calendar (Week/Month)** | Lưới lịch, ca theo local time, chuyển view week ↔ month | P0 |
| **Quick Add / Add Shift** | 1-tap từ template; form thêm ca (job, template, ngày, giờ); DST dialog khi cần | P0 |
| **Pattern Builder** | Chọn cycle (4-on/4-off, 2-2-3, DuPont), cấu hình sequence, **preview** schedule, ngày hiệu lực (versioning) | P0 |
| **Occurrence Edit** | Edit giờ, đổi template (UPDATE/REPLACE), xóa (DELETE), tách ca (SPLIT), hoán đổi (SWAP) | P0/P2 |
| **Import** | Chọn nguồn (paste/CSV/ảnh/PDF); **Review UI** từng candidate với Confidence bar + Accept/Edit/Reject + bulk actions | P0/P1 |
| **Re-import Diff** | "What changed?" — danh sách added/removed/modified + tác động thu nhập/availability | P1 |
| **Jobs** | Quản lý nhiều job: mỗi job có template, pay rule, timezone riêng | P0 |
| **Pay Rules** | Cấu hình base rate, differentials, overtime rules; chọn từ **template library** (US/UK/DE) | P0 |
| **Income breakdown** | Breakdown base + differential + OT + tổng (kèm "Ước tính") | P1 |
| **Availability Finder** | Tìm khung rảnh dựa trên ca + availability blocks | P1 |
| **Sharing** | Chọn mode (FULL/BUSY_ONLY/RECOVERY), tạo/revoke link | P1 |
| **Settings** | Jobs, pay rules, sharing, webcal token management, backup | P0/P1 |
| **DST Dialog** | Spring-forward: báo giờ không tồn tại; Fall-back: 2 options (VD: chọn EDT hay EST) | P0 |
| **Unable to calculate** | Hiện lý do cụ thể khi thiếu config pay (work-week boundary, state OT rule) | P0 |

---

## 5. Luồng (Flows) quan trọng

1. **Thêm ca qua DST** — local time rơi vào giờ không tồn tại/bị lặp → dialog chọn diễn giải → resolve UTC → tạo occurrence.
2. **Sửa ca (Override)** — user edit → tạo `Override` với operation rõ ràng → render lại Effective Schedule; pattern **không bị mutate** (INVARIANT-001).
3. **Đổi roster từ ngày X** — đóng pattern cũ (`effectiveUntil = X-1`), tạo bản mới (`effectiveFrom = X`), re-project từ X; ca trước X giữ nguyên (D1).
4. **Import roster** — parse → candidates + confidence → **user review bắt buộc** → commit (INVARIANT-004); ImportSession lưu để audit + re-import diff.
5. **Tính lương** — active PayRule tại ngày ca → duration từ UTC → regular hours + differentials + OT (multi-rule max, WEEK theo LIFO) → snapshot lưu vào occurrence (INVARIANT-006).
6. **Share lịch** — chọn mode → link anonymous UUID → người nhận xem theo mode → revoke khi cần.

---

## 6. Invariants được bảo vệ

| # | Invariant | Module |
|---|---|---|
| INVARIANT-001 | Pattern never mutates because an occurrence is edited | pattern |
| INVARIANT-002 | Duration luôn từ resolved UTC instants | time |
| INVARIANT-003 | Local civil time là cơ sở recurrence | time |
| INVARIANT-004 | Imported data không bao giờ commit nếu chưa user confirm | import |
| INVARIANT-005 | ShiftTemplate chỉ chứa time/UI — không pay semantics | pattern/money |
| INVARIANT-006 | Historical pay estimates là snapshot bất biến | money |
| INVARIANT-007 | Occurrence giữ nguyên timezone gốc | time |
| INVARIANT-008 | Core calendar hoạt động hoàn toàn offline | platform |

---

## 7. Ghi chú trạng thái hiện tại

- **Đã code:** `core/time` (Gate 0, resolver DB-driven), `core/pattern` (Gate 0, resolved-only + provenance + chain atomicity), `core/money` (Gate 1, Method B + LIFO + MAX-composition), `core/import` (Gate 2, non-OCR engine: state machine, confidence, commit atomic UTC, re-import diff), `core/db` (Gate 3 + M2, SQLite: migration user_version v3, typed repos, override append-only replay, INVARIANT-006 snapshot, renderJobSchedule từ active versions + override log + imported-roster merge/suppress). Tổng **164/164 tests pass** (db suite 18 incl. v1→v3 upgrade + import seam + 4 AC-2/3/6 Gate A) — *số tại thời điểm M2, trước Gate A/B; hiện tại xem các bullet Gate A/B (179) và Gate C (207) bên dưới*.
- **Golden test suites:** 3 file JSON đầy đủ (time 28 cases, money 14 cases PAY-001..014, import 8 cases IMPORT-001..008) + 3 verify scripts (time/money/import, Errors: 0) + CI `.github/workflows/test.yml` (6 jobs: + persistence-tests, paths thật).
- **Gate M1 (UI + domain):** repo → Flutter app (root), `lib/domain/schedule_service.dart`, `lib/features/{jobs,templates,pattern_builder,calendar,occurrence}`, `lib/app` + `lib/main.dart`. DoD e2e (job → template → pattern → calendar tuần → edit ca → persist) chạy trong widget test với SQLite thật; **5 tests domain+UI pass**. Xem `plan5_m1_ui.md` + `result11_gate_m1.txt`.
- **Gate M1b (UI):** Today screen + Month view + Quick Add 1-tap + re-version UI (D9). **4 tests UI mới**; domain+UI = 9 (thời điểm đó). Xem `plan6_m1b.md` + `result12_m1b.txt`.
- **Gate M2 (Import UI):** `features/import/import_screen.dart` (Smart Paste → Review bắt buộc → Commit → calendar seam D-M2-1 A, schema v3). **4 widget tests mới** (DoD e2e restart file DB, reject, atomic DST-gap, INVARIANT-004); domain+UI = 13 (thời điểm đó). Xem `plan7_m2_import_ui.md` + `result13_gate_m2.txt`.
- **Gate A/B (2026-09-06):** `prompt_gate_a_b.md` — A1 production composition (`composeService` trong `main.dart`, AC-1 test) · A2 commit 1 transaction + ROLLBACK (AC-2) · A3 `windowStart`/`windowEnd` bắt buộc khi committed + OFF per-day window (bỏ lọc `!= '[]'`, AC-3) · A4 SWAP `effectiveJobId` (imported có jobId riêng) + từ chối `INCOMPLETE_SWAP` (AC-4) · A5 partial-commit warning + dialog xác nhận (AC-5) · A6 Pattern/PayRule version immutability, D9 close (effectiveUntil) được phép (AC-6). **179/179 tests pass** (core 164 + domain 4 + UI 11) — `flutter analyze` clean; 0 regression. Xem `result14_gate_a.txt`.
- **Gate C (2026-09-07):** `prompt_gate_c.md` — Phần A integrity: A1 chỉ REVIEWING→COMMIT (EXTRACTED + zero-approved reject) · A2 changeRosterFrom 1 transaction + rollback · A3 saveOverride idempotent/diff→ImmutableHistoryError · A4 session COMMITTED immutable · A5 ADV-1..5 bundle + full regression. Phần B product: B1 DST dialog (không auto-pick, không ghi khi DST) · B2 income estimate + PayRule editor + nhãn ước tính · B3 ICS export offline · B4 reminder baseline · B5 pubspec path_provider + flutter_local_notifications + android/ios folders (**KHÔNG build apk local**). **207/207 tests pass** (core 176 + domain 9 + UI 16 + features 6) — analyze clean, 0 regression (179/179 cũ). Xem `result15_gate_c.txt`.
- **Chưa xong (RC plan8 đang chạy — xem `.plan/plan8_m3_income.md` §15):** CSV mapping UI + re-import diff UI (C1/C2 — pure xong, UI chưa), DST final UX (D), notification stale cancel/lifecycle/permission (E1–E3, permission device), backup/restore (F), SQLCipher native (G, device verify), Settings (H), mobile readiness (I), adversarial bổ sung (J), evidence `result16_rc.txt`. **Sau RC:** SPLIT/SWAP UI (P2), OCR (gated M4.5 spike), calendar event model, sharing.
- **Roadmap:** M0 Foundation (core engines 0–2 ✅) → M1 Basic Calendar (UI + persistence) → M2 Import (UI ✅ M2 — Smart Paste + Review + commit seam; CSV/diff UI M2b) → M3 Multi-Job + Pay → M4 Export & Share → **M4.5 OCR Spike Test (gate: ≥70% dates, ≥60% shift types, nếu không đạt thì không làm M5)** → M5 OCR Import → M6 Cloud.
- **RC plan8 (2026-09-07, đang chạy):** `plan8_m3_income.md` Release Candidate — A1–A8 integrity ✅ (write boundary, imported-only CREATE, materialized scoped REPLACE, import state-machine/conflict verify, override/PayRule integrity) · B1–B7 income ✅ (estimator parity HOURS_IN_WINDOW + goldens, per-occurrence rule, breakdown screen, range/month, presets library, Income Impact, multi-job total) · C1/C2 pure ✅ (CSV validation + re-import diff) — **249/249 tests pass, analyze clean**; còn C1/C2 UI + D–J + evidence/docs. Không làm trong batch: OCR/Cloud/Sharing/CalendarEvent/AI/B2B/Tax (§14).