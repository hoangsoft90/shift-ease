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
| `core/time` | ✅ Implement | `lib/core/time/` — 24 unit tests pass |
| `core/pattern` | ✅ Implement | `lib/core/pattern/` — 31 engine tests + 5 property tests + 4 integration tests pass |
| `core/money` | ⏳ Chưa code | Đã có golden test suite `test/golden/money_engine_cases.json` (13 cases PAY-001→014) |
| Import pipeline | ⏳ Chưa code | Đã có `test/golden/import_pipeline_cases.json` (8 cases IMPORT-001→008) |
| Golden tests (Time) | ✅ | `test/golden/time_engine_cases.json` (20 cases) |
| UI / features / domain / data / platform | ⏳ Chưa code | Kiến trúc đã chốt trong plan2 §1.1 |
| CI | ✅ | `.github/workflows/test.yml` — 5 jobs + gate rule |

---

## 3. Tính năng theo nhóm

### A. Time Engine — Độ chính xác thời gian (✅ core/time)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| A1 | **Civil Time Architecture** | 3 khái niệm tách bạch: Local Civil Time (cơ sở recurrence/UI), UTC Instant (sắp xếp/reminder), Elapsed Duration (đầu vào Pay Engine) | P0 | ✅ |
| A2 | **Resolve local → UTC** | Chuyển đổi local civil time sang UTC instant, có xử lý overnight (`+1` / endHour < startHour) | P0 | ✅ |
| A3 | **Tính duration từ UTC** (INVARIANT-002) | Duration luôn từ `utcEnd - utcStart`, không trừ giờ local — ca bắc DST spring-forward = 7h, fall-back = 9h | P0 | ✅ |
| A4 | **DST non-existent time** (D4) | Giờ không tồn tại (spring-forward) → **không tự quyết**, trả lỗi `NONEXISTENT_LOCAL_TIME` → UI hiện dialog | P0 | ✅ (engine) |
| A5 | **DST ambiguous time** (D4) | Giờ bị lặp (fall-back) → trả `AMBIGUOUS_LOCAL_TIME` kèm danh sách 2 options (EDT/EST...) → UI hiện dialog cho user chọn | P0 | ✅ (engine) |
| A6 | **Ambiguous end-time** | End time bị lặp cũng không auto-select — xử lý y hệt start time (sửa bug DST-008) | P0 | ✅ |
| A7 | **Timezone retention** (INVARIANT-007) | Occurrence giữ nguyên timezone gốc kể cả khi user đổi timezone thiết bị | P0 | ✅ |
| A8 | **Recurrence theo local time** (INVARIANT-003) | Ca 22:00 chạy xuyên đêm DST không bị lệch giờ hiển thị | P0 | ✅ |
| A9 | **Golden Test Suite** | `time_engine_cases.json`: DST Mỹ/UK/Úc, southern hemisphere, ranh giới tháng/năm, error cases, invariant cases | P0 | ✅ |
| A10 | **DST resolution dialog (UI)** | Khi giờ không tồn tại/bị lặp: dialog xác nhận, user chọn diễn giải — **không tự làm tròn/đoán** | P0 | ⏳ (UI chưa code) |

