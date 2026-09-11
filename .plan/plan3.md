Check code mới /Users/hoang/htdocs_apps/ShiftEase và kết quả mới nhất ghi nhận. xem features.md thống kê các tính năng hiện tại. Bạn có 2 nhiệm vụ: 
- review code xem logic đã đúng chưa, tìm chỗ sai nếu có
- đưa ra hành động tiếp theo.
- gợi ý bổ xung tính năng + UI. mục đích app production ko phải bản nháp.
--------------------
Mình đã check **source hiện tại + `features.md` + `result4_status.txt`**, và đối chiếu lại với những vấn đề mình phát hiện ở vòng trước.

Có một điểm rất quan trọng: **`features.md` hiện mô tả khá tốt trạng thái project, nhưng có vài chỗ đang “đánh dấu ✅ hơi rộng” so với implementation thực tế.** Vì mục tiêu của bạn là **production app**, mình sẽ không coi “test pass” = “logic đúng”.

1\. Verdict hiện tại
--------------------

**Chưa nên chuyển ngay sang `core/money`.**

Mình đánh giá:

| Khu vực | Đánh giá |
| --- | --- |
| Time Engine | 🟡 Khá tốt nhưng còn hardening |
| Pattern Engine | 🟡 Kiến trúc tốt, implementation override chưa production-safe |
| Test strategy | 🟢 Khá tốt |
| Feature completeness | 🔴 Còn rất xa production |
| Data/domain architecture | 🔴 Chưa bắt đầu |
| UI | 🔴 Chưa bắt đầu |
| Production readiness | 🔴 Chưa sẵn sàng |

**Điểm tổng thể hiện tại: ~5.5–6/10**, nhưng không phải vì code core tệ; chủ yếu vì phần application thực tế chưa được xây.

* * *

2\. `features.md`: thống kê hiện tại là hợp lý, nhưng cần chỉnh cách ghi trạng thái
===================================================================================

`features.md` ghi:

> `core/time` ✅ Implement  
> `core/pattern` ✅ Implement

Điều này **chỉ đúng nếu hiểu là “engine skeleton/core implementation đã tồn tại”**.

Nếu dùng `features.md` làm product truth cho AI agent, mình khuyên đổi thành:

    ✅ Implemented & verified
    🟡 Implemented but needs hardening
    🟠 Partially implemented
    ⏳ Designed, not implemented

Vì Pattern hiện tại không nên ghi đơn giản là:

> B5 Override — ✅

Trong chính file đã thừa nhận:

> 5/6 — UPDATE còn lỗi P3

nhưng thực tế **không chỉ UPDATE**.

* * *

3\. Pattern Engine: các lỗi cũ vẫn còn
======================================

Mình vừa đọc lại source hiện tại, và những vấn đề trong `result4_status.txt` **chưa được sửa**.

### 🔴 P1 — CREATE vẫn tạo UTC rỗng

Trong `_applyCreate()`:

dart

    startDateTimeUtc: '',
    endDateTimeUtc: '',
    timezone: '',

Đây là lỗi production nghiêm trọng.

Một `ShiftOccurrence` hợp lệ mà có:

    UTC start = ""
    UTC end   = ""
    timezone  = ""

thì downstream engine không thể tin object này.

Đặc biệt Correctness Contract của ShiftEase nói:

> Không silent đưa ra kết quả khi input/rule không đủ.

Object kiểu này nên **không được phép tồn tại** trong domain.

### Hành động

Không nên chữa bằng:

    // caller sẽ resolve sau

Mà phải thiết kế lại contract.

Tốt hơn:

    Override command
          ↓
    resolve local civil time
          ↓
    validated ShiftOccurrence

**Mọi `ShiftOccurrence` đã tồn tại trong domain phải luôn valid.**

* * *

4\. 🔴 SPLIT cũng còn UTC rỗng
==============================

Hiện tại:

dart

    startDateTimeUtc: '',
    endDateTimeUtc: '',

Tức là:

    07:00–19:00
           ↓ SPLIT
    07:00–11:00
    15:00–19:00

hai occurrence mới không có temporal identity hoàn chỉnh.

Đây là lỗi tương tự CREATE.

* * *

5\. 🔴 UPDATE vẫn silent no-op đối với đổi giờ
==============================================

Hiện tại `_applyUpdate()`:

dart

    return occ.copyWith(
      templateId: payload.templateId,
    );

Trong khi payload có:

    startTime
    endTime

