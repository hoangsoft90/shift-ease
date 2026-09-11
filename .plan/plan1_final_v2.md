# ShiftEase — Kế hoạch tổng hợp cuối cùng v2 (Domain-Hardened)

> Tổng hợp từ: `plan1_final.md` + 5 bản review kiến trúc (`plan1_final_review1` → `plan1_final_review5`)
> Mục tiêu: khóa toàn bộ quyết định domain-model còn mở, để `plan2` chỉ còn việc viết đặc tả kỹ thuật chi tiết và giao cho AI coding agents.

---

## 0. Verdict

**Tầm nhìn sản phẩm đã chốt (không đổi so với `plan1_final.md`). Domain model CHƯA sẵn sàng để code.**

Điểm số trung bình từ 5 review: Product direction 9/10, Target persona 9/10, Differentiation 8/10 — nhưng **Pay Engine 5.5/10, Import Strategy 6/10, Domain Model 6.5–7/10**. Không có lỗi "fatal" nào khiến phải bỏ ý tưởng, nhưng có **8 quyết định kiến trúc (D1–D8)** nếu không khóa trước, AI coding agents sẽ dựng một hệ thống nhìn đẹp nhưng domain model gãy khi gặp dữ liệu thật — và sửa sau (đặc biệt trong database đã có dữ liệu) sẽ rất tốn.

**Lộ trình đúng:**

```
plan1_final_v2 (văn bản này)
       ↓
plan2 — Domain Model + Time/Pattern/Pay Engine spec + Import Pipeline + Test Strategy
       ↓
Review plan2
       ↓
Implementation Spec + Golden Test Suite
       ↓
AI coding agents (module theo module, core/time và core/pattern trước tiên)
```

**Không nên:** `plan1_final → AI agent → code → phát hiện lỗi domain → migration đau đớn`.

---

## 1. Điều không đổi so với `plan1_final.md`

- Định vị: **Personal Operating System for Shift Workers**, 3 trụ cột Work – Life – Money
- Target persona: Nurse/Healthcare 25–45, Mỹ/Anh/Đức, ca xoay 3 kíp, đa nguồn thu nhập, có gia đình
- Đối thủ (Supershift, MyShiftPlanner) đã có pattern/roster — đây là **table stakes**, không phải USP
- 3 trục differentiation thật: **(1) nhập liệu nhanh, (2) tính đúng tuyệt đối về mặt kỹ thuật (đổi tên thành Correctness Contract — xem mục 2), (3) UX đơn giản**
- Loại Health AI + B2B khỏi MVP (giữ wellness nhẹ rule-based ở P2)
- Monetization: Free/Pro, Lifetime $39.99 ưu tiên giai đoạn đầu
- Phạm vi địa lý MVP: Mỹ, Anh, Đức

---

## 2. Correctness Contract (thay cho "tính đúng tuyệt đối")

Không hệ thống production nào nên promise "absolute correctness", đặc biệt với DST, timezone, payroll, OCR, luật overtime theo bang/quốc gia. Nguyên tắc thay thế, áp dụng cho **mọi** module (Time, Pattern, Pay, Import):

> **Với cùng input hợp lệ + cùng timezone database version + cùng pay rule version → kết quả phải deterministic.**
> **Không được silently đưa ra kết quả khi input/rule không đủ để tính — phải báo rõ "Unable to calculate accurately" kèm lý do.**

Ví dụ: nếu chưa cấu hình work-week boundary hoặc chưa chọn state overtime rule, app phải nói *"Cannot determine overtime because: work week boundary not configured"* — không đoán.

**Nguyên tắc sản phẩm:** *"Không biết" tốt hơn "tính sai".* Mọi số tiền hiển thị vẫn giữ nhãn "Ước tính" (đã có ở `plan1_final.md`), nhưng giờ đây có thêm cơ chế từ chối tính toán khi thiếu dữ liệu thay vì âm thầm dùng giá trị mặc định sai.

---

## 3. Civil Time Architecture (Time Engine — hardened)

Ba khái niệm thời gian phải tách biệt rõ trong data model, không được để AI agent tự suy diễn:

