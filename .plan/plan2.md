# ShiftEase — Kỹ thuật chi tiết (plan2)

> Nguồn sự thật: `plan1_final_v2.md` (mục 16).
> Tài liệu này **chi tiết hóa** quyết định D1–D8, Invariants, và Schema đã khóa ở plan1_final_v2.
> **Không được phép sửa/nới lỏng** bất kỳ Architectural Invariant nào trong tài liệu này.
>
> **Changelog (so với bản trước):**
> - DST-001/DST-002: Sửa shiftDate + tính lại utcStart/utcEnd bằng Intl API (lỗi ngày sai)
> - DST-005: Thiết kế lại case (22:00→06:00 thực sự cắt ngang fall-back) + tính lại UTC
> - DST-003: Sửa error type từ AMBIGUOUS_LOCAL_TIME sang NONEXISTENT_LOCAL_TIME
> - Mục 5.2 + 5.4: Sửa overtime double-counting, chọn Cách B (Regular + OT tách bạch)
> - Mục 2.1: Bổ sung CalendarEvent subtypes (TimeOff, PersonalEvent, AvailabilityBlock)
> - Mục 5.6: Thêm PayRuleTemplate + seed data
> - Mục 7.1: Bổ sung money_engine_cases.json golden test cases
> - Mục 8.1: Thêm M4.5 OCR Spike Test milestone
> - Toàn văn: Khôi phục dấu tiếng Việt

---

## Mục lục

