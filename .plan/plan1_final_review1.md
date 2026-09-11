phân tích solution plan1_final.md & suy nghĩ kỹ rồi đưa ra các ý kiến đóng góp/bổ xung/phản biện. project path /Users/hoang/htdocs_apps/ShiftEase
--------------------
Mình đã đọc trực tiếp `/Users/hoang/htdocs_apps/ShiftEase/.plan/plan1_final.md`. Bản này **tiến bộ rất nhiều so với `plan1.md`**: đã thu hẹp persona, xác định Work–Life–Money, tách P0/P1/P2/P3 và đặc biệt đã nhận ra Time Engine là phần nguy hiểm nhất.

Tuy nhiên, sau khi suy nghĩ kỹ, mình **chưa khuyên đóng băng plan này để chuyển thẳng sang `plan2`**. Có một số điểm kiến trúc và product strategy cần chốt lại trước.

* * *

1\. Verdict của mình
====================

Mình chấm:

| Hạng mục | Điểm |
| --- | --- |
| Product direction | **9/10** |
| Target user | **9/10** |
| Core value proposition | **8.5/10** |
| Differentiation | **7.5/10** |
| MVP scope | **7/10** |
| Domain model | **7/10** |
| Time Engine | **7/10** |
| Pay Engine | **5.5/10** |
| Import/OCR strategy | **6/10** |
| Privacy architecture | **7/10** |
| Monetization | **7/10** |
| Technical feasibility | **8/10** |
| Readiness để viết plan2 | **~80%** |

**Không có lỗi "fatal" khiến phải bỏ ý tưởng.**

Nhưng có khoảng **8 vấn đề lớn** mà nếu không giải quyết ở plan2 thì AI agent rất dễ code một hệ thống nhìn đẹp nhưng domain model về sau rất khó sửa.

* * *

2\. Điểm tốt nhất của plan hiện tại
===================================

Mình đặc biệt đồng ý với việc đã bỏ hướng:

> Calendar + Health AI + Sleep + Nutrition + Workout + Payroll + B2B cùng lúc.

Plan final đã chốt:

> **ShiftEase = Personal Operating System for Shift Workers**

và 3 trụ cột:

> **Work – Life – Money**

Đây là hướng đúng.

plan1(20260901-154900)

Đặc biệt, việc xác định:

> **Pattern + Exception + Time Engine**

là xương sống của hệ thống là rất đúng.

* * *

3\. Nhưng mình muốn phản biện một câu rất quan trọng
====================================================

Plan nói:

> "tính đúng tuyệt đối"

Mình **không muốn dùng requirement này trong technical spec**.

Không có hệ thống production nào nên promise "absolute correctness".

Đặc biệt với:

*   DST
    
*   timezone
    
*   payroll
    
*   OCR
    
*   employer schedule
    
*   legal overtime
    

Thay vào đó nên định nghĩa:

### Correctness contract

Ví dụ:

> Với cùng một input hợp lệ + cùng timezone database version + cùng pay rule version → kết quả phải deterministic.

Và:

> Không được silently đưa ra kết quả khi input/rule không đủ để tính.

Đây là distinction rất quan trọng.

Ví dụ:

    Cannot determine overtime
    because:
    - work week boundary not configured
    - state rule not selected

thì app phải nói:

> **Unable to calculate accurately**

chứ không đoán.

**"Không biết" tốt hơn "tính sai".**

* * *

4\. Vấn đề lớn #1 — Smart Import đang bị đặt sai tầng
=====================================================

Plan nói:

> OCR ảnh/PDF + Excel/CSV = P0/P1

và thậm chí xem đây là một trong những differentiation chính.

plan1(20260901-154900)

Mình đồng ý đây là **cơ hội rất hay**.

Nhưng mình không đồng ý với cách hiện tại.

OCR không phải một feature đơn giản
-----------------------------------

Một nurse đưa:

    September Schedule
    Sep 1  D
    Sep 2  D
    Sep 3  N
    Sep 4  OFF
    ...

thì dễ.

Nhưng thực tế có thể là:

                  MON TUE WED THU FRI
    John           D   D   N   N   O
    Sarah          N   O   D   D   D
    Mike           O   D   D   N   N

hoặc PDF:

*   màu sắc
    
*   ký hiệu
    
*   merged cells
    
*   abbreviation
    
*   tên bệnh viện
    
*   pay code
    