### B. Pattern → Occurrence → Override (✅ core/pattern)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| B1 | **Shift Template** | Chỉ chứa time/UI: `startTime`, `endTime`, `breakDurationMinutes`, `color` — **không chứa pay** (INVARIANT-005, D5) | P0 | ✅ (type) |
| B2 | **Shift Pattern** | Cycle lặp: `FIXED_CYCLE` (4-on/4-off, 2-2-3, DuPont) + chừa `ALTERNATING_WEEKS` / `CUSTOM`; sequence chứa `null` = OFF day | P0 | ✅ |
| B3 | **Project occurrences** | Sinh baseline occurrences từ pattern trong date range; OFF day không sinh ca; template thiếu → lỗi `MISSING_TEMPLATE` (không silent skip) | P0 | ✅ |
| B4 | **Pattern versioning** (D1) | Đổi roster từ ngày X → tạo pattern bản mới (`effectiveFrom`/`effectiveUntil`), **không mutate bản cũ** | P0 | ✅ |
| B5 | **Override — 6 operations** (D2) | `CREATE` (thêm ca, VD ca overtime) / `UPDATE` (đổi giờ/template) / `DELETE` (OFF, hủy ca) / `REPLACE` (Day→Night) / `SPLIT` (1 ca → nhiều phần) / `SWAP` (hoán đổi 2 ca) | P0 | ✅ (5/6 — UPDATE còn lỗi P3: chưa áp đổi giờ) |
| B6 | **Effective Schedule = baseline + overrides** | Render theo yêu cầu, không lưu cứng; đánh dấu `source: baseline/override/created` | P0 | ✅ |
| B7 | **Override isolation** (INVARIANT-001) | Sửa occurrence #N không đổi pattern, không ảnh hưởng occurrence #N+1 trở đi | P0 | ✅ (property test) |
| B8 | **Override reason** | `reason: SWAP / OVERTIME / LEAVE / CUSTOM` — ghi chú lý do sửa ca | P0 | ✅ (type) |
| B9 | **Pattern builder UI** | Tạo pattern 4-on/4-off, 2-2-3, DuPont + **preview** schedule trước khi lưu | P0 | ⏳ (UI chưa code) |
| B10 | **Override UI** | Edit/delete ca từ lịch; split/swap UI mượt (P2) | P0/P2 | ⏳ (UI chưa code) |

### C. Pay Engine — Tiền (⏳ core/money chưa code, đã có golden tests)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| C1 | **PayRule versioned** (D6) | Base rate + differentials + overtime rules, theo `jobId`, `effectiveFrom/Until` | P0 | ⏳ |
| C2 | **PayBreakdown — Cách B** | Tách bạch: `Regular Pay` (giờ không phải OT) + `Differentials` + `Overtime Pay` — **không double-count** | P0 | ⏳ |
| C3 | **Pluggable Differential** | `NIGHT / WEEKEND / HOLIDAY / HAZARD / CALLBACK / CUSTOM`; mode `PERCENT/FLAT`; appliesTo `ALL_HOURS_IN_SHIFT` hoặc `HOURS_IN_WINDOW` (window start/end local) | P0 | ⏳ |
| C4 | **Overtime multi-rule** | `SHIFT/DAY/WEEK` threshold + multiplier; nhiều rule cùng lúc → lấy **max()** giữa các rule, không cộng dồn | P0 | ⏳ |
| C5 | **Weekly OT Allocation — LIFO** (5.7) | Tuần vượt ngưỡng → OT gán cho **ca cuối cùng theo thứ tự thời gian**; tràn sang ca trước nếu ca cuối không đủ giờ; minh họa PAY-014 (3×14h = 42h → Fri nhận 2h OT, tổng $1,505) | P0 | ⏳ |
| C6 | **PayRule Snapshot** (INVARIANT-006) | Historical earnings = snapshot bất biến; PayRule mới **không rewrite** earnings cũ | P0 | ⏳ |
| C7 | **PayRuleTemplate Library** (5.6) | Template theo ngành/quốc gia: US-CA (SHIFT>8h + WEEK>40h ×1.5), US-NY, US-TX, UK NHS (WEEK>39h), DE (DAY>8h + WEEK>40h); night/weekend/holiday differential mặc định | P0 | ⏳ |
| C8 | **Income breakdown dashboard** | Chi tiết: base + từng differential + OT + tổng, kèm disclaimer "Ước tính" | P1 | ⏳ |
| C9 | **Golden Test Suite (Money)** | `money_engine_cases.json`: base pay, từng differential, OT theo SHIFT/DAY/WEEK, multi-differential + OT, window differential, versioning, template US-CA | P0 | ✅ (test data) |
| C10 | **Từ chối tính khi thiếu config** | Chưa cấu hình work-week boundary / state OT rule → hiện *"Cannot determine overtime because: ..."*, không đoán | P0 | ⏳ |