Nếu user:

    07:00 → 09:00

nhưng không đổi template:

→ implementation **không thay đổi giờ**.

Đây là bug rất rõ.

Và nguy hiểm hơn:

> UI có thể báo “Saved successfully”.

Đây là kiểu bug phải loại bỏ hoàn toàn ở production.

* * *

6\. 🔴 REPLACE cũng chưa hoàn thiện
===================================

Comment nói:

dart

    // If overrideTime provided, update times too
    // (UTC resolution handled by caller)

nhưng implementation chỉ:

dart

    templateId: payload.newTemplateId,

Nếu:

    Day → Night

thì template đổi.

Nhưng nếu REPLACE yêu cầu:

    Day 08:00–16:00
    → Night 20:00–08:00

thì `overrideTime` chưa được áp dụng.

Vì vậy `features.md` nên ghi:

> REPLACE: 🟠 partially implemented

* * *

7\. 🔴 `renderEffectiveSchedule()` vẫn silent drop DST-error
============================================================

Đây là bug mình đặc biệt muốn giữ lại trong danh sách P1.

Code:

dart

    final resolved = projectOccurrences(...);
    
    var occurrences = resolved
        .where((r) => r.isSuccess)
        .map((r) => r.occurrence!)
        .toList();

Trong khi `projectOccurrences()` cố tình tạo:

    ResolvedOccurrence(error: ...)

để **không silent drop**.

Nhưng render lại:

    error occurrence
          ↓
    where(isSuccess)
          ↓
    DISCARDED

Tức là:

### Comment:

> NEVER silently drop occurrences

### Runtime:

> `.where((r) => r.isSuccess)`

→ **contradiction trực tiếp.**

* * *

8\. Đây là vấn đề architecture, không chỉ bug
=============================================

Bạn cần quyết định:

### Option A — Effective schedule trả cả error

    EffectiveOccurrence
     ├── success occurrence
     └── unresolved occurrence

UI có thể hiển thị:

> ⚠️ Cannot calculate this shift  
> 02:30 on Mar 8 doesn't exist because DST changes.

Đây là hướng mình khuyến nghị.

### Option B — render trả Result

Ví dụ:

    ScheduleRenderResult
     ├── occurrences
     └── issues

Mình thích **Option B hơn cho production**.

Ví dụ:

    ScheduleRenderResult
    {
        occurrences: [...]
        issues: [
            DST_NONEXISTENT,
            MISSING_TEMPLATE
        ]
    }

Như vậy calendar vẫn render được các ca hợp lệ nhưng **không mất thông tin lỗi**.

* * *

9\. Time Engine: mình vẫn giữ P1 về DST implementation
======================================================

`resolveUtcInstant()` hiện vẫn có:

dart

    final prevHour = ...
    final nextHour = ...

và:

dart

    Duration(hours:
        offset.inHours > alternativeOffset.inHours ? 1 : -1)

Tức là alternative UTC đang được suy ra bằng:

> ±1 hour

Đây là assumption không nên nằm trong một Time Engine production.

Đặc biệt:

    offset.inHours

còn làm mất precision đối với timezone offset dạng:

    +05:30
    +05:45
    +09:30

Trong khi code khác lại có `inMinutes`.

### Khuyến nghị

Không tự tính:

    utc2 = utc1 ± 1h

Mà phải resolve **hai candidate UTC instant thực sự** từ timezone database.

* * *

10\. Time Engine còn thiếu validation boundary
==============================================

Ví dụ:

    25:90
    2026-99-99
    2026-02-31
    abc

hiện có khả năng bị đẩy vào:

    NONEXISTENT_LOCAL_TIME

Nhưng:

> invalid input ≠ nonexistent DST time.

Production UI cần phân biệt:

    INVALID_DATE
    INVALID_TIME
    INVALID_TIMEZONE
    NONEXISTENT_LOCAL_TIME
    AMBIGUOUS_LOCAL_TIME
    END_BEFORE_START

Điều này rất quan trọng cho UX.

* * *

11\. Pattern versioning: cần khóa semantics trước khi build UI
==============================================================

Hiện tại:

dart

    anchorDate: newEffectiveFrom,

Tức:

    effectiveFrom = 2026-10-01
    anchorDate    = 2026-10-01

Điều này có nghĩa pattern mới **reset cycle tại ngày bắt đầu version mới**.

Ví dụ:

    4 ON / 4 OFF