*   multiple employees
    
*   multiple locations.
    

OCR chỉ giải quyết:

> "đọc chữ"

Nó chưa giải quyết:

> **"hiểu roster".**

* * *

5\. Smart Import nên có một pipeline riêng
==========================================

Mình đề nghị plan2 thiết kế:

    Image / PDF / Excel / CSV
            ↓
    Document Parser
            ↓
    Raw Extraction
            ↓
    Schedule Interpretation
            ↓
    Candidate Shifts
            ↓
    USER REVIEW
            ↓
    Commit to Calendar

**Không bao giờ:**

    OCR
     ↓
    tự động ghi thẳng vào calendar

Ví dụ:

    We found 14 shifts.
    
    Sep 01   DAY   07:00–19:00
    Sep 02   DAY   07:00–19:00
    Sep 03   NIGHT 19:00–07:00
    ...
    
    [✓ Confirm all]

User sửa được trước khi commit.

Đây sẽ là một feature cực mạnh.

* * *

6\. Mình còn muốn thêm "Import Confidence"
==========================================

Ví dụ:

    Sep 03
    Night Shift
    19:00–07:00
    
    Confidence: High

nhưng:

    Sep 07
    ?
    07:00–19:00
    
    Confidence: Low

User phải xác nhận.

Điều này giải quyết một vấn đề cực lớn:

> **OCR sai → lịch sai → payroll sai → mất trust.**

* * *

7\. Vấn đề lớn #2 — Pattern → Occurrence → Exception đúng, nhưng Exception Model chưa đủ
========================================================================================

Plan hiện tại:

TypeScript

    isException: boolean
    exceptionType?: ...

là **chưa đủ**.

Ví dụ pattern:

    DDDD OOOO

Generated:

    Sep 1 D
    Sep 2 D
    Sep 3 D
    Sep 4 D
    Sep 5 O
    ...

User làm:

> Sep 3 đổi DAY → NIGHT

Đơn giản.

Nhưng thực tế còn:

### Delete

    Sep 3 = OFF

### Replace

    Sep 3 DAY → NIGHT

### Modify

    Sep 3
    07:00–19:00
    →
    08:00–20:00

### Split

    Sep 3
    07:00–11:00
    +
    15:00–19:00

### Add

    Sep 3
    existing DAY
    +
    extra 4h overtime

### Swap

    Sep 3 DAY
    ↕
    Sep 7 NIGHT

Do đó:

**`isException` không nên là abstraction chính.**

* * *

8\. Mình khuyên có "Occurrence Override"
========================================

Ví dụ conceptually:

    Pattern
       ↓
    Occurrence
       ↓
    Override

Override có:

    operation:
      CREATE
      UPDATE
      DELETE
      REPLACE
      SPLIT

và reference tới occurrence/pattern.

Khi render:

    Pattern baseline
           +
    Overrides
           ↓
    Effective Schedule

Điều này làm domain model mạnh hơn rất nhiều.

* * *

9\. Vấn đề lớn #3 — "Generate 12 months" cần quyết định rõ source of truth
==========================================================================

Plan nói generate khoảng 12 tháng tới.

plan1(20260901-154900)

Mình muốn plan2 chốt:

### Pattern mới là source of truth?

hay:

### Occurrences mới là source of truth?

Mình khuyên:

> **Pattern = source of truth cho recurring schedule.**

Occurrence là projection/materialization.

Ví dụ:

    Pattern
    4 ON / 4 OFF
    Anchor = Sep 1

→ generate:

    Sep 1
    Sep 2
    Sep 3
    ...

Nếu user thay Sep 10:

    Pattern
         +
    Override Sep 10

chứ không sửa pattern.

* * *

10\. Cần xử lý khi user thay Pattern
====================================

Đây là một edge case rất quan trọng mà plan hiện tại chưa nói.

Ví dụ:

    Pattern A
    4 ON / 4 OFF

đã generate tới:

> March 2027

Sau đó user:

> "From Oct 1, my roster changes to 3 ON / 4 OFF."

Phải làm gì?

Không thể đơn giản update pattern cũ.

Nên model phải hỗ trợ:

    Pattern A
    Sep 1 → Sep 30
    
    Pattern B
    Oct 1 → ...

Tức:

    Pattern
     ├── effective_from
     └── effective_until

Đây là thứ mình muốn thấy trong plan2.

* * *