| Khái niệm | Dùng để | Ví dụ |
|---|---|---|
| **Local Civil Time** (wall-clock) | Cơ sở của recurrence, hiển thị UI, ý định người dùng | `22:00 America/New_York` |
| **UTC Instant** | Sắp xếp sự kiện, trigger reminder, so sánh mốc thời gian | `2026-11-01T02:00:00Z` |
| **Elapsed Duration** | Tổng giờ làm, input cho Pay Engine | Số giây thực tế trôi qua |

**D3 (Recurrence basis) — CHỐT: Local Civil Time (wall-clock), không phải UTC interval.** Đây là cách duy nhất để ca 22:00 chạy xuyên suốt các đêm DST mà không bị lệch giờ hiển thị.

**D4 (DST ambiguity) — CHỐT: Không tự quyết định.** Khi giờ local không tồn tại (spring-forward) hoặc bị lặp (fall-back), hệ thống hiện dialog xác nhận cho người dùng chọn diễn giải, thay vì tự làm tròn hoặc đoán.

### Golden Test Suite (bắt buộc viết trước khi code)

- File `time_engine_cases.json` chứa hàng trăm test case dạng input/expected (timezone, start/end local, expected UTC start/end, expected duration)
- Case bắt buộc: ca bắc qua DST spring-forward (7 tiếng thay vì 8), DST fall-back (9 tiếng thay vì 8), ca 23:30→01:30 bắc qua đêm fall-back ở EU, ca bắc qua ranh giới năm/tháng, user đổi timezone thiết bị giữa chừng (occurrence cũ giữ nguyên timezone gốc)
- Property test cho Pattern: `occurrence[n + cycleLength]` phải cùng vị trí pattern như `occurrence[n]`; sửa occurrence #10 không được làm thay đổi occurrence #11 trở đi trừ khi user sửa pattern
- Mỗi lần AI agent sửa `core/time` hoặc `core/pattern` → chạy toàn bộ golden tests trước khi merge

---

## 4. Pattern → Occurrence → Override (Pattern Engine — hardened)

### Source of truth

> **Pattern = source of truth cho recurring schedule. Occurrence = projection/materialization. Override = lớp ghi đè.**
>
> **Effective Schedule = Pattern baseline + Overrides** (tính khi render, không lưu cứng)

### D1 (Pattern versioning) — CHỐT

Khi user đổi roster từ ngày X (VD: "From Oct 1, chuyển từ 4-on/4-off sang 3-on/4-off"), **không mutate pattern cũ**:

```
Pattern A   effective_from = Sep 1    effective_until = Sep 30
Pattern B   effective_from = Oct 1    effective_until = null (đang active)
```

Áp dụng versioning tương tự cho `PayRule` và `ShiftTemplate` (đổi lương cơ bản, đổi giờ ca chuẩn) — dùng chung một khuôn `VersionedEntity { effective_from, effective_until }`.

### D2 (Occurrence override) — CHỐT

Thay `isException: boolean` bằng **Override object** với `operation` rõ ràng:

```typescript
type OverrideOperation = 'CREATE' | 'UPDATE' | 'DELETE' | 'REPLACE' | 'SPLIT' | 'SWAP';

interface Override {
  id: string;
  occurrenceId: string;          // occurrence gốc bị ảnh hưởng
  operation: OverrideOperation;
  payload: unknown;              // dữ liệu cụ thể theo từng operation
  swapWithOccurrenceId?: string; // chỉ dùng khi operation = SWAP
  createdAt: string;
  reason?: 'SWAP' | 'OVERTIME' | 'LEAVE' | 'CUSTOM';
}
```

Case thực tế cần cover: Delete (Sep 3 = OFF), Replace (Day → Night), Modify giờ (07:00–19:00 → 08:00–20:00), Split (07:00–11:00 + 15:00–19:00), Add (ca gốc + 4h overtime), Swap (Sep 3 ↔ Sep 7).

### Pattern mở rộng (kiến trúc chừa chỗ, không cần implement hết ở MVP)

```typescript
type PatternType = 'FIXED_CYCLE' | 'ALTERNATING_WEEKS' | 'CUSTOM';
```

MVP chỉ cần `FIXED_CYCLE` (4-on/4-off, 2-2-3, DuPont). Nhưng thiết kế `type` field ngay từ đầu để không phải phá schema khi thêm "tuần lẻ/chẵn xoay ca" hoặc quy tắc phức tạp hơn sau này.

---

## 5. Domain Event Model (mở rộng khỏi Shift)