Nếu version cũ đang ở:

    ON ON OFF OFF

và user đổi roster từ ngày X, code hiện tại có thể làm:

    X = sequence[0]

Trong khi user có thể kỳ vọng:

    X tiếp tục cycle position cũ

Đây phải là **explicit product decision**, không để implementation tự quyết.

* * *

12\. SWAP: chưa nên chốt implementation hiện tại
================================================

Hiện tại SWAP làm:

    A gets B:
        date
        template
        UTC
        timezone
    
    B gets A:
        date
        template
        UTC
        timezone

Cách này dễ tạo semantic sai.

Production nên định nghĩa:

> SWAP là swap **schedule intent** hay swap **absolute instant**?

Mình khuyến nghị:

    SWAP
     ↓
    swap local civil schedule
     ↓
    resolve again using destination timezone
     ↓
    new UTC

Không nên đơn giản copy UTC từ A sang B.

* * *

13\. ID strategy cũng cần sửa trước Data layer
==============================================

Hiện tại:

dart

    _generateId(
      pattern.id,
      shiftDate,
      templateId,
    )

ra:

    pattern_2026-09-04_day

Điều này tốt cho baseline deterministic.

Nhưng khi production có:

*   2 shift cùng ngày
    
*   CREATE
    
*   SPLIT
    
*   REPLACE
    
*   import
    
*   duplicate template
    
*   recurring pattern
    
*   override chain
    

thì ID này sẽ không đủ.

Nên tách:

    Occurrence identity

khỏi:

    projection identity

và đặc biệt **không để UI/DB phụ thuộc vào string ID generated từ template/date**.

* * *

14\. Điều mình muốn sửa trong `features.md`
===========================================

Ví dụ hiện tại:

    B5 Override — ✅ (5/6 — UPDATE còn lỗi P3)

nên thành:

    B5 Override — 🟠 Partial
        CREATE     🟠 invalid/incomplete temporal identity
        UPDATE     🔴 time update missing
        DELETE     🟢
        REPLACE    🟠 overrideTime missing
        SPLIT      🔴 UTC unresolved
        SWAP       🟠 semantics need hardening

Tương tự:

    A1-A9

nên có:

    A1-A3 🟢
    A4-A6 🟡
    A7-A9 🟡

cho tới khi Time Engine vượt qua validation + DST edge cases.

* * *

15\. Hành động tiếp theo — mình thay đổi thứ tự so với `result4_status.txt`
===========================================================================

**Không chuyển ngay sang Money Engine.**

Mình đề xuất:

Phase 0 — Core Contract Freeze
------------------------------

### P0.1 — Fix Time Engine

Phải đạt:

    VALID INPUT
        ↓
    local civil
        ↓
    timezone resolver
        ↓
    0 / 1 / 2 valid UTC candidates

Không:

    ±1 hour assumption

và phân biệt rõ error types.

* * *

### P0.2 — Thiết kế lại `ShiftOccurrence`

Mục tiêu:

> **Không tồn tại valid occurrence với empty UTC/timezone.**

Ví dụ conceptual:

    ShiftOccurrence
     ├── id
     ├── patternId?
     ├── shiftDate
     ├── templateId
     ├── localStartTime
     ├── localEndTime
     ├── timezone
     ├── utcStart
     ├── utcEnd
     └── ...

Local civil time phải được lưu nếu nó là source-of-truth của schedule.

* * *

### P0.3 — Thiết kế `Override` thành domain command

Thay vì:

    applyOverride()

đơn thuần manipulate list.

Nên hướng tới:

    Override
        ↓
    validate payload
        ↓
    resolve local time
        ↓
    validate temporal invariants
        ↓
    produce occurrence(s)

* * *

### P0.4 — Fix toàn bộ 6 operations

Acceptance criteria:

| Operation | Requirement |
| --- | --- |
| CREATE | valid UTC + timezone |
| UPDATE | đổi template +/hoặc time |
| DELETE | deterministic |
| REPLACE | template + optional time |
| SPLIT | mỗi part valid UTC |
| SWAP | explicit civil-time semantics |

* * *

### P0.5 — Fix Effective Schedule

Không:

dart

    .where(isSuccess)

rồi vứt error.

Phải trả:

    success occurrences
    +
    render issues

* * *

16\. Sau đó mới làm Money Engine
================================

Khi Pattern/Time đạt:

    100% valid occurrence contract

thì:

    Time
      ↓
    Pattern
      ↓
    Effective Schedule
      ↓
    Money