11\. Vấn đề lớn #4 — Time Engine hiện tốt nhưng còn thiếu "Civil Time"
======================================================================

Đây là phần mình muốn AI agent **tuyệt đối không tự sáng tạo**.

Plan đã làm đúng khi lưu:

    shift_date
    start_datetime_utc
    end_datetime_utc
    timezone

và tính duration từ UTC.

plan1(20260901-154900)

Nhưng recurring shift cần thêm một concept:

> **local/civil schedule**

Ví dụ:

    Night shift
    22:00 → 06:00
    America/New_York

Pattern phải nói:

> "Mỗi occurrence bắt đầu lúc 22:00 local time."

Chứ không phải:

> "Mỗi occurrence bắt đầu cách nhau đúng 24h UTC."

Nếu không, recurring schedule xuyên DST sẽ sai.

* * *

12\. Phải phân biệt 3 thứ
=========================

Mình đề nghị plan2 formalize:

    1. Local Civil Time
       22:00 America/New_York
    
    2. Instant
       2026-11-01T...
    
    3. Duration
       actual elapsed seconds

### Local time dùng để:

*   pattern
    
*   schedule
    
*   display
    
*   user intent
    

### UTC/Instant dùng để:

*   duration
    
*   ordering
    
*   notifications
    
*   comparison
    

### Timezone dùng để:

*   resolve local → instant.
    

Đây là architecture rất quan trọng.

* * *

13\. Cần test thêm "non-existent" và "ambiguous" local time
===========================================================

Plan hiện đã có:

*   spring-forward
    
*   fall-back
    
*   overnight
    
*   timezone change.
    
    plan1(20260901-154900)
    

Nhưng còn:

### Non-existent time

Một số local times không tồn tại khi clock nhảy.

Ví dụ:

    02:30

có thể không tồn tại trong ngày DST transition.

### Ambiguous time

Một local time có thể xuất hiện **hai lần** khi clock quay lại.

Do đó plan2 phải định nghĩa:

    If local time is ambiguous:
        which occurrence?
    
    If local time does not exist:
        reject?
        shift forward?
        require confirmation?

**Không để library mặc định quyết định mà không có product rule.**

* * *

14\. Vấn đề lớn #5 — Pay Engine hiện tại còn nguy hiểm hơn Time Engine
======================================================================

Schema:

TypeScript

    payMultiplier
    baseHourlyRate
    nightDifferential
    weekendDifferential
    overtimeRules

nhìn khá đẹp, nhưng thực tế payroll phức tạp hơn nhiều.

Đặc biệt:

    payMultiplier

trong `ShiftTemplate`

và

    nightDifferential
    weekendDifferential
    overtimeRules

trong PayRule

có nguy cơ **double-counting**.

Ví dụ:

    Night shift
    payMultiplier = 1.3

và:

    Night differential = +30%

→ app có thể vô tình tính:

    1.3 × 1.3

Đây là bug domain rất dễ xảy ra.

* * *

15\. Mình khuyên bỏ pay semantics khỏi ShiftTemplate
====================================================

`ShiftTemplate` nên mô tả:

    Day
    Night
    Evening

về mặt **thời gian / UI**.

Còn:

> "Night được trả thêm 30%"

phải nằm hoàn toàn trong:

    PayRule

Tức:

    ShiftTemplate
       ↓
    What is this shift?
    
    PayRule
       ↓
    How much is this shift worth?

Hai domain phải tách.

* * *

16\. Pay Engine nên có "Pay Calculation Breakdown"
==================================================

Đây là feature mình đánh giá cực kỳ quan trọng.

Không chỉ:

> Estimated: $312

Mà:

    Sep 03 Night Shift
    
    8.0h × $32.00       $256
    Night differential    $38
    Weekend premium       $18
    --------------------------------
    Estimated             $312

Và nếu overtime:

    Regular     40h
    Overtime     8h
    
    Regular pay      $1,280
    OT pay              $384
    Night premium        $76
    -------------------------
    Estimated          $1,740

User có thể kiểm tra **tại sao app tính ra số đó**.

Đây là cách xây trust.

* * *

17\. Pay Rule phải có version
=============================

Đây là điểm mình rất muốn bổ sung.

Ví dụ:

    Pay Rule v1
    effective: Jan 1 → Jun 30
    
    Pay Rule v2
    effective: Jul 1 → ...

Không được:

> user thay Pay Rule hôm nay → lịch sử 6 tháng trước tự thay đổi.

Historical calculation phải reproducible.

* * *

18\. Pay Engine nên tính "gross estimate", không nên trở thành payroll
======================================================================

Plan đã rất đúng khi ghi:

> "Ước tính — không phải bảng lương chính thức."
> 
> plan1(20260901-154900)

Mình sẽ giữ nguyên.

Nhưng còn phải chốt:

### MVP chỉ tính:

**Gross estimated earnings**

Không tính:

*   tax
    
*   deductions
    
*   insurance
    
*   pension
    
*   benefits
    
*   net salary
    

Nếu làm net income thì app bắt đầu tiến gần payroll/tax software.

* * *

19\. "Pay Rule Template theo quốc gia" cần cẩn thận
===================================================

Plan đề xuất:

> "US Hospital Nurse — California overtime rule", "UK NHS shift differential".
> 
> plan1(20260901-154900)

Mình thấy ý tưởng tốt cho UX nhưng **rất nguy hiểm về maintenance**.

Luật thay đổi.

Contract bệnh viện khác nhau.

Union agreement khác nhau.

Employer policy khác nhau.

Do đó nên gọi:

> **Example / configurable template**

chứ không nên tạo impression:

> "ShiftEase knows the legal payroll rules."

Và mọi template phải có:

    Source / last updated
    Effective date
    User confirmation

* * *

20\. Vấn đề lớn #6 — Family Webcal đang mâu thuẫn với Offline-first
===================================================================

Plan nói:

> Dynamic iCal/Webcal Link

nhưng đồng thời:

> Offline-first + không bắt buộc account.

Đây là một architectural contradiction cần giải quyết.

Dynamic Webcal nghĩa là:

    Phone A
       ↓
    server
       ↓
    Webcal URL
       ↓
    Phone B

Nếu không có server:

**không có dynamic URL để subscribe.**

Do đó phải phân biệt:

### Offline MVP

    Export .ics

### Online P1

    Private Webcal URL

và lúc đó cần:

*   server
    
*   authentication/token
    
*   revocation
    
*   rotation
    
*   privacy
    
*   rate limiting.
    

Không nên ghi chung thành một capability.

* * *

21\. Thậm chí Webcal token là dữ liệu nhạy cảm
==============================================

Nếu:

    https://api.shiftease.com/calendar/abc123...

ai có URL thì có thể xem lịch.

Do đó phải có:

    Share link
        ↓
    Revoke
        ↓
    Regenerate

và nên có các loại:

    FULL
    BUSY_FREE
    RECOVERY

Ý tưởng privacy mode trong plan rất tốt.

plan1(20260901-154900)

Nhưng plan2 cần thiết kế security model cụ thể.

* * *

22\. Vấn đề lớn #7 — Commute reminder chưa được định nghĩa
==========================================================

MVP ghi:

> Shift reminder, commute reminder, weekly summary.

Nhưng commute reminder cần biết:

    home
    workplace
    travel time
    traffic?

Nếu chỉ:

> "Your shift starts in 1 hour"

thì đó thực chất là shift reminder.

Nếu app muốn:

> "Leave home by 06:15"

thì phải có:

*   workplace location
    
*   home location
    
*   travel duration
    
*   possibly maps/traffic provider.
    

Mình đề nghị **không đưa smart commute vào P0**.

P0 chỉ:

> Shift starts in X minutes.

Commute intelligence để sau.

* * *

23\. Vấn đề lớn #8 — Widget không nên là P0 core
================================================

Plan đặt Widget P0.

plan1(20260901-154900)

Mình không phản đối widget.

Nhưng nếu mục tiêu là:

> build bằng AI agents

thì widget có thể tạo rất nhiều platform-specific complexity:

*   iOS WidgetKit
    
*   Android AppWidget/Glance
    
*   data refresh
    
*   deep link
    
*   shared storage
    
*   timeline policies.
    

Trong khi widget không giúp validate core domain.

Mình sẽ đưa:

> **Widget = P1**

và MVP P0 dùng:

> excellent Today screen + notifications.

Sau khi core ổn → widget.

* * *

24\. Mình muốn thêm một feature P0 mà plan chưa nhấn đủ: "Quick Add"
====================================================================

Nếu ShiftEase muốn thắng bằng **Ease**, đây phải là một trong những feature quan trọng nhất.