Schema hiện tại gần như chỉ có Shift — quá hẹp cho Availability Finder và Family Overlay. Formalize thành:

```
CalendarEvent
├── ShiftOccurrence     (ca làm việc, sinh từ Pattern)
├── TimeOff              (PTO / Sick / Holiday)
├── PersonalEvent        (sự kiện cá nhân, không liên quan công việc)
└── AvailabilityBlock    (khối thời gian rảnh/bận, dùng cho Availability Finder)
```

`CalendarEvent` nên có `source: 'user' | 'partner' | 'colleague'` và `status: 'pending' | 'accepted' | 'declined'` — chừa sẵn cho tính năng partner đề xuất sự kiện vào lịch user (P2/P3, không làm ở MVP nhưng schema không nên chặn đường).

---

## 6. Job/Workplace là First-Class Entity

Mỗi Job (Hospital A, Agency B) sở hữu **riêng**:

- Bộ `ShiftTemplate` riêng
- Bộ `PayRule` riêng
- Timezone mặc định riêng (nếu cần)

Lý do: cùng "Night 19:00–07:00" nhưng Hospital A trả $35/h, Agency trả $48/h là chuyện rất phổ biến với nurse làm nhiều nơi. Để `ShiftTemplate` ở cấp global sẽ gãy ngay khi user có 2 job.

---

## 7. Pay Engine — hardened

### D5 (Pay semantics trong Template) — CHỐT: KHÔNG.

`ShiftTemplate` chỉ chứa thời gian/UI (`startTime`, `endTime`, `breakDurationMinutes`, `color`). Không chứa `payMultiplier`. Toàn bộ ngữ nghĩa tiền tệ chuyển sang `PayRule`, gắn theo `jobId`, versioned.

### D6 (Pay versioning) — CHỐT

**Historical earnings là snapshot tại thời điểm tính, không bị rewrite khi user sửa PayRule sau này.** Nếu lương tăng từ 2026-07-01, các ca đã làm trước đó vẫn hiển thị đúng mức lương cũ.

### Pluggable Differential (thay vì field cố định)

```typescript
interface PayRule {
  id: string;
  jobId: string;
  effectiveFrom: string;
  effectiveUntil: string | null;
  baseHourlyRate: number;
  differentials: PayDifferential[];   // pluggable, không hard-code
  overtimeRules: OvertimeRule[];
}

interface PayDifferential {
  id: string;
  type: 'NIGHT' | 'WEEKEND' | 'HOLIDAY' | 'HAZARD' | 'CALLBACK' | 'CUSTOM';
  calc: { mode: 'PERCENT' | 'FLAT'; value: number };
  appliesTo: 'ALL_HOURS_IN_SHIFT' | 'HOURS_IN_WINDOW';
  window?: { startLocal: string; endLocal: string }; // nếu appliesTo = HOURS_IN_WINDOW
}

interface OvertimeRule {
  thresholdHours: number;
  period: 'SHIFT' | 'DAY' | 'WEEK';
  multiplier: number;
}
```

Thiết kế pluggable giúp thêm sau: hazard pay, call-back pay, shift-length premium — không cần đổi schema gốc, chỉ thêm `type` mới.

### Pay Rule Template Library (giữ từ `plan1_final.md`)

Cung cấp sẵn template theo ngành + quốc gia (VD: "US Hospital Nurse — California overtime rule") để người dùng mới không phải tự cấu hình từ đầu → tránh tính sai ngay từ lần dùng đầu tiên.

### Nguyên tắc hiển thị (giữ nguyên)

Mọi số tiền luôn kèm **breakdown chi tiết** (base + night + weekend + OT + ...) và nhãn **"Ước tính — không phải bảng lương chính thức"**.

---

## 8. Smart Import Pipeline — hardened

### D7 (Import safety) — CHỐT: Bắt buộc User Review, không bao giờ auto-commit.

```
Image / PDF / Excel / CSV / Paste text
            ↓
     Document Parser
            ↓
     Raw Extraction
            ↓
   Schedule Interpretation
            ↓
     Candidate Shifts (kèm Confidence Score: High/Medium/Low)
            ↓
        USER REVIEW  ← bắt buộc, user sửa được trước khi commit
            ↓
      Commit to Calendar
```