### D. Calendar & Màn hình chính (P0 — UI chưa code)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| D1 | **Today screen** | Ca hôm nay + ca tiếp theo, giờ nghỉ trước ca sau, thu nhập hôm nay/tuần này (thuần hiển thị, không AI) | P0 | ⏳ |
| D2 | **Calendar view** | Week + Month; hiển thị ca theo local time | P0 | ⏳ |
| D3 | **Quick Add (1-tap template)** | Thêm ca nhanh từ template có sẵn — ưu tiên nhập liệu **bậc 1** | P0 | ⏳ |
| D4 | **Add Shift UI** | Chọn template/job, ngày, giờ; xử lý overnight và DST dialog | P0 | ⏳ |
| D5 | **Multi-job cơ bản** | Mỗi job có bộ ShiftTemplate + PayRule + timezone riêng | P0 | ⏳ |
| D6 | **.ics export (offline)** | Export lịch offline, không cần server (D8 — P0) | P0 | ⏳ |
| D7 | **Basic notifications** | Thông báo ca bắt đầu | P0 | ⏳ |
| D8 | **Offline-first** (INVARIANT-008) | Calendar core (view/add/edit shifts) hoạt động hoàn toàn offline; không yêu cầu cloud/account | P0 | ⏳ |

### E. Import Pipeline (⏳ chưa code, đã có golden tests)

| # | Tính năng | Mô tả | Phase | Trạng thái |
|---|---|---|---|---|
| E1 | **Smart Paste** | Paste text → regex + heuristics → schedule entries; ưu tiên **bậc 2** | P0 | ⏳ |
| E2 | **CSV/Excel import** | UI mapping cột → parser; ưu tiên **bậc 3** | P0/P1 | ⏳ |
| E3 | **OCR + PDF import** | Tesseract/PaddleOCR → regex parser; **có gate**: chỉ build kiến trúc lớn sau spike-test 20–30 roster thật (M4.5) | P1 | ⏳ |
| E4 | **Confidence Scoring** | Từng candidate shift có `HIGH/MEDIUM/LOW` theo date format, time format, template match, shift type | P0/P1 | ⏳ |
| E5 | **User Review UI (bắt buộc)** (D7, INVARIANT-004) | Mỗi candidate: `[✓ Accept] [✎ Edit] [✗ Reject]` + Confidence bar; bulk "Accept All High", "Review Remaining"; **không auto-commit** | P0/P1 | ⏳ |
| E6 | **ImportSession audit** | Lưu raw extraction + candidates + committed IDs → truy vết nguồn gốc mọi ca ("Tại sao Sep 03 là Night?") | P1 | ⏳ |
| E7 | **Re-import "What changed?"** | So sánh roster mới vs cũ: `added/removed/modified` + impact (hours, income, availability) | P1 | ⏳ |
| E8 | **Pattern auto-detection** | Tự phát hiện pattern từ lịch đã import | P1/P2 | ⏳ |
| E9 | **State machine import** | `IDLE → PARSING → EXTRACTED/ERROR → REVIEWING → COMMITTED`; parse fail → hiện lỗi, user sửa lại input | P0 | ⏳ |
| E10 | **Golden Test Suite (Import)** | `import_pipeline_cases.json`: happy path, INVARIANT-004 (no auto-commit), commit flow, CSV, re-import diff, medium confidence, parse failure, bulk accept | P0 | ✅ (test data) |

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

- **Đã code (Bước 1–3):** `core/time` (A1–A9) và `core/pattern` (B1–B7, trừ lỗi P3 ở B5 — UPDATE chưa áp đổi giờ). Tổng 55 tests pass (24 time + 22 pattern + 5 property + 4 integration).
- **Golden test suites:** đã có đủ 3 file JSON (time 20 cases, money 13 cases, import 8 cases) + script `scripts/verify_all_cases.mjs` + CI `.github/workflows/test.yml`.
- **Chưa code:** toàn bộ UI, `core/money`, import pipeline, domain/data/platform layers.
- **Roadmap:** M0 Foundation (core engines) → M1 Basic Calendar → M2 Import → M3 Multi-Job + Pay → M4 Export & Share → **M4.5 OCR Spike Test (gate: ≥70% dates, ≥60% shift types, nếu không đạt thì không làm M5)** → M5 OCR Import → M6 Cloud.