Ví dụ user mở app:

    + Add Shift

không được bắt:

    Name
    Start
    End
    Timezone
    Pay rule
    Color
    ...

Mà:

    + Add
    
    DAY
    07:00 → 19:00
    
    [Save]

Hoặc:

    NIGHT
    19:00 → 07:00
    
    [Save & Repeat]

Một tay.

Ít thao tác.

* * *

25\. Nên có "Smart Repeat"
==========================

Ví dụ:

    Add Night Shift
    
    [ Repeat ]
    
    Every:
    ○ day
    ○ 2 days
    ○ week
    ● custom pattern

Hoặc:

    Repeat:
    Mon Tue Wed
    for 4 weeks

Sau đó:

    Preview 12 shifts

**Confirm.**

Đây mới thực sự hiện thực hóa chữ **Ease**.

* * *

26\. Một feature khác rất đáng có: "Paste Schedule"
===================================================

Không cần OCR ngay.

User copy text:

    Sep 1 Day
    Sep 2 Day
    Sep 3 Night
    Sep 4 Night
    Sep 5 Off

→ app parse.

Hoặc:

> Paste screenshot.

→ OCR.

Tức Smart Import nên có hierarchy:

    Manual quick add
          ↓
    Paste text
          ↓
    CSV
          ↓
    Excel
          ↓
    Image OCR
          ↓
    PDF

Không nhất thiết phải làm OCR/PDF đầu tiên.

* * *

27\. Đây có thể là killer loop của ShiftEase
============================================

Mình nhìn thấy một flow rất mạnh:

    Employer gives schedule
            ↓
    Take screenshot
            ↓
    Share to ShiftEase
            ↓
    ShiftEase recognizes shifts
            ↓
    Review
            ↓
    Import
            ↓
    Calendar populated
            ↓
    Pattern detected
            ↓
    Future schedule generated

Nếu làm tốt:

> **đây mới có thể là differentiation thực sự.**

Vì user không muốn "quản lý calendar".

Họ muốn:

> **"Tôi vừa nhận roster → đưa nó vào app trong 10 giây."**

* * *

28\. Cần thêm "Pattern Detection from Imported Schedule"
========================================================

Sau import:

    Sep 1 D
    Sep 2 D
    Sep 3 D
    Sep 4 O
    Sep 5 O
    Sep 6 N
    Sep 7 N
    ...

app:

> **We detected a repeating pattern.**

    D D D O O N N O

> "Use this pattern to predict future shifts?"

\[Yes\]

Đây là AI/automation **có giá trị thực tế**, hơn nhiều so với chatbot.

* * *

29\. Một feature khác mình muốn đưa vào P1: "What changed?"
===========================================================

Nếu user import roster mới:

    Old schedule
    Sep 12 DAY
    
    New schedule
    Sep 12 NIGHT

app:

> ⚠️ **1 shift changed**

    Sep 12
    DAY → NIGHT

và:

    Estimated pay: +$42
    Next day availability: changed

Đây là một use case rất phù hợp với "Personal Operating System".

* * *

30\. Product model nên có "Job / Workplace" riêng
=================================================

Plan có:

> multiple jobs

nhưng schema hiện chưa thể hiện rõ.

Mình muốn:

    Job
     ├── Hospital A
     │     ├── Shift templates
     │     └── Pay rule
     │
     ├── Clinic B
     │     ├── Shift templates
     │     └── Pay rule
     │
     └── Agency C

Vì cùng:

    Night Shift
    19:00–07:00

nhưng:

    Hospital A → $35/h
    Clinic B   → $42/h
    Agency C   → $50/h

Không nên để `ShiftTemplate` global nếu nó mang semantics của workplace.

* * *

31\. Cần tách "Schedule" và "Actual Work"
=========================================

Đây là một điểm mình rất muốn bổ sung.

Hiện plan chủ yếu là:

> planned shift.

Nhưng sau này user có:

    Scheduled:
    07:00–19:00
    
    Actual:
    07:12–19:34

và:

    Scheduled = 12h
    Actual = 12h22m

Nếu sau này có overtime/pay thì đây là distinction quan trọng.

Không nhất thiết làm clock-in/out MVP.

Nhưng domain model nên **chừa đường**:

    ScheduledShift
    ActualWork

để không phải phá schema về sau.

* * *

32\. "Leave" cũng không nên chỉ là exceptionType
================================================