**Confidence Score** hiển thị theo từng candidate shift (VD: "Sep 03 Night 19:00–07:00 — Confidence: High" vs "Sep 07 ? 07:00–19:00 — Confidence: Low, vui lòng xác nhận"). Lý do: OCR sai → lịch sai → payroll sai → mất trust ngay từ lần dùng đầu.

### ImportSession (bổ sung mới)

Lưu lại dữ liệu thô đã parse + mapping tới các `ShiftOccurrence` đã tạo, gắn nhãn theo từng lần import:

- Cho phép user kiểm tra lại nguồn gốc một ca khi phát hiện sai
- Hỗ trợ **"Re-import" khi employer gửi roster mới**: app so sánh với lịch cũ, hiển thị **"What changed?"** (đã đổi ca nào, ảnh hưởng thu nhập/availability ra sao) — đây là tính năng rất thực tế, ít đối thủ làm tốt

### Thứ tự ưu tiên nhập liệu (đã điều chỉnh, KHÔNG nhảy thẳng OCR)

| Bậc | Phương thức | Ưu tiên | Ghi chú |
|---|---|---|---|
| 1 | Quick Add (1-tap template) | **P0** | |
| 2 | Paste text / Smart Paste | **P0** | Rủi ro thấp, giá trị cao ngay |
| 3 | CSV/Excel với mapping cột | **P0/P1** | |
| 4 | Image OCR + PDF | **P1** | **Có gate**: chỉ commit kiến trúc lớn sau khi spike-test với 20–30 roster thật, đo % correct dates/shift type/start-end/manual corrections cần thiết. Không cam kết P0. |
| 5 | Pattern auto-detection từ lịch đã import | **P1/P2** | |

*(OCR vẫn là hook marketing mạnh nhất — "Screenshot your hospital roster. ShiftEase does the rest." — nhưng kiến trúc lớn không nên commit trước khi có dữ liệu thật để đo độ chính xác.)*

---

## 9. Webcal vs Offline-first

### D8 (Webcal) — CHỐT

- **Offline Export (.ics file)**: P0, không cần server, hoạt động ngay trong kiến trúc offline-first
- **Dynamic Webcal** (link tự cập nhật, subscribe được): cần server + token + cơ chế **revoke/expiration** — đây là kiến trúc khác hẳn offline-first, để ở **P1+**

Không giả định Dynamic Webcal hoạt động trong kiến trúc offline-only ban đầu — đây là điểm hai bản plan trước đó đã mâu thuẫn ngầm.

---

## 10. Architectural Invariants (kim chỉ nam cho AI Agents)

```
INVARIANT-001  Pattern never mutates because an occurrence is edited.
INVARIANT-002  Duration is always calculated from resolved UTC instants,
               never from local-time subtraction (localEnd - localStart).
INVARIANT-003  Local civil time is the basis of recurrence.
INVARIANT-004  Imported data never commits without explicit user confirmation.
INVARIANT-005  ShiftTemplate contains time/UI semantics only — no pay semantics.
INVARIANT-006  Historical pay estimates are immutable snapshots; a new
               PayRule version never rewrites past earnings.
INVARIANT-007  Existing occurrences keep their original timezone even if
               the user's device timezone changes.
INVARIANT-008  Core calendar (view, add, edit shifts) works fully offline.
```

### NEVER list (rút gọn, cho AI agent dễ tuân thủ)

```
NEVER:
- calculate overnight duration from local clock subtraction
- mutate Pattern when editing an occurrence
- auto-commit OCR/import result without user review
- infer payroll rules silently when config is incomplete
- change historical occurrence timezone
- mix pay multiplier into ShiftTemplate
- let current PayRule rewrite historical earnings
- require cloud/account for core calendar to function
```

### Human-in-the-loop cho module lõi

Với mỗi module thuộc `core/time`, `core/pattern`, `core/money`: yêu cầu AI agent sinh kèm **bộ unit test + file giải thích logic**. Con người review test và giải thích trước khi chấp nhận merge — không chỉ nhìn code chạy được là đủ.

---

## 11. Data Schema tổng hợp (cập nhật từ `plan1_final.md`)