Money không nên phải xử lý:

    utcStart == ''
    timezone == ''

hoặc tự đoán local time.

* * *

17\. Sau Money mới làm Data/Domain
==================================

Thứ tự production mình đề xuất:

    M0  Core correctness
    │
    ├── Time
    ├── Pattern
    ├── Override
    └── Effective Schedule
    
    M1  Money
    │
    ├── PayRule
    ├── Differential
    ├── OT
    ├── Snapshot
    └── Golden tests
    
    M2  Persistence
    │
    ├── SQLite
    ├── migrations
    ├── repositories
    ├── transaction
    └── backup/restore
    
    M3  Domain
    │
    ├── Job
    ├── Shift
    ├── CalendarEvent
    ├── TimeOff
    └── Availability
    
    M4  Calendar UX
    │
    ├── Today
    ├── Week
    ├── Month
    ├── Add Shift
    ├── Edit
    └── Pattern Builder
    
    M5  Import
    │
    ├── Smart Paste
    ├── CSV
    ├── Review
    ├── confidence
    └── audit
    
    M6  Production hardening
    │
    ├── notifications
    ├── analytics
    ├── crash reporting
    ├── backup
    ├── migration
    └── security
    
    M7  Sharing / Cloud

* * *

18\. Các tính năng mình khuyên bổ sung cho production
=====================================================

Không phải tất cả đều cần MVP, nhưng đây là những thứ **nên cân nhắc**, vì mục tiêu của bạn là app thực tế chứ không phải demo.

A. Calendar UX
--------------

### ⭐ “Next Shift” cực lớn trên Today

Ví dụ:

    NEXT SHIFT
    
    Tomorrow
    Night Shift
    
    19:00 → 07:00
    18h 42m from now
    
    Mercy General

Một nút:

**View shift**

* * *

### ⭐ Countdown

    WORKING IN
    03h 24m
    
    or
    
    OFF FOR
    1d 08h

Đây có thể trở thành UX signature của app.

* * *

### ⭐ Recovery indicator

Sau night shift:

    🌙 Recovery
    
    Recommended recovery window
    07:30 → 14:30

Nhưng nên ghi:

> planning aid

không phải medical advice.

* * *

19\. Shift detail screen
========================

Khi tap một ca:

    Night Shift
    ────────────────
    Thu, Sep 10
    
    19:00 → 07:00
    12h 00m
    
    Job
    Mercy General
    
    Pay
    $312 estimated
    
    Break
    30m
    
    Timezone
    America/New_York
    
    ────────────────
    Edit
    Delete
    Split
    Swap

Đặc biệt:

### “Why this shift?”

Rất hữu ích:

    Why is this here?
    
    Pattern:
    4-on / 4-off
    
    Cycle day:
    Day 3 of 8
    
    Source:
    Baseline
    
    Pay rule:
    US-CA v2
    
    Timezone:
    America/New_York

Đây là UX cực kỳ hợp với Correctness Contract của ShiftEase.

* * *

20\. “What changed?” timeline
=============================

Không chỉ import mới cần.

Mỗi shift có:

    Shift history
    
    Sep 1
    Created from pattern
    
    Sep 3
    Time changed
    08:00 → 10:00
    
    Sep 4
    Template changed
    Day → Night
    
    Reason:
    Manager changed roster

Đây sẽ giải quyết một câu hỏi cực thực tế:

> “Tại sao lịch của tôi lại thành thế này?”

* * *

21\. Pay UX
===========

Đừng chỉ:

    This week: $1,420

Mà:

    THIS WEEK
    
    $1,420 estimated
    
    Regular        $980
    Night diff     $180
    Weekend diff   $90
    Overtime       $170
    ────────────────
    Total          $1,420

Tap vào OT:

    Why 6.0h overtime?
    
    Fri   +2h
    Sat   +4h

Đây là thứ giúp app **trustworthy**, đặc biệt vì positioning của bạn là correctness.

* * *

22\. Calendar nên có “conflict detection”
=========================================

Ví dụ:

    ⚠️ Conflict
    
    Dentist appointment
    09:00–10:00
    
    Night shift ends
    07:00
    
    Only 2h recovery gap

Không nhất thiết cấm user.

Chỉ cảnh báo.

* * *

23\. Smart import UI nên là một trong những USP chính
=====================================================

Thay vì form import khô:

    Upload