PTO:

    Sep 10–Sep 15

không phải một shift exception đơn lẻ.

Nó là:

> **Availability / Leave event**

Tương tự:

*   vacation
    
*   sick
    
*   personal leave
    
*   holiday
    
*   training
    
*   unavailable.
    

Mình khuyên domain model có:

    Schedule Event
     ├── Shift
     ├── Time Off
     ├── Personal Event
     └── Availability Block

thay vì nhét tất cả vào `ShiftOccurrence.exceptionType`.

* * *

33\. Đây sẽ giúp Work–Life integration tốt hơn
==============================================

Cuối cùng model có thể là:

                     Calendar
                        │
           ┌────────────┼────────────┐
           ↓            ↓            ↓
         Work          Life         Time Off
           │            │
         Shift        Family
         Overtime     Doctor
         Training     Event

Thay vì app chỉ có:

    Shift

Đây là hướng mình nghĩ plan2 nên formalize.

* * *

34\. Monetization: Lifetime $39.99 là hợp lý để test, nhưng đừng đóng đinh
==========================================================================

Plan đề xuất:

    $3.99/month
    $29.99/year
    $39.99 lifetime

Mình không phản đối.

Nhưng:

> **không nên quyết định pricing architecture quá sớm.**

Đặc biệt lifetime:

    $39.99

nếu sau này phải trả:

*   OCR API
    
*   cloud storage
    
*   Webcal hosting
    
*   sync
    
*   AI inference
    

thì lifetime users trở thành liability.

Do đó Lifetime nên chỉ unlock:

> local capabilities.

Còn cloud/AI có thể cần subscription hoặc usage-based.

* * *

35\. Free tier hiện hơi quá ít để tạo word-of-mouth
===================================================

Plan:

> 1 job, basic patterns, calendar cơ bản.

Mình sẽ cân nhắc:

    FREE
    1–2 jobs
    unlimited basic shifts
    basic rotation
    basic notifications
    offline

Không nên khiến user thấy:

> "Tôi phải trả tiền chỉ để dùng calendar."

Paywall nên xuất hiện khi họ đã cảm nhận:

> **"App này thật sự hiểu lịch ca của tôi."**

Sau đó Pro:

    Smart Import
    Pay
    Multiple jobs
    Advanced patterns
    Family
    Widgets
    Backup

* * *

36\. Go-to-market hiện tại vẫn hơi chung chung
==============================================

Plan nói:

*   Reddit
    
*   Facebook
    
*   influencer nurse
    
*   blog/video.
    
    plan1(20260901-154900)
    

Mình muốn cụ thể hơn.

Đừng marketing:

> "Best shift calendar."

Hãy marketing bằng pain:

### Hook 1

> **Turn your hospital schedule into a calendar in seconds.**

### Hook 2

> **Screenshot your roster. ShiftEase does the rest.**

### Hook 3

> **Know when you're working, when you're free, and what you'll earn.**

### Hook 4

> **Your shifts. Your life.**

Trong đó **Smart Import** có thể là acquisition hook cực tốt.

* * *

37\. Persona "Nurse" nên tiếp tục được giữ rất chặt
===================================================

Mình đồng ý với decision:

> Nurse / Healthcare shift worker 25–45 tại Mỹ/Anh/Đức.
> 
> plan1(20260901-154900)

Đừng mở rộng quá sớm sang:

> Police + firefighter + factory + FIFO + retail...

Chúng chỉ là:

> **future expansion.**

Ngay cả UI copy ban đầu cũng nên ưu tiên:

    Shift
    Roster
    Day shift
    Night shift
    Overtime
    PTO

thay vì generic workforce terminology.

* * *

38\. Một điều mình muốn thay đổi trong P0/P1/P2
===============================================

Mình sẽ điều chỉnh thành:

### P0 — Validate Core Loop

    1. Today
    2. Calendar
    3. Quick Add
    4. Shift Templates
    5. Rotation
    6. Pattern Preview
    7. Overnight
    8. DST/timezone engine
    9. Notifications
    10. Offline
    11. Edit/Delete/Bulk edit
    12. Basic jobs
    13. Basic import: text/CSV

### P1 — Killer Differentiation

    14. Screenshot/OCR import
    15. PDF import
    16. Excel import
    17. Import review/correction
    18. Pattern detection
    19. Pay Engine
    20. Income dashboard
    21. Partner/Family
    22. Availability Finder
    23. ICS export
    24. Backup
    25. Widgets