```typescript
// Job / Workplace — first-class
interface Job {
  id: string;
  name: string;              // "Hospital A - ICU"
  defaultTimezone: string;
}

// Shift Template — CHỈ thời gian/UI, không có pay
interface ShiftTemplate {
  id: string;
  jobId: string;
  name: string;
  code: string;
  color: string;
  startTime: string;         // "07:00" local
  endTime: string;           // "19:00" local
  breakDurationMinutes: number;
}

// Shift Pattern — versioned
interface ShiftPattern {
  id: string;
  jobId: string;
  name: string;
  type: 'FIXED_CYCLE' | 'ALTERNATING_WEEKS' | 'CUSTOM';
  cycleLengthDays: number;
  sequence: (string | null)[];   // ShiftTemplate IDs hoặc null (OFF)
  anchorDate: string;
  effectiveFrom: string;
  effectiveUntil: string | null;
}

// Shift Occurrence — projection từ Pattern
interface ShiftOccurrence {
  id: string;
  patternId: string;
  shiftDate: string;             // "2026-09-01", key hiển thị
  templateId: string;
  startDateTimeUtc: string;
  endDateTimeUtc: string;
  timezone: string;              // cố định tại thời điểm tạo, không tự đổi
  actualPayEstimate?: number;
}

// Override — thay cho isException
type OverrideOperation = 'CREATE' | 'UPDATE' | 'DELETE' | 'REPLACE' | 'SPLIT' | 'SWAP';
interface Override {
  id: string;
  occurrenceId: string;
  operation: OverrideOperation;
  payload: unknown;
  swapWithOccurrenceId?: string;
  createdAt: string;
  reason?: 'SWAP' | 'OVERTIME' | 'LEAVE' | 'CUSTOM';
}

// Pay Rule — tách khỏi template, versioned, pluggable
interface PayRule {
  id: string;
  jobId: string;
  effectiveFrom: string;
  effectiveUntil: string | null;
  baseHourlyRate: number;
  differentials: PayDifferential[];
  overtimeRules: OvertimeRule[];
}
interface PayDifferential {
  id: string;
  type: 'NIGHT' | 'WEEKEND' | 'HOLIDAY' | 'HAZARD' | 'CALLBACK' | 'CUSTOM';
  calc: { mode: 'PERCENT' | 'FLAT'; value: number };
  appliesTo: 'ALL_HOURS_IN_SHIFT' | 'HOURS_IN_WINDOW';
  window?: { startLocal: string; endLocal: string };
}
interface OvertimeRule {
  thresholdHours: number;
  period: 'SHIFT' | 'DAY' | 'WEEK';
  multiplier: number;
}

// Calendar Event — supertype rộng hơn Shift
interface CalendarEvent {
  id: string;
  type: 'SHIFT' | 'TIME_OFF' | 'PERSONAL' | 'AVAILABILITY_BLOCK';
  source: 'user' | 'partner' | 'colleague';
  status: 'pending' | 'accepted' | 'declined';
  refId: string;              // trỏ tới ShiftOccurrence / TimeOff / v.v.
}

// Import Session — audit + re-import diff
interface ImportSession {
  id: string;
  createdAt: string;
  sourceType: 'IMAGE' | 'PDF' | 'CSV' | 'PASTE_TEXT';
  rawExtraction: unknown;
  candidateShifts: { data: unknown; confidence: 'HIGH' | 'MEDIUM' | 'LOW' }[];
  committedOccurrenceIds: string[];
}
```

---

## 12. Roadmap tinh chỉnh (P0 → P3)

**P0 — Validate Core Loop** (không phụ thuộc platform phức tạp)
1. Today screen (kèm: ca tiếp theo, giờ nghỉ trước ca sau, thu nhập hôm nay/tuần này — thuần hiển thị dữ liệu, không phải AI)
2. Calendar view (week/month)
3. Quick Add (1-tap template)
4. Shift Templates + Pattern builder (4-on/4-off, 2-2-3, DuPont) + preview
5. Time Engine: Civil Time + DST + overnight (với Golden Test Suite chạy trước)
6. Override cơ bản (edit/delete)
7. Offline-first
8. Basic notifications (shift bắt đầu)
9. Paste text + CSV import (không OCR)
10. Multi-job cơ bản (mỗi job có template riêng)
11. .ics export (offline)

**P1 — Differentiation & Conversion**
- Image/PDF OCR import + Review UI + Confidence score (sau spike-test)
- ImportSession + Re-import "What changed?"
- Pattern auto-detection từ lịch import
- Pay Rule Engine (pluggable differentials) + Income breakdown dashboard
- Availability Finder
- Partner/Family overlay (read-only share link, Privacy mode: Busy/Free/Recovery)
- Widgets
- Cloud backup (optional, E2E encrypted)