1. [Kiến trúc tổng thể & Architectural Invariants](#1-kiến-trúc-tổng-thể--architectural-invariants)
2. [Data Model chi tiết (ER + VersionedEntity)](#2-data-model-chi-tiết)
3. [Quy trình xử lý Import](#3-quy-trình-xử-lý-import)
4. [Quy trình Pattern / Override](#4-quy-trình-pattern--override)
5. [Pay Engine chi tiết](#5-pay-engine-chi-tiết)
6. [Security & Privacy Model](#6-security--privacy-model)
7. [Testing Strategy](#7-testing-strategy)
8. [Milestones & Metrics](#8-milestones--metrics)

---

## 1. Kiến trúc tổng thể & Architectural Invariants

### 1.1 Kiến trúc tổng thể

```
┌─────────────────────────────────────────────────────────┐
│                      platform/                          │
│  notifications/  widgets/  share/  calendar/            │
├─────────────────────────────────────────────────────────┤
│                      features/                          │
│  today/  calendar/  add_shift/  import/  income/        │
│  availability/  settings/                               │
├─────────────────────────────────────────────────────────┤
│                       domain/                           │
│  jobs/  shifts/  patterns/  events/  leave/             │
│  pay/  sharing/                                         │
├─────────────────────────────────────────────────────────┤
│                        data/                            │
│  database/  repositories/  migrations/                  │
├─────────────────────────────────────────────────────────┤
│                        core/     ← KHÔNG phụ thuộc UI   │
│  time/  pattern/  recurrence/  money/  notifications/   │
└─────────────────────────────────────────────────────────┘
```

**Nguyên tắc dependency:**
- `core/` không import bất kỳ module nào ở `domain/`, `features/`, `platform/`, `data/`.
- `domain/` chỉ import `core/` và `data/`.
- `features/` có thể import `domain/`, `core/`, `data/`.
- `platform/` có thể import mọi thứ nhưng là lớp ngoài cùng.

**Ba module bảo vệ tuyệt đối:**
```
core/time    →  core/pattern  →  core/money
```
Sai bất kỳ module nào trong ba module này = app không đáng tin = mất lợi thế cạnh tranh duy nhất.

### 1.2 Architectural Invariants

> **Copy nguyên từ plan1_final_v2.md mục 10. Không được phép sửa/nới lỏng.**

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

### 1.3 NEVER List

> **Copy nguyên từ plan1_final_v2.md. Không được phép sửa/nới lỏng.**

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

### 1.4 Correctness Contract

> Với cùng input hợp lệ + cùng timezone database version + cùng pay rule version → kết quả phải deterministic.
> Không được phép silent đưa ra kết quả khi input/rule không đủ để tính — phải báo rõ "Unable to calculate accurately" kèm lý do.

---

## 2. Data Model chi tiết

### 2.1 Entity Relationship Diagram

```
                    ┌──────────────┐
                    │     Job      │
                    │──────────────│
                    │ id (PK)      │
                    │ name         │
                    │ defaultTz    │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────────┐
              │            │                │
              ▼            ▼                ▼
     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
     │ShiftTemplate │ │   PayRule    │ │ShiftPattern  │
     │──────────────│ │──────────────│ │──────────────│
     │ id (PK)      │ │ id (PK)      │ │ id (PK)      │
     │ jobId (FK)   │ │ jobId (FK)   │ │ jobId (FK)   │
     │ name         │ │ effectiveFrom│ │ name         │
     │ code         │ │ effectiveUntil│ │ type         │
     │ color        │ │ baseHourlyRate│ │ cycleLength  │
     │ startTime    │ └──────┬───────┘ │ sequence[]   │
     │ endTime      │        │         │ anchorDate   │
     │ breakMinutes │        ▼         │ effectiveFrom│
     └──────┬───────┘ ┌──────────────┐ │ effectiveUntil│
            │         │PayDifferential│ └──────┬───────┘
            │         │──────────────│        │
            │         │ id (PK)      │        │
            │         │ payRuleId(FK)│        ▼
            │         │ type         │ ┌────────────────┐
            │         │ calc{mode,val}│ │ShiftOccurrence │
            │         │ appliesTo    │ │────────────────│
            │         │ window?      │ │ id (PK)        │
            │         └──────────────┘ │ patternId (FK) │
            │                          │ shiftDate      │
            │         ┌──────────────┐ │ templateId(FK) │
            │         │ OvertimeRule │ │ startUtc       │
            │         │──────────────│ │ endUtc         │
            │         │ payRuleId(FK)│ │ timezone       │
            │         │ thresholdHrs │ │ payEstimate?   │
            │         │ period       │ └──────┬─────────┘
            │         │ multiplier   │        │
            │         └──────────────┘        ▼
            │                        ┌────────────────┐
            │                        │    Override     │
            │                        │────────────────│
            │                        │ id (PK)        │
            │                        │ occurrenceId(FK)│
            │                        │ operation      │
            │                        │ payload        │
            │                        │ swapWithId?    │
            │                        │ createdAt      │
            │                        │ reason?        │
            │                        └────────────────┘
            │
            ▼
     ┌──────────────────┐
     │  CalendarEvent   │  ← supertype
     │──────────────────│
     │ id (PK)          │
     │ type             │
     │ source           │
     │ status           │
     │ refId            │
     └────────┬─────────┘
              │
     ┌────────┼──────────────────────────────┐
     │        │              │               │
     ▼        ▼              ▼               ▼
┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌────────────────────┐
│ShiftOccur│ │ TimeOff  │ │PersonalEvent │ │ AvailabilityBlock  │
│ence      │ │──────────│ │──────────────│ │────────────────────│
│(refId)   │ │ id (PK)  │ │ id (PK)      │ │ id (PK)            │
│          │ │ calEvId  │ │ calEvId      │ │ calEvId            │
│          │ │ type     │ │ title        │ │ status             │
│          │ │ PTO/Sick/│ │ startTime    │ │  (FREE/BUSY/       │
│          │ │ Holiday  │ │ endTime      │ │   RECOVERY)        │
│          │ │ startDate│ │ location?    │ │ startTime          │
│          │ │ endDate? │ │ recurrence?  │ │ endTime            │
│          │ │ halfDay? │ └──────────────┘ └────────────────────┘
│          │ └──────────┘
└──────────┘

     ┌──────────────────┐     ┌──────────────────┐
     │  ImportSession   │────▶│CandidateShift[]  │
     │──────────────────│     │──────────────────│
     │ id (PK)          │     │ data             │
     │ createdAt        │     │ confidence       │
     │ sourceType       │     └──────────────────┘
     │ rawExtraction    │
     │ committedOccurIds│
     └──────────────────┘
```

#### CalendarEvent Subtypes (bổ sung từ plan1_final_v2 mục 5)

```typescript
// Supertype
interface CalendarEvent {
  id: string;
  type: 'SHIFT' | 'TIME_OFF' | 'PERSONAL' | 'AVAILABILITY_BLOCK';
  source: 'user' | 'partner' | 'colleague';
  status: 'pending' | 'accepted' | 'declined';
  refId: string;  // trỏ tới ShiftOccurrence / TimeOff / PersonalEvent / AvailabilityBlock
}

// Ca làm việc — đã định nghĩa ở ShiftOccurrence
// (refId trỏ tới ShiftOccurrence.id)

// Nghỉ phép / PTO / Sick / Holiday
interface TimeOff {
  id: string;
  calendarEventId: string;  // FK -> CalendarEvent
  type: 'PTO' | 'SICK' | 'HOLIDAY' | 'UNPAID' | 'PERSONAL_LEAVE';
  startDate: string;        // ISO date
  endDate: string | null;   // null = 1 ngày, có giá trị = nhiều ngày
  halfDay: 'NONE' | 'AM' | 'PM';
  notes?: string;
}

// Sự kiện cá nhân (không liên quan công việc)
interface PersonalEvent {
  id: string;
  calendarEventId: string;  // FK -> CalendarEvent
  title: string;
  startTime: string;        // ISO datetime
  endTime: string;          // ISO datetime
  location?: string;
  recurrence?: {
    type: 'DAILY' | 'WEEKLY' | 'MONTHLY';
    interval: number;
    endDate?: string;
  };
}

// Khối thời gian rảnh/bận (dùng cho Availability Finder)
interface AvailabilityBlock {
  id: string;
  calendarEventId: string;  // FK -> CalendarEvent
  status: 'FREE' | 'BUSY' | 'RECOVERY';
  startTime: string;        // ISO datetime
  endTime: string;          // ISO datetime
}
```

### 2.2 VersionedEntity Pattern

Ba entity chung pattern versioning: `ShiftPattern`, `PayRule`, và (tương lai) `ShiftTemplate` nếu thay đổi thuộc tính cơ bản:

```typescript
interface VersionedEntity {
  effectiveFrom: string;   // ISO date, inclusive
  effectiveUntil: string | null;  // null = đang active
}
```

**Nguyên tắc versioning:**
1. Khi tạo bản mới, set `effectiveUntil` trên bản cũ = ngày trước `effectiveFrom` của bản mới.
2. **Không bao giờ** mutate bản cũ — luôn tạo bản mới.
3. Query version tại thời điểm T: `effectiveFrom <= T && (effectiveUntil is null || effectiveUntil >= T)`.

**Ví dụ:**
```
ShiftPattern v1: effectiveFrom=2026-01-01, effectiveUntil=2026-09-30
ShiftPattern v2: effectiveFrom=2026-10-01, effectiveUntil=null
```

### 2.3 ImportSession & CandidateShift

`ImportSession` lưu toàn bộ lịch sử một lần import, để:
- **Audit**: user có thể xem lại nguồn gốc bất kỳ ca nào.
- **Re-import diff**: khi employer gửi roster mới, app so sánh `rawExtraction` cũ vs mới → hiển thị "What changed?".

```typescript
interface ImportSession {
  id: string;
  createdAt: string;              // ISO datetime
  sourceType: 'IMAGE' | 'PDF' | 'CSV' | 'PASTE_TEXT';
  rawExtraction: unknown;         // dữ liệu thô từ parser
  candidateShifts: CandidateShift[];
  committedOccurrenceIds: string[];  // IDs đã commit vào calendar
}

interface CandidateShift {
  data: {
    date: string;
    templateId: string | null;
    startTime: string;
    endTime: string;
    shiftType: string;           // "Day", "Night", "Off", "?"
  };
  confidence: 'HIGH' | 'MEDIUM' | 'LOW';
  reviewStatus: 'PENDING' | 'APPROVED' | 'REJECTED' | 'MODIFIED';
}
```

### 2.4 Override & OverrideOperation

```typescript
type OverrideOperation = 'CREATE' | 'UPDATE' | 'DELETE' | 'REPLACE' | 'SPLIT' | 'SWAP';

interface Override {
  id: string;
  occurrenceId: string;          // occurrence gốc bị ảnh hưởng
  operation: OverrideOperation;
  payload: OverridePayload;      // dữ liệu cụ thể theo operation
  swapWithOccurrenceId?: string; // chỉ dùng khi operation = SWAP
  createdAt: string;
  reason?: 'SWAP' | 'OVERTIME' | 'LEAVE' | 'CUSTOM';
}
```

**Payload theo từng operation (xem chi tiết ở Mục 4).**

---

## 3. Quy trình xử lý Import

### 3.1 State Machine

```
                    ┌─────────────┐
                    │  IDLE       │
                    └──────┬──────┘
                           │ User chọn file/paste text
                           ▼
                    ┌─────────────┐
                    │  PARSING    │
                    └──────┬──────┘
                           │ Parser hoàn thành
                     ┌─────┴──────┐
                     │            │
                Parse OK     Parse Fail
                     │            │
                     ▼            ▼
              ┌────────────┐ ┌────────────┐
              │ EXTRACTED  │ │   ERROR    │
              │ (candidates│ │ (hiện lỗi │
              │  generated)│ │  cho user) │
              └──────┬─────┘ └────────────┘
                     │                    │
                     │ User review        │ User sửa lại input
                     ▼                    │
              ┌────────────┐              │
              │  REVIEWING │◄─────────────┘
              │  (per-shift│
              │  approve/  │
              │  reject/   │
              │  modify)   │
              └──────┬─────┘
                     │ User xác nhận (Commit)
                     ▼
              ┌────────────┐
              │  COMMITTED │
              │  (creates  │
              │  ShiftOccur│
              │  ences +   │
              │  Calendar  │
              │  Events)   │
              └────────────┘
```

### 3.2 Pipeline chi tiết

#### Bước 1: Document Parser

Tùy `sourceType`, chọn parser phù hợp:

| SourceType | Parser | Output |
|---|---|---|
| `PASTE_TEXT` | Regex + heuristics | Raw schedule entries |
| `CSV` | Column mapping UI → parser | Raw schedule entries |
| `IMAGE` | OCR (Tesseract/PaddleOCR) | Text → regex parser |
| `PDF` | PDF text extraction → regex | Text → regex parser |

#### Bước 2: Schedule Interpretation

```
Raw entries → Date resolution → Shift type matching → Template matching
```

- **Date resolution**: Parse date strings ("Sep 3", "03/09", "Monday") → ISO date (`2026-09-03`)
- **Shift type matching**: So sánh startTime/endTime với ShiftTemplate có sẵn → gợi ý template phù hợp
- **Confidence scoring**: Dựa vào độ rõ ràng của input

**Confidence Scoring Algorithm:**

| Factor | HIGH | MEDIUM | LOW |
|---|---|---|---|
| Date format | ISO hoặc rõ ràng | Mờ ("Mon", "Day 3") | Không xác định được |
| Time format | HH:MM rõ ràng | Chỉ có type ("Night") | Không có thời gian |
| Template match | 1 template khớp rõ | Nhiều template gần giống | Không match template nào |
| Shift type | "Day", "Night", "OFF" rõ ràng | Viết tắt không chuẩn | Không xác định |

#### Bước 3: User Review UI

Mỗi `CandidateShift` hiển thị:
```
┌─────────────────────────────────────────────┐
│ Sep 03, 2026 — Night 19:00–07:00          │
│ Template: Night Shift (Hospital A)         │
│ Confidence: ████████░░ Medium              │
│                                             │
│ [✓ Accept]  [✎ Edit]  [✗ Reject]          │
└─────────────────────────────────────────────┘
```

- User có thể sửa ngày, giờ, template trước khi accept.
- User có thể reject (xóa) candidate.
- Bulk actions: "Accept All High", "Review Remaining".

#### Bước 4: Commit to Calendar

```
For each APPROVED CandidateShift:
  1. Resolve UTC instants (startUtc, endUtc) từ local time + timezone
  2. Create ShiftOccurrence
  3. Create CalendarEvent (type=SHIFT, source=user, status=accepted)
  4. Add occurrenceId to ImportSession.committedOccurrenceIds
```

**Invariant check tại commit:**
- INVARIANT-002: Duration tính từ UTC instants ✓
- INVARIANT-004: Chỉ commit khi user explicit confirm ✓
- INVARIANT-007: timezone giữ nguyên từ thời điểm tạo ✓

### 3.3 ImportSession Audit

```typescript
// Query: "Tại sao ca Sep 03 lại là Night?"
const session = await importRepo.findById(occurrence.importSessionId);
const candidate = session.candidateShifts.find(c =>
  c.data.date === '2026-09-03'
);
// → Hiển thị: raw extraction data + confidence + review status
```

### 3.4 Re-import Diff ("What changed?")

```typescript
function computeImportDiff(
  oldSession: ImportSession,
  newExtraction: RawExtraction
): ImportDiff {
  return {
    added: newEntries.filter(e => !oldEntries.has(e.key)),
    removed: oldEntries.filter(e => !newEntries.has(e.key)),
    modified: newEntries.filter(e =>
      oldEntries.has(e.key) && !shallowEqual(e, oldEntries.get(e.key))
    ),
    impact: {
      totalHoursChanged: calculateDelta(modified),
      incomeImpact: calculateIncomeDelta(modified),
      availabilityImpact: calculateAvailabilityDelta(added, removed),
    }
  };
}
```

---

## 4. Quy trình Pattern / Override

### 4.1 Pattern Creation & Projection

**Input:** Pattern definition + Date range
**Output:** Series of ShiftOccurrence projections

```typescript
function projectOccurrences(
  pattern: ShiftPattern,
  rangeStart: string,   // ISO date
  rangeEnd: string       // ISO date
): ShiftOccurrence[] {
  const occurrences: ShiftOccurrence[] = [];
  let cycleIndex = 0;

  for (let date = rangeStart; date <= rangeEnd; date = addDays(date, 1)) {
    const positionInCycle = cycleIndex % pattern.cycleLengthDays;
    const templateId = pattern.sequence[positionInCycle];

    if (templateId !== null) {
      const template = getTemplate(templateId);
      occurrences.push({
        id: generateId(),
        patternId: pattern.id,
        shiftDate: date,
        templateId,
        startDateTimeUtc: resolveUtcInstant(date, template.startTime, pattern.job.defaultTimezone),
        endDateTimeUtc: resolveUtcInstant(addDaysIfNeeded(date, template), template.endTime, pattern.job.defaultTimezone),
        timezone: pattern.job.defaultTimezone,
      });
    }

    cycleIndex++;
  }

  return occurrences;
}
```

**Property test requirement:**
- `occurrence[n + cycleLengthDays]` phải cùng vị trí pattern như `occurrence[n]`.
- Sửa occurrence #10 không được làm thay đổi occurrence #11 trở đi (INVARIANT-001).

### 4.2 Override Operations chi tiết

#### CREATE
Tạo mới một occurrence không có trong pattern baseline.

```typescript
// Override khi user thêm ca overtime
{
  operation: 'CREATE',
  occurrenceId: null,  // không có gốc
  payload: {
    date: '2026-09-03',
    templateId: 'template-night-id',
    startTime: '19:00',
    endTime: '07:00+1',
  }
}
```

#### UPDATE
Sửa giờ hoặc template của occurrence có sẵn.

```typescript
// User sửa ca từ 07:00–19:00 thành 08:00–20:00
{
  operation: 'UPDATE',
  occurrenceId: 'occ-2026-09-03',
  payload: {
    startTime: '08:00',
    endTime: '20:00',
  }
}
```

#### DELETE
Xóa occurrence (VD: nghỉ phép, ca bị hủy).

```typescript
// User đánh dấu Sep 03 = OFF
{
  operation: 'DELETE',
  occurrenceId: 'occ-2026-09-03',
  payload: null,
}
```

#### REPLACE
Thay template hoàn toàn (VD: Day → Night).

```typescript
// Thay ca Day thành Night
{
  operation: 'REPLACE',
  occurrenceId: 'occ-2026-09-03',
  payload: {
    newTemplateId: 'template-night-id',
    // Giữ nguyên thời gian gốc hoặc override time
    overrideTime: {
      startTime: '19:00',
      endTime: '07:00+1',
    }
  }
}
```

#### SPLIT
Chia một ca thành nhiều phần (VD: ca 07:00–19:00 → 07:00–11:00 + 15:00–19:00).

```typescript
{
  operation: 'SPLIT',
  occurrenceId: 'occ-2026-09-03',
  payload: {
    parts: [
      { startTime: '07:00', endTime: '11:00', templateId: 'template-day-id' },
      { startTime: '15:00', endTime: '19:00', templateId: 'template-day-id' },
    ]
  }
}
```

#### SWAP
Hoán đổi 2 occurrences.

```typescript
// Hoán đổi Sep 03 ↔ Sep 07
{
  operation: 'SWAP',
  occurrenceId: 'occ-2026-09-03',
  swapWithOccurrenceId: 'occ-2026-09-07',
  payload: {
    // Cả hai occurrence giữ nguyên template, chỉ đổi ngày
    // Hoặc nếu template khác nhau → swap cả template
  }
}
```

### 4.3 Effective Schedule Rendering

```
Effective Schedule = Pattern baseline + Overrides
```

```typescript
function renderEffectiveSchedule(
  pattern: ShiftPattern,
  overrides: Override[],
  rangeStart: string,
  rangeEnd: string
): EffectiveOccurrence[] {
  // 1. Project baseline từ pattern
  const baseline = projectOccurrences(pattern, rangeStart, rangeEnd);

  // 2. Apply overrides
  let result = baseline;
  for (const override of overrides) {
    result = applyOverride(result, override);
  }

  // 3. Sort by date
  return result.sort(byDate);
}
```

### 4.4 Pattern Versioning Workflow

```
User: "From Oct 1, chuyển từ 4-on/4-off sang 3-on/4-off"

Step 1: Set effectiveUntil on current pattern = Sep 30
Step 2: Create new pattern version:
  - effectiveFrom = Oct 1
  - effectiveUntil = null
  - sequence = [Day, Day, Day, OFF, OFF, OFF, OFF] (3-on/4-off)
Step 3: Re-project occurrences from Oct 1 onward
Step 4: Existing occurrences (before Oct 1) giữ nguyên — INVARIANT-001
```

---

## 5. Pay Engine chi tiết

### 5.1 PayRule Structure

```typescript
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
  window?: { startLocal: string; endLocal: string };  // nếu appliesTo = HOURS_IN_WINDOW
}

interface OvertimeRule {
  thresholdHours: number;   // VD: 8 (per shift), 40 (per week)
  period: 'SHIFT' | 'DAY' | 'WEEK';
  multiplier: number;       // VD: 1.5
}
```

### 5.2 Pay Breakdown Algorithm (Cách B — Regular + OT tách bạch)

> **Lựa chọn: Cách B (Regular + Overtime tách bạch).**
> Lý do: Hiển thị trên UI rõ ràng hơn — user thấy ngay "X giờ regular + Y giờ OT".
> Cách A (Overtime Premium) dùng khi muốn giữ dòng "Base Pay" là toàn bộ giờ, nhưng khó hiểu hơn cho người dùng.

```typescript
function calculatePayBreakdown(
  occurrence: ShiftOccurrence,
  payRule: PayRule
): PayBreakdown {
  const durationHours = (occurrence.endDateTimeUtc - occurrence.startDateTimeUtc) / 3600;
  const overtimeHours = calculateOvertimeHours(occurrence, payRule);
  const regularHours = Math.max(0, durationHours - overtimeHours);

  let breakdown: PayLine[] = [];

  // 1. Regular Pay (chỉ tính giờ không phải OT)
  breakdown.push({
    label: 'Regular Pay',
    hours: regularHours,
    rate: payRule.baseHourlyRate,
    amount: regularHours * payRule.baseHourlyRate,
  });

  // 2. Differentials (applied to regular hours only, not OT)
  for (const diff of payRule.differentials) {
    if (appliesToOccurrence(diff, occurrence)) {
      const applicableHours = calculateApplicableHours(diff, occurrence, regularHours);
      const diffAmount = diff.calc.mode === 'PERCENT'
        ? applicableHours * payRule.baseHourlyRate * (diff.calc.value / 100)
        : applicableHours * diff.calc.value;

      breakdown.push({
        label: diff.type + ' Differential',
        hours: applicableHours,
        rate: diff.calc.mode === 'PERCENT'
          ? payRule.baseHourlyRate * (diff.calc.value / 100)
          : diff.calc.value,
        amount: diffAmount,
      });
    }
  }

  // 3. Overtime Pay (tính đầy đủ, không cộng thêm vào base)
  if (overtimeHours > 0) {
    const otMultiplier = resolveOvertimeMultiplier(occurrence, payRule.overtimeRules);
    breakdown.push({
      label: 'Overtime Pay',
      hours: overtimeHours,
      rate: payRule.baseHourlyRate * otMultiplier,
      amount: overtimeHours * payRule.baseHourlyRate * otMultiplier,
    });
  }

  const total = breakdown.reduce((sum, line) => sum + line.amount, 0);

  return {
    lines: breakdown,
    total,
    disclaimer: 'Estimate — not official payroll',
  };
}
```

**Ví dụ số (ca 10h, shift threshold 8h, multiplier 1.5):**
```
Regular Pay:  8h x $35.00 = $280.00
Overtime Pay: 2h x $52.50 = $105.00  (35 x 1.5 = 52.50)
                           ----------
Total:                        $385.00
```
Không còn double-count: OT 2h chỉ tính 1 lần, không còn "base $35 + OT $52.50 = $87.50 cho 2h".

### 5.3 Differential Appliance Logic

```typescript
function appliesToOccurrence(
  diff: PayDifferential,
  occurrence: ShiftOccurrence
): boolean {
  switch (diff.type) {
    case 'NIGHT':
      return diff.appliesTo === 'ALL_HOURS_IN_SHIFT'
        ? isNightShift(occurrence)
        : isNightWindowOverlap(occurrence, diff.window!);

    case 'WEEKEND':
      return isWeekend(occurrence.shiftDate);

    case 'HOLIDAY':
      return isHoliday(occurrence.shiftDate, occurrence.timezone);

    case 'HAZARD':
    case 'CALLBACK':
    case 'CUSTOM':
      return occurrenceHasDiffTag(occurrence, diff.type);
  }
}
```

### 5.4 Overtime Calculation (sửa double-count + multi-rule)

> **Vấn đề cũ:** Hàm cũ `return` ngay ở rule đầu tiên trong vòng lặp `overtimeRules`, chỉ áp dụng 1 rule.
> **Vấn đề double-count:** Nếu ca 10h, shift threshold 8h và week threshold 40h, chỉ shift rule được tính, week rule bị bỏ qua.

**Nguyên tắc mới:**
1. Tính OT hours cho từng rule.
2. Lấy **max()** giữa các rule áp dụng được (không cộng dồn — tránh double-count).
3. Nếu trường hợp trùng (cùng 1 khung giờ khớp cả SHIFT và WEEK), lấy cái lớn hơn.

```typescript
function calculateOvertimeHours(
  occurrence: ShiftOccurrence,
  overtimeRules: OvertimeRule[]
): number {
  const shiftHours = (occurrence.endDateTimeUtc - occurrence.startDateTimeUtc) / 3600;

  let maxOvertime = 0;

  for (const rule of overtimeRules) {
    let otHours = 0;

    switch (rule.period) {
      case 'SHIFT':
        otHours = Math.max(0, shiftHours - rule.thresholdHours);
        break;

      case 'DAY': {
        const dayTotal = getDailyTotalHours(occurrence.shiftDate, occurrence.patternId);
        otHours = Math.max(0, dayTotal - rule.thresholdHours);
        break;
      }

      case 'WEEK': {
        const weekTotal = getWeeklyTotalHours(occurrence.shiftDate, occurrence.patternId);
        otHours = Math.max(0, weekTotal - rule.thresholdHours);
        break;
      }
    }

    // Lấy max, không cộng dồn
    maxOvertime = Math.max(maxOvertime, otHours);
  }

  return maxOvertime;
}

/**
 * Tìm multiplier phù hợp nhất khi nhiều rule áp dụng.
 * Nguyên tắc: lấy multiplier của rule cho nhiều OT nhất
 * (vì rule cho nhiều OT thường có multiplier cao hơn — VD: week OT > shift OT).
 */
function resolveOvertimeMultiplier(
  occurrence: ShiftOccurrence,
  overtimeRules: OvertimeRule[]
): number {
  const shiftHours = (occurrence.endDateTimeUtc - occurrence.startDateTimeUtc) / 3600;

  let bestMultiplier = 1.0;
  let maxOt = 0;

  for (const rule of overtimeRules) {
    let otHours = 0;

    switch (rule.period) {
      case 'SHIFT':
        otHours = Math.max(0, shiftHours - rule.thresholdHours);
        break;
      case 'DAY': {
        const dayTotal = getDailyTotalHours(occurrence.shiftDate, occurrence.patternId);
        otHours = Math.max(0, dayTotal - rule.thresholdHours);
        break;
      }
      case 'WEEK': {
        const weekTotal = getWeeklyTotalHours(occurrence.shiftDate, occurrence.patternId);
        otHours = Math.max(0, weekTotal - rule.thresholdHours);
        break;
      }
    }

    if (otHours > maxOt) {
      maxOt = otHours;
      bestMultiplier = rule.multiplier;
    }
  }

  return bestMultiplier;
}
```

**Ví dụ số — California nurse, ca 10h/ngày, tuần đã làm 42h:**
```
Rules:
  - SHIFT: threshold=8h, multiplier=1.5
  - WEEK:  threshold=40h, multiplier=1.5

Tính từng rule:
  - SHIFT rule: 10h - 8h = 2h OT
  - WEEK rule:  42h - 40h = 2h OT (cho ca này)

max(2, 2) = 2h OT
multiplier = 1.5 (cả hai rule đều 1.5)

Kết quả: 8h regular + 2h OT x 1.5
```

**Ví dụ số — ca 12h, tuần đã làm 44h (shift OT < week OT):**
```
Rules:
  - SHIFT: threshold=8h, multiplier=1.5
  - WEEK:  threshold=40h, multiplier=1.5

Tính từng rule:
  - SHIFT rule: 12h - 8h = 4h OT
  - WEEK rule:  44h - 40h = 4h OT

max(4, 4) = 4h OT (trường hợp này bằng nhau)

Kết quả: 8h regular + 4h OT x 1.5
```

**Ví dụ số — California nurse, 2 rules với multiplier khác nhau:**
```
Rules:
  - SHIFT: threshold=8h, multiplier=1.0 (không có shift OT)
  - WEEK:  threshold=40h, multiplier=1.5

Ca 10h, tuần đã làm 42h:
  - SHIFT rule: 10h - 8h = 2h OT, multiplier=1.0
  - WEEK rule:  42h - 40h = 2h OT, multiplier=1.5

max(2, 2) = 2h OT
lấy multiplier của rule cho nhiều OT nhất -> 1.5 (WEEK rule)

Kết quả: 8h regular + 2h OT x 1.5
```

### 5.5 PayRule Snapshot (INVARIANT-006)

```typescript
// Khi tính pay cho một occurrence, luôn dùng PayRule đang active tại thời điểm occurrence
function getActivePayRule(jobId: string, date: string): PayRule | null {
  return payRules.find(rule =>
    rule.jobId === jobId &&
    rule.effectiveFrom <= date &&
    (rule.effectiveUntil === null || rule.effectiveUntil >= date)
  );
}

// Historical earnings là snapshot — KHÔNG BAO GIỜ rewrite
// Khi user thay đổi PayRule sau này, các occurrence cũ giữ nguyên payEstimate
```

### 5.6 PayRuleTemplate (template library theo ngành/quốc gia)

> **Nguồn:** plan1_final_v2 mục 7 — "Cung cấp sẵn template theo ngành + quốc gia để người dùng mới không phải tự cấu hình từ đầu."

```typescript
interface PayRuleTemplate {
  id: string;
  name: string;                    // VD: "US Hospital Nurse — California"
  country: 'US' | 'UK' | 'DE';
  region?: string;                 // VD: "California", "Bavaria"
  description: string;
  defaultBaseRate: number;         // Mức lương mặc định (user có thể thay đổi)
  differentials: PayDifferential[];
  overtimeRules: OvertimeRule[];
}
```

**Seed data cho MVP (Mỹ, Anh, Đức):**

| Template ID | Name | Country | OT Rules | Notes |
|---|---|---|---|---|
| `tpl-us-ca-nurse` | US Hospital Nurse — California | US/CA | SHIFT>8h x1.5, WEEK>40h x1.5 | CA labor law: daily OT >8h |
| `tpl-us-ny-nurse` | US Hospital Nurse — New York | US/NY | WEEK>40h x1.5 | NY: weekly OT only, no daily |
| `tpl-us-tx-nurse` | US Hospital Nurse — Texas | US/TX | WEEK>40h x1.5 | Federal default |
| `tpl-uk-nurse` | UK NHS Nurse | UK | WEEK>39h x1.5 | NHS Agenda for Change |
| `tpl-de-nurse` | German Krankenschwester | DE | DAY>8h x1.5, WEEK>40h x1.5 | German labor law |

**Differentials mặc định:**
- Night differential: +10% (US), +30% (UK NHS night premium), varies (DE)
- Weekend: +15% (US), +0% (UK — đã tính trong night), varies (DE)
- Holiday: +0% (US — often flat bonus, not hourly), varies (UK/DE)

**User flow:**
1. User chọn job, chọn country/region
2. App gợi ý template phù hợp
3. User chọn template → PayRule được tạo với data mặc định
4. User có thể chỉnh sửa bất kỳ field nào sau khi tạo

### 5.7 Weekly Overtime Allocation

> **Bối cảnh:** Rule `WEEK` ở mục 5.4 trả về tổng số giờ OT của cả tuần (`weekTotal - threshold`), nhưng không nói rõ số giờ OT đó được **gán vào ca nào** trong tuần để tính `PayBreakdown` riêng cho từng occurrence. Mục này chốt quy tắc phân bổ (allocation).

**Quy tắc đã chọn: LIFO (Last-In-First-Out) theo thứ tự thời gian trong tuần.**

Sắp xếp các ca trong tuần theo `shiftDate` tăng dần, sau đó gán số giờ OT của cả tuần bắt đầu từ **ca cuối cùng** (gần cuối tuần nhất) lùi dần về trước, cho đến khi hết số giờ OT cần phân bổ.

**Lý do chọn LIFO thay vì chia đều (pro-rata) hoặc FIFO:**

| Phương án | Ưu điểm | Nhược điểm | Kết luận |
|---|---|---|---|
| **Pro-rata** (chia đều theo tỷ lệ giờ mỗi ca) | "Công bằng" về mặt toán học | Phức tạp, khó giải thích cho user ("tại sao ca Thứ 2 cũng có OT?"); không khớp cách tính lương thực tế của hầu hết employer (họ tính OT theo thứ tự thời gian, không chia ngược) | Loại |
| **FIFO** (gán OT vào ca đầu tuần) | Đơn giản tương đương LIFO | Sai về mặt nghiệp vụ: tại thời điểm kết thúc ca đầu tuần, người lao động **chưa vượt threshold** nên về mặt thời gian thực tế không thể là OT — OT chỉ "xuất hiện" khi tổng giờ tuần vượt ngưỡng, tức là tại (các) ca gần cuối tuần | Loại |
| **LIFO** (gán OT vào ca cuối tuần, lùi dần) | Khớp với cách diễn giải tự nhiên "giờ thứ 41 trở đi là OT"; khớp cách nhiều hệ thống payroll thực tế tính (chronological cumulative); dễ giải thích cho user bằng UI ("ca cuối tuần của bạn có giờ OT vì tổng tuần đã vượt 40h tại điểm đó") | Cần đủ dữ liệu cả tuần trước khi tính (không thể tính pay estimate chính xác cho 1 ca riêng lẻ giữa tuần nếu các ca sau chưa xác định — xem ghi chú “Estimate tạm thời” bên dưới) | **Chọn** |

**Thuật toán (pseudo-code):**

```typescript
function allocateWeeklyOvertime(
  shiftsInWeek: ShiftOccurrence[],   // đã có shiftHours từng ca
  weeklyOvertimeHours: number        // = max(0, weeklyTotalHours - threshold), từ mục 5.4
): Map<occurrenceId, { regularHours: number; overtimeHours: number }> {
  // 1. Sắp xếp ca theo thời gian THỰC DIỄN (shiftDate/startDateTimeUtc), tăng dần
  const sorted = shiftsInWeek.sort(byChronologicalOrder);

  const allocation = new Map();
  let remainingOt = weeklyOvertimeHours;

  // 2. Duyệt NGƯỢC từ ca cuối tuần về ca đầu tuần (LIFO)
  for (let i = sorted.length - 1; i >= 0 && remainingOt > 0; i--) {
    const shift = sorted[i];
    // 3. Ca hiện tại hấp thụ tối đa min(giờ của ca, OT còn lại cần phân bổ)
    const otForThisShift = Math.min(shift.shiftHours, remainingOt);

    allocation.set(shift.id, {
      regularHours: shift.shiftHours - otForThisShift,
      overtimeHours: otForThisShift,
    });

    remainingOt -= otForThisShift;
    // 4. Dừng khi remainingOt === 0 (giờ vòng for đã tự check ở điều kiện)
  }

  // 5. Các ca chưa được duyệt tới (nằm trước điểm hết OT) là toàn bộ regular
  for (const shift of sorted) {
    if (!allocation.has(shift.id)) {
      allocation.set(shift.id, { regularHours: shift.shiftHours, overtimeHours: 0 });
    }
  }

  return allocation;
}
```

**Edge case — ca cuối không đủ giờ hấp thụ hết OT (tràn sang ca trước):**

Nếu `weeklyOvertimeHours` lớn hơn số giờ của riêng ca cuối tuần (VD: ca cuối chỉ 4h nhưng cần phân bổ 6h OT), thuật toán ở trên **tự động xử lý đúng** nhờ vào `Math.min(shift.shiftHours, remainingOt)` kết hợp vòng lặp lùi dần:
- Ca cuối (4h): hấp thụ hết 4h OT → `regularHours=0, overtimeHours=4`. `remainingOt` còn lại 2h.
- Ca kế trước đó: tiếp tục hấp thụ 2h OT còn lại (nếu đủ giờ), phần còn lại của ca đó là regular.
- Cứ thế tràn tiếp về các ca trước nữa nếu vẫn còn `remainingOt > 0`, cho đến khi hết OT hoặc hết ca trong tuần (trường hợp hết ca mà vẫn còn `remainingOt > 0` không thể xảy ra về mặt toán học, vì `weeklyOvertimeHours ≤ weeklyTotalHours ≤` tổng giờ tất cả ca trong tuần).

**Estimate tạm thời khi tuần chưa kết thúc:**
Vì allocation phụ thuộc vào tổng giờ **cả tuần**, `payEstimate` của một ca giữa tuần có thể thay đổi khi các ca sau được thêm/sửa. App phải hiển thị rõ nhãn **"Estimate — tính lại khi tuần đầy đủ"** cho các ca chưa kết thúc tuần, không coi đây là vi phạm INVARIANT-006 (INVARIANT-006 chỉ áp dụng cho snapshot sau khi đã chốt — tức là chu kỳ pay đã đóng).

**Tham chiếu golden test:** Xem `PAY-014` trong `money_engine_cases.json` — 3 ca x 14h = 42h/tuần, threshold 40h → 2h OT, LIFO gán toàn bộ 2h OT vào ca cuối tuần (`shift-fri`: 12h regular + 2h OT), hai ca đầu tuần (`shift-mon`, `shift-wed`) giữ nguyên 14h regular.

---

## 6. Security & Privacy Model

### 6.1 Data Encryption

| Layer | Encryption | Notes |
|---|---|---|
| Local storage | SQLite encryption (SQLCipher) | INVARIANT-008: offline-first |
| Cloud sync (optional) | AES-256-GCM | End-to-end encrypted |
| Network transport | TLS 1.3 | Standard |
| Backup export | AES-256-GCM + password | User-controlled |

### 6.2 Token Management (Dynamic Webcal — P1+)

```typescript
interface WebcalToken {
  id: string;
  userId: string;
  token: string;           // random-generated, 64 chars
  expiresAt: string;       // ISO datetime
  revokedAt: string | null;
  permissions: 'FULL' | 'BUSY_ONLY';
}
```

**Revocation/Expiration:**
- Default expiration: 90 ngày
- User có thể revoke bất cứ lúc nào trong Settings
- Khi token expired/revoked → webcal link trả về HTTP 410 Gone

### 6.3 Granular Sharing

| Mode | Nội dung chia sẻ | Use case |
|---|---|---|
| `FULL` | Ca làm + giờ + loại ca | Gia đình, quản lý trực tiếp |
| `BUSY_ONLY` | Chỉ occupied/free blocks, không chi tiết | Colleague, availability |
| `RECOVERY` | Ca + recovery windows sau night shift | Gia đình (hiểu khi nào cần nghỉ) |

**Sharing flow:**
1. User chọn chế độ sharing
2. Tạo share link (anonymous UUID)
3. Người nhận truy cập link → chỉ thấy nội dung theo chế độ đã chọn
4. User có thể revoke link bất cứ lúc nào

---

## 7. Testing Strategy

### 7.1 Golden Test Suite cho Time Engine

File `time_engine_cases.json` chứa các test cases bắt buộc.

**Giá trị UTC được tính bởi `scripts/verify_dst.mjs` sử dụng `Intl.DateTimeFormat` API.**

```json
{
  "metadata": {
    "version": "1.2.0",
    "description": "Golden test cases for ShiftEase Time Engine",
    "required_invariants": ["INVARIANT-002", "INVARIANT-003", "INVARIANT-007"],
    "verification": "All UTC values computed by Intl.DateTimeFormat (Node.js)"
  },
  "cases": [
    {
      "id": "DST-001",
      "name": "Night shift crossing spring-forward (US Eastern)",
      "timezone": "America/New_York",
      "shiftDate": "2026-03-07",
      "startTime": "22:00",
      "endTime": "06:00+1",
      "expected": {
        "utcStart": "2026-03-08T03:00:00.000Z",
        "utcEnd": "2026-03-08T10:00:00.000Z",
        "durationHours": 7.0,
        "startOffset": -5,
        "endOffset": -4,
        "note": "Spring-forward at 2:00 AM Mar 8: EST(UTC-5) -> EDT(UTC-4). 8h wall-clock = 7h actual."
      }
    },
    {
      "id": "DST-002",
      "name": "Night shift crossing fall-back (US Eastern)",
      "timezone": "America/New_York",
      "shiftDate": "2026-10-31",
      "startTime": "22:00",
      "endTime": "06:00+1",
      "expected": {
        "utcStart": "2026-11-01T02:00:00.000Z",
        "utcEnd": "2026-11-01T11:00:00.000Z",
        "durationHours": 9.0,
        "startOffset": -4,
        "endOffset": -5,
        "note": "Fall-back at 2:00 AM Nov 1: EDT(UTC-4) -> EST(UTC-5). 8h wall-clock = 9h actual."
      }
    },
    {
      "id": "DST-003",
      "name": "Shift starting in non-existent hour (spring-forward)",
      "timezone": "America/New_York",
      "shiftDate": "2026-03-08",
      "startTime": "02:30",
      "endTime": "10:30",
      "expected": {
        "error": "NONEXISTENT_LOCAL_TIME",
        "note": "2:30 AM does not exist on Mar 8 (clocks jump 2:00->3:00). Prompt user."
      }
    },
    {
      "id": "DST-004",
      "name": "Shift during repeated hour (fall-back)",
      "timezone": "America/New_York",
      "shiftDate": "2026-11-01",
      "startTime": "01:00",
      "endTime": "09:00",
      "expected": {
        "error": "AMBIGUOUS_LOCAL_TIME",
        "options": [
          { "label": "EDT", "utc": "2026-11-01T05:00:00.000Z", "offset": -4 },
          { "label": "EST", "utc": "2026-11-01T06:00:00.000Z", "offset": -5 }
        ],
        "note": "1:00 AM occurs twice on Nov 1 (clocks fall 2:00->1:00). Prompt user to choose EDT or EST."
      }
    },
    {
      "id": "DST-005",
      "name": "EU night shift crossing fall-back (22:00->06:00)",
      "timezone": "Europe/Berlin",
      "shiftDate": "2026-10-24",
      "startTime": "22:00",
      "endTime": "06:00+1",
      "expected": {
        "utcStart": "2026-10-24T20:00:00.000Z",
        "utcEnd": "2026-10-25T05:00:00.000Z",
        "durationHours": 9.0,
        "startOffset": 2,
        "endOffset": 1,
        "note": "EU fall-back at 3:00 AM CEST(UTC+2) Oct 25 -> 2:00 AM CET(UTC+1). 8h wall-clock = 9h actual."
      }
    },
    {
      "id": "BORDER-001",
      "name": "Shift crossing month boundary",
      "timezone": "America/New_York",
      "shiftDate": "2026-01-31",
      "startTime": "22:00",
      "endTime": "06:00+1",
      "expected": {
        "utcStart": "2026-02-01T03:00:00.000Z",
        "utcEnd": "2026-02-01T11:00:00.000Z",
        "durationHours": 8.0,
        "note": "Normal overnight, no DST. Both in EST(UTC-5)."
      }
    },
    {
      "id": "BORDER-002",
      "name": "Shift crossing year boundary",
      "timezone": "America/New_York",
      "shiftDate": "2026-12-31",
      "startTime": "22:00",
      "endTime": "06:00+1",
      "expected": {
        "utcStart": "2027-01-01T03:00:00.000Z",
        "utcEnd": "2027-01-01T11:00:00.000Z",
        "durationHours": 8.0,
        "note": "Year boundary, no DST. Both in EST(UTC-5)."
      }
    },
    {
      "id": "TZ-CHANGE-001",
      "name": "User changes device timezone mid-history",
      "timezone_initial": "America/New_York",
      "timezone_new": "America/Los_Angeles",
      "shiftDate": "2026-06-15",
      "note": "Existing occurrence keeps original timezone (INVARIANT-007). New occurrences use new timezone."
    },
    {
      "id": "TZ-CHANGE-002",
      "name": "User travels from US to UK, schedule adjusts",
      "timezone_initial": "America/New_York",
      "timezone_new": "Europe/London",
      "note": "Recurrence basis stays local civil time (INVARIANT-003)"
    },
    {
      "id": "STANDARD-001",
      "name": "Regular day shift (no DST)",
      "timezone": "America/New_York",
      "shiftDate": "2026-06-15",
      "startTime": "07:00",
      "endTime": "19:00",
      "expected": {
        "utcStart": "2026-06-15T11:00:00.000Z",
        "utcEnd": "2026-06-15T23:00:00.000Z",
        "durationHours": 12.0,
        "offset": -4,
        "note": "Both in EDT(UTC-4)."
      }
    },
    {
      "id": "STANDARD-002",
      "name": "Regular night shift (no DST)",
      "timezone": "America/New_York",
      "shiftDate": "2026-06-15",
      "startTime": "19:00",
      "endTime": "07:00+1",
      "expected": {
        "utcStart": "2026-06-15T23:00:00.000Z",
        "utcEnd": "2026-06-16T11:00:00.000Z",
        "durationHours": 12.0,
        "note": "Both in EDT(UTC-4)."
      }
    }
  ]
}
```

### 7.1b Golden Test Suite cho Money Engine

File `money_engine_cases.json` chứa các test cases cho Pay Engine:

```json
{
  "metadata": {
    "version": "1.0.0",
    "description": "Golden test cases for ShiftEase Money Engine (Pay Breakdown)",
    "required_invariants": ["INVARIANT-005", "INVARIANT-006"]
  },
  "cases": [
    {
      "id": "PAY-001",
      "name": "Simple day shift, no differentials, no OT",
      "input": {
        "shiftHours": 12,
        "baseRate": 35.00,
        "differentials": [],
        "overtimeRules": [],
        "dailyHours": 12,
        "weeklyHours": 36
      },
      "expected": {
        "regularPay": 420.00,
        "overtimePay": 0.00,
        "total": 420.00,
        "breakdownLines": 1
      }
    },
    {
      "id": "PAY-002",
      "name": "Night shift with NIGHT differential (percent)",
      "input": {
        "shiftHours": 12,
        "baseRate": 35.00,
        "differentials": [
          { "type": "NIGHT", "calc": { "mode": "PERCENT", "value": 10 }, "appliesTo": "ALL_HOURS_IN_SHIFT" }
        ],
        "overtimeRules": [],
        "isNightShift": true,
        "dailyHours": 12,
        "weeklyHours": 36
      },
      "expected": {
        "regularPay": 420.00,
        "nightDiff": 42.00,
        "overtimePay": 0.00,
        "total": 462.00,
        "breakdownLines": 2
      }
    },
    {
      "id": "PAY-003",
      "name": "Night + Weekend differentials",
      "input": {
        "shiftHours": 12,
        "baseRate": 35.00,
        "differentials": [
          { "type": "NIGHT", "calc": { "mode": "PERCENT", "value": 10 }, "appliesTo": "ALL_HOURS_IN_SHIFT" },
          { "type": "WEEKEND", "calc": { "mode": "FLAT", "value": 3.00 }, "appliesTo": "ALL_HOURS_IN_SHIFT" }
        ],
        "overtimeRules": [],
        "isNightShift": true,
        "isWeekend": true,
        "dailyHours": 12,
        "weeklyHours": 36
      },
      "expected": {
        "regularPay": 420.00,
        "nightDiff": 42.00,
        "weekendDiff": 36.00,
        "overtimePay": 0.00,
        "total": 498.00,
        "breakdownLines": 3
      }
    },
    {
      "id": "PAY-004",
      "name": "SHIFT overtime only (10h shift, threshold 8h, multiplier 1.5)",
      "input": {
        "shiftHours": 10,
        "baseRate": 35.00,
        "differentials": [],
        "overtimeRules": [
          { "thresholdHours": 8, "period": "SHIFT", "multiplier": 1.5 }
        ],
        "dailyHours": 10,
        "weeklyHours": 30
      },
      "expected": {
        "regularPay": 280.00,
        "overtimeHours": 2,
        "overtimePay": 105.00,
        "total": 385.00,
        "breakdownLines": 2,
        "note": "8h regular x $35 + 2h OT x $52.50"
      }
    },
    {
      "id": "PAY-005",
      "name": "WEEK overtime only (daily < threshold, weekly exceeds)",
      "input": {
        "shiftHours": 10,
        "baseRate": 35.00,
        "differentials": [],
        "overtimeRules": [
          { "thresholdHours": 40, "period": "WEEK", "multiplier": 1.5 }
        ],
        "dailyHours": 10,
        "weeklyHours": 42
      },
      "expected": {
        "regularPay": 350.00,
        "overtimeHours": 2,
        "overtimePay": 105.00,
        "total": 455.00,
        "breakdownLines": 2,
        "note": "10h regular x $35 + 2h OT x $52.50. Week rule: 42h - 40h = 2h OT."
      }
    },
    {
      "id": "PAY-006",
      "name": "Both SHIFT and WEEK rules (max applies)",
      "input": {
        "shiftHours": 10,
        "baseRate": 35.00,
        "differentials": [],
        "overtimeRules": [
          { "thresholdHours": 8, "period": "SHIFT", "multiplier": 1.5 },
          { "thresholdHours": 40, "period": "WEEK", "multiplier": 1.5 }
        ],
        "dailyHours": 10,
        "weeklyHours": 42
      },
      "expected": {
        "regularPay": 280.00,
        "overtimeHours": 2,
        "overtimePay": 105.00,
        "total": 385.00,
        "breakdownLines": 2,
        "note": "SHIFT: 10-8=2h, WEEK: 42-40=2h. max(2,2)=2h OT. No double-count."
      }
    },
    {
      "id": "PAY-007",
      "name": "California nurse: 12h shift, 44h week (week OT > shift OT)",
      "input": {
        "shiftHours": 12,
        "baseRate": 35.00,
        "differentials": [
          { "type": "NIGHT", "calc": { "mode": "PERCENT", "value": 10 }, "appliesTo": "ALL_HOURS_IN_SHIFT" }
        ],
        "overtimeRules": [
          { "thresholdHours": 8, "period": "SHIFT", "multiplier": 1.5 },
          { "thresholdHours": 40, "period": "WEEK", "multiplier": 1.5 }
        ],
        "isNightShift": true,
        "dailyHours": 12,
        "weeklyHours": 44
      },
      "expected": {
        "regularPay": 280.00,
        "nightDiff": 28.00,
        "overtimeHours": 4,
        "overtimePay": 210.00,
        "total": 518.00,
        "breakdownLines": 3,
        "note": "SHIFT: 12-8=4h, WEEK: 44-40=4h. max(4,4)=4h OT. Night diff on regular hours only (8h)."
      }
    },
    {
      "id": "PAY-008",
      "name": "No overtime (shift below all thresholds)",
      "input": {
        "shiftHours": 7,
        "baseRate": 40.00,
        "differentials": [],
        "overtimeRules": [
          { "thresholdHours": 8, "period": "SHIFT", "multiplier": 1.5 },
          { "thresholdHours": 40, "period": "WEEK", "multiplier": 1.5 }
        ],
        "dailyHours": 7,
        "weeklyHours": 28
      },
      "expected": {
        "regularPay": 280.00,
        "overtimeHours": 0,
        "overtimePay": 0.00,
        "total": 280.00,
        "breakdownLines": 1,
        "note": "7h < 8h shift threshold, 28h < 40h week threshold. No OT."
      }
    },
    {
      "id": "PAY-009",
      "name": "HOLIDAY differential (flat rate)",
      "input": {
        "shiftHours": 12,
        "baseRate": 35.00,
        "differentials": [
          { "type": "HOLIDAY", "calc": { "mode": "FLAT", "value": 5.00 }, "appliesTo": "ALL_HOURS_IN_SHIFT" }
        ],
        "overtimeRules": [],
        "isHoliday": true,
        "dailyHours": 12,
        "weeklyHours": 36
      },
      "expected": {
        "regularPay": 420.00,
        "holidayDiff": 60.00,
        "overtimePay": 0.00,
        "total": 480.00,
        "breakdownLines": 2
      }
    }
  ]
}
```

### 7.2 Property Tests cho Pattern Engine

```typescript
// Property 1: Cycle repetition
// occurrence[n + cycleLengthDays] must be same position as occurrence[n]
forAll(patterns, dates, (pattern, baseDate) => {
  const occ1 = projectSingleOccurrence(pattern, baseDate);
  const occ2 = projectSingleOccurrence(pattern, addDays(baseDate, pattern.cycleLengthDays));
  assertEqual(occ1.templateId, occ2.templateId);
});

// Property 2: Override isolation (INVARIANT-001)
// Editing occurrence #N does not affect occurrence #N+1
forAll(patterns, indices, (pattern, editIndex) => {
  const before = projectOccurrences(pattern, range);
  const edited = applyOverride(before, createEditOverride(editIndex));
  // occurrences after editIndex must be unchanged
  for (let i = editIndex + 1; i < before.length; i++) {
    assertEqual(edited[i].templateId, before[i].templateId);
    assertEqual(edited[i].startDateTimeUtc, before[i].startDateTimeUtc);
  }
});

// Property 3: Duration correctness (INVARIANT-002)
forAll(occurrences, (occ) => {
  const duration = occ.endDateTimeUtc - occ.startDateTimeUtc;
  assert(duration >= 0, "Duration must be non-negative");
  assert(duration === expectedDuration(occ.timezone, occ.shiftDate, ...));
});
```

### 7.3 CI Integration

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  core-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: flutter pub get
      - name: Run Golden Tests (Time Engine)
        run: flutter test test/core/time/ --reporter expanded
      - name: Run Golden Tests (Pattern Engine)
        run: flutter test test/core/pattern/ --reporter expanded
      - name: Run Golden Tests (Money Engine)
        run: flutter test test/core/money/ --reporter expanded
      - name: Run Property Tests
        run: flutter test test/core/property/ --reporter expanded
      - name: Verify no INVARIANT violations
        run: dart analyze lib/core/ --fatal-warnings
```

**Gate rule:** PR merge bị block nếu bất kỳ golden test nào fail hoặc có analyzer warning trong `core/`.

---

## 8. Milestones & Metrics

### 8.1 Milestones

| Milestone | Scope | Deliverables | Duration |
|---|---|---|---|
| **M0: Foundation** | Core time + pattern + money | Time Engine, Pattern Engine, Pay Engine + full test suites | 3 weeks |
| **M1: Basic Calendar** | Offline calendar + quick add | Today screen, calendar view, quick add, override (edit/delete) | 2 weeks |
| **M2: Import** | Paste text + CSV import | Import pipeline, review UI, ImportSession audit | 2 weeks |
| **M3: Multi-Job** | Multi-job + pay breakdown | Job management, pay dashboard, income breakdown | 2 weeks |
| **M4: Export & Share** | .ics export + partner sharing | Offline .ics export, busy/free sharing | 1 week |
| **M4.5: OCR Spike Test** | Validate OCR feasibility | Test with 20-30 real rosters, measure % correct dates/shift types/start-end/manual corrections needed. **Gate:** Only proceed to M5 if >=70% of dates and >=60% of shift types are correctly parsed without manual correction. Deliverable: spike-test report with raw numbers. | 1 week |
| **M5: OCR Import** | Image/PDF OCR + confidence (conditional on M4.5) | OCR parser, confidence scoring, re-import diff | 3 weeks |
| **M6: Cloud** | Cloud backup + dynamic webcal | E2E encrypted backup, dynamic webcal (P1) | 2 weeks |

### 8.2 Key Metrics

#### Retention Metrics
| Metric | Target | Measurement |
|---|---|---|
| Day 1 retention | > 60% | Users return after first session |
| Day 7 retention | > 30% | Users active after 7 days |
| Day 30 retention | > 15% | Users active after 30 days |
| Weekly active users | Track trend | Users opening app ≥ 3x/week |

#### Conversion Metrics
| Metric | Target | Measurement |
|---|---|---|
| Free → Pro conversion | > 5% | Users upgrading after trial |
| Lifetime purchase rate | > 3% | Users buying $39.99 lifetime |
| Time to first value | < 2 min | Time from install to first shift added |

#### Import Metrics
| Metric | Target | Measurement |
|---|---|---|
| Import success rate | > 85% | Imports with ≥80% HIGH confidence candidates |
| Manual correction rate | < 15% | Candidates requiring user edit before accept |
| Re-import usage | Track trend | Users using re-import feature |
| Import completion rate | > 70% | Users who complete import after starting |

#### Engagement Metrics
| Metric | Target | Measurement |
|---|---|---|
| Avg. shifts added/week | > 3 | Calendar events created |
| Pay rule configuration | > 40% | Users setting up at least one pay rule |
| Pattern usage | Track trend | Users using pattern builder vs manual add |
| Override frequency | Track trend | Average overrides per user per week |

---

*Document ends. plan2.md v3 is ready for review.*