### P2 — Moat

    26. Schedule change detection
    27. Smart suggestions
    28. Wellness
    29. Colleague sharing
    30. Webcal
    31. Cloud sync

### P3

    Health AI
    B2B
    Team
    Admin

Cách này mình thấy **an toàn hơn plan hiện tại**.

* * *

39\. Nhưng có một tranh luận quan trọng: OCR P0 hay P1?
=======================================================

Mình sẽ không quyết định bằng cảm tính.

Đây là feature cần **prototype trước**.

Làm một prototype rất nhỏ:

    20 screenshots roster thực tế
            ↓
    OCR/parser
            ↓
    candidate shifts

Đo:

    % correct dates
    % correct shift type
    % correct start/end
    % manual corrections

Nếu đạt chất lượng tốt:

> đẩy Smart Import thành P0.

Nếu không:

> P1.

**Đừng commit architecture OCR lớn trước khi test dữ liệu thật.**

* * *

40\. Testing strategy cần mạnh hơn
==================================

Plan đã có Time Engine test.

plan1(20260901-154900)

Mình muốn plan2 thêm:

Golden test cases
-----------------

Một file:

    time_engine_cases.json

chứa hàng trăm case.

Ví dụ:

    input:
    timezone = America/New_York
    date = ...
    start = 22:00
    end = 07:00
    
    expected:
    utcStart = ...
    utcEnd = ...
    duration = ...

AI agent sửa code → chạy toàn bộ golden tests.

* * *

41\. Pattern Engine cũng cần property tests
===========================================

Ví dụ:

    cycle = 4 ON / 4 OFF

phải đảm bảo:

    occurrence[n + 8]
    ==
    same pattern position as occurrence[n]

và:

    editing occurrence #10

không làm thay đổi:

    occurrence #11+

trừ khi user explicitly sửa pattern.

Đây là loại test rất phù hợp cho AI coding agent.

* * *

42\. Cần có "Decision Log" trong plan2
======================================

Vì bạn đang build bằng nhiều AI agents, mình khuyên plan2 có một section:

    ARCHITECTURAL INVARIANTS

Ví dụ:

    INVARIANT-001
    Pattern never mutates because an occurrence is edited.
    
    INVARIANT-002
    Historical occurrences never change timezone automatically.
    
    INVARIANT-003
    Pay calculation never modifies source shift data.
    
    INVARIANT-004
    Imported data never commits without user confirmation.
    
    INVARIANT-005
    ShiftTemplate contains time semantics, not pay semantics.
    
    INVARIANT-006
    Local civil time is used for recurrence.
    
    INVARIANT-007
    Elapsed duration is calculated from resolved instants.

Đây sẽ là **kim chỉ nam cực kỳ tốt cho AI agents**.

* * *

43\. Đặc biệt cần có "Never do this"
====================================

Mình khuyên plan2 thêm:

    NEVER:
    - calculate overnight duration from local clock subtraction
    - mutate Pattern when editing an occurrence
    - auto-commit OCR result
    - infer payroll rules silently
    - change historical occurrence timezone
    - mix pay multiplier into ShiftTemplate
    - let current PayRule rewrite historical earnings
    - require cloud for core calendar

Đây là loại instruction AI agent rất dễ hiểu.

* * *

44\. Architecture mình đề nghị cho plan2
========================================

Không cần quá phức tạp:

    lib/
    ├── core/
    │   ├── time/
    │   ├── pattern/
    │   ├── recurrence/
    │   ├── notifications/
    │   └── money/
    │
    ├── domain/
    │   ├── jobs/
    │   ├── shifts/
    │   ├── patterns/
    │   ├── events/
    │   ├── leave/
    │   ├── pay/
    │   └── sharing/
    │
    ├── data/
    │   ├── database/
    │   ├── repositories/
    │   └── migrations/
    │
    ├── features/
    │   ├── today/
    │   ├── calendar/
    │   ├── add_shift/
    │   ├── import/
    │   ├── income/
    │   ├── availability/
    │   └── settings/
    │
    └── platform/
        ├── notifications/
        ├── widgets/
        ├── share/
        └── calendar/

Điểm quan trọng:

> **`core/time` và `core/pattern` không được phụ thuộc UI.**

* * *

45\. Có một vấn đề nhỏ nhưng đáng chú ý trong file
==================================================