**P2 — Moat & Stickiness**
- Shift change detection (employer đổi lịch → cảnh báo ảnh hưởng availability/thu nhập)
- Wellness nhẹ, rule-based (cảnh báo chuỗi ca dài, recovery window sau night shift, thống kê giờ làm/nghỉ)
- Colleague sharing (read-only + "open to swap", không approval flow)
- Dynamic Webcal (server + token + revoke)
- Advanced override (split/swap UI mượt hơn)
- Partner reverse-sharing (đối tác đề xuất sự kiện, pending/accepted)

**P3 — Ngoài phạm vi**
- Health AI (circadian, nutrition, workout, medical risk)
- B2B / Team management (duyệt nghỉ, admin, báo cáo)

---

## 13. Kiến trúc thư mục đề xuất cho `plan2`

```
lib/
├── core/                    ← KHÔNG phụ thuộc UI, bảo vệ tuyệt đối
│   ├── time/                (Civil Time + DST + Instant)
│   ├── pattern/              (Pattern → Occurrence → Override + versioning)
│   ├── recurrence/
│   ├── money/                (PayRule versioned + Breakdown)
│   └── notifications/
├── domain/
│   ├── jobs/  shifts/  patterns/  events/  leave/  pay/  sharing/
├── data/
│   ├── database/  repositories/  migrations/
├── features/
│   ├── today/  calendar/  add_shift/  import/  income/  availability/  settings/
└── platform/
    ├── notifications/  widgets/  share/  calendar/
```

Ba module bảo vệ tuyệt đối khỏi thay đổi tùy tiện của AI agents: **`core/time` → `core/pattern` → `core/money`**. Nếu ba phần này đúng, phần UI/mobile còn lại tương đối thẳng. Nếu sai, dù UI đẹp đến đâu ShiftEase vẫn là app lịch ca không đáng tin — đúng điểm chết của hầu hết đối thủ hiện tại.

---

## 14. Hook Marketing (giữ nguyên, đã đồng thuận 5/5 review)

> **"Screenshot your hospital roster. ShiftEase does the rest."**
> **"Know when you're working, when you're free, and what you'll earn."**
> **"Your shifts. Your life."**

---

## 15. Bảng tổng hợp 8 quyết định đã khóa (D1–D8)

| # | Quyết định | Chốt |
|---|---|---|
| D1 | Pattern mutation/versioning | Versioned bằng `effective_from`/`effective_until`; không mutate pattern cũ |
| D2 | Occurrence override | `Override` object với `operation`: CREATE/UPDATE/DELETE/REPLACE/SPLIT/SWAP |
| D3 | Recurrence basis | **Local Civil Time** (wall-clock) |
| D4 | DST non-existent/ambiguous | Không tự quyết; hiện dialog xác nhận |
| D5 | Pay semantics trong Template | **KHÔNG** — ShiftTemplate chỉ chứa thời gian/UI |
| D6 | PayRule versioning | Historical earnings là snapshot bất biến, không bị rewrite |
| D7 | Import safety | Bắt buộc User Review; không auto-commit; có ImportSession để audit |
| D8 | Webcal | `.ics` offline export (P0) tách biệt Dynamic Webcal server+token (P1+) |

---

## 16. Hành động tiếp theo

`plan2` viết chi tiết kỹ thuật dựa trên toàn bộ khung này, gồm 8 phần:

1. Kiến trúc tổng thể + Architectural Invariants (đặt lên đầu)
2. Data model chi tiết (ER diagram) — bao gồm `ImportSession`, `VersionedEntity`, `Override`
3. Quy trình xử lý Import: parse → confidence → review → commit + lưu lịch sử
4. Quy trình Pattern/Override: tạo, sửa, xóa, version hóa
5. Pay Engine chi tiết: differential pluggable, breakdown, versioning
6. Security & Privacy Model: mã hóa, token, granular sharing
7. Testing Strategy: Golden Test Suite + property tests + CI integration
8. Milestones & metrics (retention, conversion, số lượt import thành công)

Sau khi `plan2` hoàn thành → review lại → viết Implementation Spec + Golden Tests → mới giao cho AI coding agents, bắt đầu từ `core/time`.