hãy làm:

    📸 Import roster
    
    Take a screenshot
          ↓
    
    AI / parser
          ↓
    
    We found 14 shifts
    
    ✓ 12 High confidence
    ⚠ 2 Need review

Sau đó:

    Sep 12
    Night
    19:00–07:00
    
    ✓ Looks right

và:

    Sep 14
    ???
    07:00–?
    
    ⚠ Needs review

**Không auto-commit** như spec hiện tại.

* * *

24\. Production feature rất nên có: Undo
========================================

Với một app schedule:

> **Undo là gần như bắt buộc.**

Ví dụ user vừa:

    Delete 8 shifts

hiện:

    8 shifts deleted
    
    Undo

Đây cũng làm Override architecture an toàn hơn.

* * *

25\. Backup/restore nên có trước Cloud
======================================

Trước khi làm cloud:

    Settings
     → Backup
     → Export encrypted backup

và:

    Restore

Nếu offline-first là selling point thì đây là tính năng production quan trọng.

* * *

26\. Một feature rất đáng thêm: duplicate detection
===================================================

Khi Quick Add/import:

    ⚠️ Possible duplicate
    
    You already have:
    Sep 12
    19:00–07:00
    
    Create anyway?

Đặc biệt quan trọng khi re-import roster.

* * *

27\. Production Settings nên có
===============================

Ít nhất:

    Settings
    
    Appearance
     ├─ System
     ├─ Light
     └─ Dark
    
    Calendar
     ├─ Week starts Monday
     ├─ Default view
     ├─ First day of week
     └─ 12h / 24h
    
    Time
     ├─ Timezone
     └─ DST handling
    
    Notifications
     ├─ Shift reminder
     ├─ 1 day before
     └─ X minutes before
    
    Jobs
    Pay Rules
    Backup
    Privacy
    Export
    About

* * *

28\. Một thay đổi UI mình rất khuyến nghị
=========================================

**Không để user nhìn thấy technical complexity trừ khi cần.**

Ví dụ bình thường:

    19:00 → 07:00
    12h

Không cần:

    UTC:
    2026-09-05T23:00Z

Nhưng khi có vấn đề:

    ⚠️ We couldn't calculate this shift
    
    The time 02:30 doesn't exist on
    March 8 because clocks move forward.
    
    [Choose another time]

Đây chính là:

> **Correctness Contract → UX**

rất đáng để biến thành USP.

* * *

29\. Cuối cùng: mình sẽ không cho AI agent “code tiếp tự do”
============================================================

Nếu tiếp tục bằng AI agent, mình khuyên giao task theo **gates**:

    GATE 1
    Time Engine
        ↓
    all tests
        ↓
    external review
    
    GATE 2
    Pattern + Override
        ↓
    all invariants
        ↓
    external review
    
    GATE 3
    Money
        ↓
    golden tests
        ↓
    external review
    
    GATE 4
    Persistence
        ↓
    migration/recovery/concurrency tests
    
    GATE 5
    UI
        ↓
    real device testing
    
    GATE 6
    Production hardening

Không cho agent:

    "Build all remaining features"

vì nó sẽ rất dễ biến một core chưa khóa contract thành một đống UI/data code phụ thuộc vào contract sai.

* * *

Kết luận
--------

**Bước tiếp theo tốt nhất không phải Money Engine.**

Mình đề xuất agent làm một task riêng:

> **“ShiftEase Core Contract Hardening — Time + Pattern + Override + Effective Schedule”**

với acceptance criteria:

    □ No empty UTC in valid ShiftOccurrence
    □ No empty timezone
    □ CREATE fully resolves
    □ UPDATE fully resolves
    □ REPLACE fully resolves
    □ SPLIT fully resolves
    □ SWAP semantics explicitly defined
    □ DST ambiguity preserved
    □ DST nonexistent preserved
    □ Invalid input != DST error
    □ No silent drop of unresolved occurrence
    □ Versioning semantics locked
    □ Override chain deterministic
    □ All golden + property + integration tests pass
    □ New negative tests cover every above case

**Sau khi Gate này xanh hoàn toàn → mới bắt đầu `core/money`.**

Và một lưu ý: `features.md` hiện là tài liệu rất hữu ích, nhưng từ giờ mình khuyên coi nó là **Product Capability Matrix**, không phải bằng chứng rằng feature đã production-ready. Mỗi `✅` nên chỉ được phép xuất hiện khi có **implementation + tests + acceptance scenario** tương ứng.