`plan1_final.md` nói nó được tổng hợp từ:

> `plan1.md` + 5 bản review AI (`plan1_review1` → `plan1_review5`)

Trong khi thư mục `.plan` hiện thực tế có cả:

    plan1_review6.md

và review6 cũng là file mới nhất trong chuỗi review.

Mình đã kiểm tra trực tiếp thư mục project và thấy `plan1_final.md` cùng `plan1_review1` → `plan1_review6` đều tồn tại.

Vì vậy phần header của final nên được cập nhật thành:

> Tổng hợp từ `plan1.md` + `plan1_review1` → `plan1_review6`

nếu review6 thực sự đã được dùng để adjudicate. Đây là vấn đề documentation nhỏ nhưng nên sửa trước khi xem final là baseline.

* * *

46\. Quan trọng: mình chưa khuyên code ngay
===========================================

Nếu đây là project của bạn, mình sẽ đi theo:

    plan1_final
          ↓
    Architecture review
          ↓
    Resolve 8 domain questions
          ↓
    plan2
          ↓
    plan2 review
          ↓
    implementation spec
          ↓
    AI coding agents

**Không nên:**

    plan1_final
       ↓
    AI agent
       ↓
    code
       ↓
    phát hiện domain problem
       ↓
    migration/refactor

Vì các lỗi kiểu:

> Pattern / Occurrence / Exception / Pay / Timezone

nếu đã nằm trong database rồi thì sửa sau rất tốn.

* * *

47\. 8 quyết định mình muốn plan2 bắt buộc trả lời
==================================================

Đây là phần quan trọng nhất của review này.

### D1 — Pattern mutation

> Khi user đổi pattern từ ngày X, pattern cũ và mới được version hóa thế nào?

### D2 — Occurrence override

> Edit/Delete/Swap/Split một occurrence được biểu diễn chính xác thế nào?

### D3 — Civil time

> Recurrence chạy theo local wall-clock hay UTC?

→ **Local wall-clock.**

### D4 — DST ambiguity

> Non-existent/ambiguous local time xử lý thế nào?

### D5 — Pay semantics

> ShiftTemplate có chứa payMultiplier không?

→ **Mình đề nghị NO.**

### D6 — Pay versioning

> PayRule thay đổi thì historical earnings có thay đổi không?

→ **NO.**

### D7 — Import safety

> OCR/PDF/Excel result có auto-commit không?

→ **NO. User confirmation bắt buộc.**

### D8 — Webcal

> Dynamic Webcal có server/account/token architecture thế nào?

→ Không nên giả định nó hoạt động trong offline-only architecture.

* * *

48\. Kết luận cuối
==================

Mình đánh giá **`plan1_final.md` đã đi đúng hướng và đủ tốt để tiếp tục**, nhưng chưa phải "final final".

Điểm quan trọng nhất là:

> **Plan đã giải quyết tốt vấn đề product positioning, nhưng plan2 phải giải quyết sâu vấn đề domain correctness.**

Ba module mình đặc biệt muốn bảo vệ khỏi AI agent:

           ┌────────────────────────┐
           │      TIME ENGINE       │
           │ DST / TZ / Civil Time  │
           └───────────┬────────────┘
                       ↓
           ┌────────────────────────┐
           │     PATTERN ENGINE     │
           │ Pattern → Occurrence   │
           │       → Override       │
           └───────────┬────────────┘
                       ↓
           ┌────────────────────────┐
           │       PAY ENGINE       │
           │ Rules → Breakdown      │
           │ Versioned / Auditable  │
           └────────────────────────┘

**Nếu ba phần này đúng**, phần UI/mobile còn lại tương đối thẳng.

**Nếu ba phần này sai**, dù UI đẹp đến đâu ShiftEase vẫn là một app lịch ca không đáng tin.

Và mình thấy có một hướng differentiation đáng để ưu tiên hơn nữa so với bản final hiện tại:

> **"Screenshot your roster → ShiftEase understands it → review → your entire shift calendar is ready."**

Kết hợp với:

> **"Your shifts. Your life."**

thì product story trở nên rất rõ: **ShiftEase không bắt người làm ca ngồi nhập lịch; nó biến roster mà họ đã nhận thành một hệ thống quản lý cuộc sống của họ.**

Đây là điểm mình sẽ đưa lên đầu khi viết `plan2`.