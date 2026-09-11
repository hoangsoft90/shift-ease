Agent đang code xong, bạn cần review đánh giá lại toàn bộ. Đọc những file sau để biết những gì đã thay đổi:

- checklist.md
- features.md
- result*.txt (mới nhất)
- next.md
- /handoff*.md mới nhất

> Xem tính năng đã code có lỗ hổng không như: sai logic, khi sử dụng có thể mất mát dữ liệu, crash bug...
> Tính năng đã đầy đủ để xuất bản app chưa, nếu chưa gợi ý đầy đủ tính năng hữu ích một lần cuối để cho agent code một thể rồi review.

Toàn bộ files+code của project tại /Users/hoang/htdocs_apps/ShiftEase .
Show more
--------------------
Mình đã review lại theo **source hiện tại**, không chỉ tin `handoff/result`.

Đã kiểm tra:

*   `handoff_20260906_144500.md`
    
*   `checklist.md`
    
*   `features.md`
    
*   `result14_gate_a.txt` — `result*.txt` mới nhất hiện có
    
*   `next.md`
    
*   toàn bộ cây `lib/`
    
*   toàn bộ cây `test/`
    
*   các phần quan trọng: Time, Pattern, Import, Money, DB, Domain, UI, composition, migration.
    

**Kết luận quan trọng:** handoff nói Gate A/B đã đóng và 179/179 pass, nhưng review độc lập của mình **chưa đồng ý cho release và cũng chưa đồng ý coi Gate A/B hoàn toàn sạch**. Có một số lỗi logic/persistence mà test hiện tại chưa bắt được.

* * *

1\. Verdict tổng thể
====================

Hiện tại mình đánh giá:

> **Core engine tốt, kiến trúc khá tốt, nhưng app chưa đạt production release.**

Nếu coi:

*   Core correctness = 40%
    
*   Persistence/data integrity = 20%
    
*   UX/product completeness = 20%
    
*   Mobile/security/release = 20%
    

thì hiện tại khoảng **7/10**.

Điểm đáng mừng là **không cần làm lại kiến trúc**. Nhưng trước khi cho agent code hàng loạt feature mới, mình muốn đóng một batch cuối về **data integrity + product completeness**, rồi mới release.

* * *

2\. 🔴 P1 — `EXTRACTED → COMMITTED` vẫn có thể bypass Review
============================================================

Đây là lỗi mình vẫn xác nhận trực tiếp trong:

`lib/core/import/import_engine.dart`

`commitImport()` đang cho:

    REVIEWING → COMMIT
    EXTRACTED  → COMMIT   ← vẫn được phép

Trong code:

    if (session.state != ImportState.reviewing &&
        session.state != ImportState.extracted)

Điều này mâu thuẫn trực tiếp với invariant:

> Imported data không bao giờ commit nếu chưa user confirm.

UI hiện có thể ép Review, nhưng **core engine không enforce invariant**.

### Failure scenario

Một caller:

    parseDocument()
    → EXTRACTED
    → commitImport()

không cần gọi:

    applyReview()

Core vẫn đi tiếp.

Đây chính là loại bug cần chặn ở core boundary, không nên trông chờ UI.

### Cần sửa

    EXTRACTED → COMMIT = reject
    REVIEWING → COMMIT = allowed

Và thêm test:

    EXTRACTED + approved candidate
    → commit
    → MUST FAIL

* * *

3\. 🔴 P1 — `changeRosterFrom()` không atomic
=============================================

Trong:

`lib/domain/schedule_service.dart`

đang làm:

    savePattern(closed)
    savePattern(newVersion)

hai transaction riêng.

Nếu:

    1. đóng pattern cũ → SUCCESS
    2. save pattern mới → FAIL

thì database có thể rơi vào:

    old pattern = CLOSED
    new pattern = NOT EXIST

Đây là **data integrity bug**.

### Failure scenario

User chọn:

> New version from Sep 15

App:

    old:
    effectiveUntil = Sep 14

thành công.

Sau đó new pattern gặp lỗi DB:

    UNIQUE
    constraint
    invalid sequence
    template failure

→ rollback transaction thứ hai, nhưng transaction thứ nhất đã commit.

Kết quả:

> roster bị đóng nhưng không có roster mới.

### Đây là P1.

`changeRosterFrom()` phải có transaction bao quanh:

    BEGIN
      close old
      insert new
    COMMIT

Nếu bất kỳ bước nào fail:

    ROLLBACK

* * *

4\. 🔴 P1 — `saveOverride()` vẫn silent-ignore conflicting ID
=============================================================

`lib/core/db/schedule_repository.dart`

đang:

    existing ID?
        return;

Comment nói:

> DIFFERENT override with same id is rejected.

Nhưng implementation thực tế **không reject**.

### Ví dụ

Đã có:

    override abc
    UPDATE 08:00 → 16:00

Caller gửi lại:

    override abc
    UPDATE 09:00 → 18:00

DB:

    existing → return

Không exception.

Không cảnh báo.

Không audit.

### Đây là silent data corruption class.

Cần:

    same ID + identical payload
        → idempotent OK
    
    same ID + different payload
        → ImmutableHistoryError

Đây cũng phải có test.

* * *

5\. 🔴 P1 — ImportSession vẫn có khả năng bị overwrite lịch sử
==============================================================

Trong:

`lib/core/db/business_repository.dart`

`ImportRepository.saveSession()` dùng:

    ON CONFLICT(id) DO UPDATE

và update:

*   state
    
*   raw extraction
    
*   committed ids
    
*   history
    
*   jobId
    
*   OFF dates
    
*   window
    

Điều này nghĩa là cùng `session.id` có thể được dùng để rewrite dữ liệu cũ.

Ví dụ:

    COMMITTED

sau đó caller ghi lại cùng ID:

    EXTRACTED

hoặc thay candidates/raw extraction.

Điều này hơi nguy hiểm vì `ImportSession` chính là **audit record**.

### Nên có invariant:

    COMMITTED session
    → immutable
    
    EXTRACTED/REVIEWING
    → chỉ được transition hợp lệ

Không nên coi `session.id` chỉ là upsert key.

* * *

6\. 🔴 P1 — `OFF` và `SHIFT` cùng ngày có thể cùng tồn tại
==========================================================

Import commit hiện gom:

    offDates
    shifts

nhưng không thấy invariant chặn:

    2026-09-10 OFF
    2026-09-10 Day 07:00-19:00

Cùng một roster.

Sau đó persistence có thể có:

    committedOffDates = [09-10]
    occurrence = 09-10 Day

Render logic:

    suppressed pattern
    +
    imported occurrence

nên vẫn có thể hiện Day.

Nhưng dữ liệu nguồn nói đồng thời:

> OFF

và:

> Day.

Đây là **contradictory imported data**.

### Nên xử lý

Trước commit:

    same date:
        OFF + SHIFT
           → COMMIT_UNRESOLVED / CONFLICT

UI:

> Sep 10 has both OFF and a shift. Choose one before committing.

Đây là tính năng rất đáng có trước release.

* * *

7\. 🔴 P1 — `2-2-3` preset đang sai
===================================

Trong:

`lib/features/pattern_builder/pattern_builder_screen.dart`

preset:

    2-2-3
    length = 7
    workSlots =
    [true, true, true, true, false, false, false]

Đây là:

> **4-on / 3-off**

chứ không phải 2-2-3.

Đây là lỗi UI/business logic rất cụ thể.

Nếu người dùng chọn:

> 2-2-3

app phải không thể tạo ra:

    WWWWOOO

### Cần sửa trước release.

Đồng thời mình khuyến nghị test **preset semantics**, không chỉ test widget render.

* * *

8\. 🟠 P1/P2 — PayRule repository vẫn tự tạo Job
================================================

Trong:

`lib/core/db/business_repository.dart`

`savePayRule()` gọi:

    jobs.ensureJob(...)

Nếu `jobId` sai:

    nurse-main

thay vì reject unknown job, repository có thể tạo:

    Job nurse-main
    Timezone UTC

Đây là domain corruption.

PayRule phải phụ thuộc vào Job đã tồn tại.

Nên:

    unknown job
    → StateError / EntityNotFound

không auto-create.

* * *

9\. 🟠 P2 — PayRule child comparison phụ thuộc order
====================================================

`_payChildrenDiffer()` query:

    ORDER BY type

rồi compare với:

    rule.differentials[i]

Nếu cùng logical rules nhưng input order khác:

    [NIGHT, WEEKEND]

vs:

    [WEEKEND, NIGHT]

có thể bị coi là khác.

Trong khi về semantics hai cấu hình giống nhau.

Tương tự OT:

    ORDER BY period

vs list order.

Nên canonicalize trước compare.

* * *

10\. 🟠 P1/P2 — `renderJobSchedule()` persistence còn stale rows
================================================================

Đây là vấn đề mình đặc biệt chú ý.

`renderJobSchedule()`:

    effective occurrences
        ↓
    saveOccurrences()

`saveOccurrences()` chỉ:

    INSERT
    ON CONFLICT UPDATE

Nó **không xóa những occurrence cũ không còn xuất hiện trong effective schedule**.

### Ví dụ cực kỳ thực tế

Ban đầu:

    Sep 10 Day

DB có:

    occ-Sep10

User DELETE bằng override.

Render mới:

    Sep 10 = không có occurrence

nhưng `saveOccurrences()` không delete:

    occ-Sep10

→ database vẫn có row cũ.

Tương tự:

    pattern shift
    → import OFF

pattern occurrence cũ vẫn có thể tồn tại trong materialized `occurrences`.

Hiện UI phần lớn dùng render projection nên có thể **chưa lộ ngay**.

Nhưng một API khác đọc:

    occurrencesInRange()

có thể thấy shift đã bị DELETE.

Đây là **data consistency problem**.

### Cần quyết định rõ

Hoặc:

### Option A — occurrences là materialized cache

Mỗi render:

    delete rows belonging to render scope
    insert current effective rows

### Option B — occurrences là immutable historical records

thì không được dùng nó như cache và phải có rõ:

    effective schedule query

Hiện tại architecture đang hơi trộn hai semantics.

**Mình nghiêng về A cho MVP.**

* * *

11\. 🟠 P2 — Import diff tính giờ bằng local wall-clock, không phải UTC
=======================================================================

Trong:

`import_engine.dart`

`computeImportDiff()`:

    hoursOf(start,end)

đang tính bằng phút local.

Trong khi toàn project đã chốt:

> duration phải từ resolved UTC.

Nếu re-import xảy ra quanh DST:

    01:00 → 09:00

local wall-clock duration và elapsed duration có thể khác.

Đây chưa phải blocker của import commit, nhưng:

> **Impact "hours changed" có thể sai.**

M2b UI sau này nếu hiển thị:

    +8.0 hours

thì phải chính xác.

Nên để diff engine nhận timezone và resolve UTC.

* * *

12\. 🟠 P2 — `windowOverlapHours()` cần chốt semantics overnight
================================================================

Hiện implementation dùng wall-clock:

    22:00 → 06:00

và overlap.

Nhưng case:

    shift 01:00 → 05:00
    window 22:00 → 06:00

cần xác định rõ:

> Có tính 4h không?

Hiện algorithm có thể coi shift nằm ở:

    01:00 → 05:00

trong khi window là:

    22:00 → 30:00

→ không overlap.

Nếu business semantics là:

> mỗi ngày có một recurring night window 22:00–06:00

thì đây là sai.

Nếu spec cố tình định nghĩa window anchored từ shift date 00:00 thì code có thể đúng.

**Không nên tự sửa. Cần khóa semantics bằng test trước M3.**

* * *

13\. 🟠 UI bug: Pattern Builder tạo Controller mới trong mỗi build
==================================================================

Trong:

`pattern_builder_screen.dart`

có:

dart

    controller: TextEditingController(text: _name)

ngay trong `build()`.

Đây là anti-pattern:

    build
    → new controller
    → build
    → new controller
    → ...

Có thể gây:

*   mất cursor position
    
*   selection jump
    
*   controller leak
    
*   behavior khó đoán khi rebuild
    

Nên controller phải là State field:

    late TextEditingController _nameController

và dispose.

Không phải P1, nhưng nên sửa cùng batch UI hardening.

* * *

14\. 🟠 Today Screen có semantics "next 7 days" sai
===================================================

Today đang render:

    Monday → Sunday

của **tuần hiện tại**.

Nếu hôm nay là Sunday và không còn shift:

    upcoming = empty

UI:

> No shifts coming up in the next 7 days.

Nhưng thực tế nó chưa check Monday tuần sau.

Nên hoặc:

    No more shifts this week.

hoặc thực sự query:

    today → today + 7 days

P2.

* * *

15\. 🟠 `Today` chưa phải real-time countdown
=============================================

Current screen tính:

    DateTime.now()

trong `build()`.

Nhưng không có:

    Timer.periodic

nên nếu user mở màn hình:

    10:00
    Starts in 2h 00m

ngồi đó 30 phút:

    vẫn có thể hiển thị 2h 00m

cho tới khi widget rebuild.

Đối với Today screen, đây là UX bug.

Nên có ticker khoảng:

    30s / 60s

hoặc lifecycle-aware timer.

* * *

16\. 🔴 SQLCipher vẫn chưa production-ready
===========================================

`lib/core/db/db.dart` hiện:

    sqlite3.open(path)
    PRAGMA key = ...

Đây mới chỉ là **seam**.

`pubspec.yaml` vẫn chỉ:

    sqlite3
    timezone

không có SQLCipher native integration.

`main.dart` cũng:

    openDatabase(... defaultOpener ...)

không truyền key.

Vì vậy hiện tại:

> **DB local chưa được chứng minh encrypted.**

Đây không ngăn internal development.

Nhưng nếu app lưu:

*   work schedule
    
*   employer
    
*   salary/pay rules
    
*   personal events
    
*   sharing tokens
    

thì trước production release cần giải quyết.

* * *

17\. 🔴 Mobile app hiện chưa thực sự sẵn sàng publish
=====================================================

`pubspec.yaml` và source hiện tại cho thấy app vẫn đang ở mức desktop/CLI-oriented:

    dart:io
    HOME/.shiftease/shiftease.db

Trong khi roadmap cần:

    android/
    ios/
    path_provider

chưa có.

Để publish App Store / Google Play cần:

    platform database path
    app lifecycle
    backup policy
    permission model
    notifications
    secure storage
    SQLCipher

Ít nhất:

    path_provider

và platform-specific database location phải được làm.

* * *

18\. 🔴 Documentation vẫn chưa thực sự sạch
===========================================

Đây là điểm mình không đồng ý với handoff.

`checklist.md` nói:

    result13_gate_m2.txt

tồn tại.

Mình kiểm tra filesystem hiện tại:

    ls -l result13_gate_m2.txt result14_gate_a.txt

kết quả:

    result13_gate_m2.txt → No such file
    result14_gate_a.txt → exists

Trong khi:

*   `checklist.md` vẫn reference result13
    
*   `next.md` vẫn reference result13
    
*   handoff cũng reference result13
    

\=> **evidence registry chưa clean 100%.**

* * *

19\. `features.md` hiện cực kỳ stale
====================================

Đây là vấn đề còn rõ hơn.

`features.md` vẫn ghi:

    core/money → chưa code
    Import → chưa code
    UI → chưa code
    domain → chưa code

trong khi source thật đã có:

    money_engine.dart
    import_engine.dart
    ScheduleService
    SQLite repositories
    M1
    M1b
    M2

Thậm chí `features.md` vẫn nói:

    B5 UPDATE còn lỗi P3

trong khi UPDATE đã được implement.

Do đó:

> **Không thể coi `features.md` là current feature inventory.**

Handoff nói:

> `checklist.md / .plan/features.md / next.md` đồng bộ.

Nhưng root `features.md` vẫn tồn tại và rất dễ khiến AI agent sau này đọc nhầm.

Cần quyết định một canonical file.

Mình đề nghị:

    .plan/features.md = canonical

và root:

    features.md

hoặc update hoàn toàn, hoặc ghi:

    ARCHIVED — see .plan/features.md

* * *

20\. Một vấn đề quan trọng khác: Test suite chưa test đủ "bad paths"
====================================================================

179 tests là một con số tốt.

Nhưng coverage hiện tại thiên về:

    happy path
    regression
    golden
    major invariant

Trong khi các lỗi mình vừa tìm đều thuộc:

    forbidden transition
    partial failure
    conflicting identity
    stale materialization
    contradictory input
    cross-layer failure

Mình muốn thêm một test category:

Boundary / Adversarial Tests
----------------------------

    A. EXTRACTED → COMMIT
    B. COMMITTED → EXTRACTED
    C. same override ID + different payload
    D. close old pattern + new pattern write fails
    E. OFF + SHIFT same date
    F. duplicate imported occurrence
    G. deleted occurrence remains in DB
    H. imported occurrence replaced by pattern
    I. malformed referenceDate
    J. invalid PayRule
    K. unknown jobId
    L. duplicate PayRule children in different order
    M. DST import diff
    N. restart after partial failure

Đây sẽ có giá trị hơn việc chỉ tăng số test từ 179 lên 220.

* * *

21\. Các tính năng hiện tại còn thiếu để "xuất bản app"
=======================================================

Bây giờ tới phần mình nghĩ quan trọng nhất theo yêu cầu của bạn:

> **Nếu agent chỉ còn một batch lớn cuối cùng, nên code những gì?**

Mình không khuyên code Cloud/OCR/Sharing trước.

Mình sẽ đóng **MVP Release Candidate** trước.

* * *

22\. 🔥 Batch cuối mình đề xuất agent code
==========================================

PHASE R0 — Data Integrity Hardening
-----------------------------------

**Bắt buộc.**

### R0.1 Import state machine

    EXTRACTED → REVIEWING → COMMITTED

Không bypass.

### R0.2 Import conflict detection

Phát hiện:

    OFF + SHIFT same date
    duplicate date/shift conflict
    duplicate candidate identity

### R0.3 ImportSession immutability

Không cho rewrite COMMITTED audit.

### R0.4 Override immutable identity

Same ID:

    same payload → idempotent
    different payload → error

### R0.5 Roster re-version atomic

    BEGIN
     close old
     insert new
    COMMIT

### R0.6 Materialized occurrence consistency

Quyết định và implement:

    render → effective schedule is authoritative

không để stale rows đánh lừa DB readers.

### R0.7 Adversarial test suite

Đây là phần bắt buộc.

* * *

23\. 🔥 PHASE R1 — Pay/Income
=============================

Đây mới là feature lớn cuối cùng đáng làm.

Pay Rule
--------

User có thể:

    Job
     └── Pay Rules
          ├── $35/h
          ├── Night +10%
          ├── Weekend +$5/h
          ├── Shift OT > 8h ×1.5
          └── Week OT > 40h ×1.5

Versioned:

    Jan 1 → Sep 14
    Sep 15 → current

Không sửa lịch sử.

* * *

Income Dashboard
----------------

Ví dụ:

    THIS WEEK
    
    42h worked
    
    Regular
    34h × $35
    $1,190
    
    Night differential
    18h × $3.50
    $63
    
    Overtime
    8h × $52.50
    $420
    
    ────────────────
    Estimated
    $1,673

Luôn:

> Estimate — not official payroll.

* * *

Missing configuration
---------------------

Nếu chưa có:

    work week boundary
    OT rule
    base rate

không đoán.

Hiển thị:

> Unable to calculate accurately.

* * *

24\. 🔥 PHASE R2 — Calendar UX hoàn chỉnh
=========================================

Hiện Calendar usable nhưng còn khá "developer MVP".

Cần:

### Today

*   real-time countdown
    
*   current shift
    
*   next shift
    
*   rest time
    
*   week hours
    
*   income sau M3
    

### Week

*   edit
    
*   delete
    
*   create
    
*   quick add
    
*   DST handling
    
*   imported chip
    
*   conflict indicators
    

### Month

*   empty-day tap → Add Shift
    
*   shift count
    
*   colors
    
*   imported marker
    
*   conflict marker
    

### Shift Detail

Nên có:

    Sep 10
    Night
    19:00–07:00
    
    Source
    Imported roster
    
    Timezone
    America/New_York
    
    Duration
    12h
    
    Pay
    $420 estimated
    
    Why this shift?
    Imported from Sep 2026 roster

Đây sẽ là một UX rất mạnh.

* * *

25\. 🔥 PHASE R3 — DST UI
=========================

Engine đã có:

    NONEXISTENT_LOCAL_TIME
    AMBIGUOUS_LOCAL_TIME

thì UI phải hoàn thiện.

Spring:

> 02:30 does not exist on this date because clocks move forward.

Fall:

> 01:30 occurs twice.

    ○ First 01:30
    ○ Second 01:30

Không tự đoán.

Đây là một trong những feature correctness quan trọng nhất của ShiftEase.

* * *

26\. 🔥 PHASE R4 — Import hoàn chỉnh
====================================

M2 hiện mới là Smart Paste.

Nên làm:

### CSV Mapping

    Date → Column A
    Shift → Column B
    Start → Column C
    End → Column D

Preview trước commit.

### Re-import Diff

    Roster changed
    
    Added
    + Sep 14 Night
    
    Removed
    - Sep 16 Day
    
    Modified
    Sep 18
    Day → Night
    
    Impact
    +4h
    Estimated income +$140

Đây là feature có giá trị rất cao với target nurse/shift worker.

* * *

27\. 🔥 PHASE R5 — Reliability / Safety
=======================================

Trước release:

### Backup

Offline:

    Export backup
    Import backup

Ít nhất JSON/DB backup.

### Undo

Cho:

    DELETE
    UPDATE
    REPLACE
    SPLIT
    SWAP

Vì override log đã append-only thì Undo rất phù hợp:

    Undo
    → append inverse override

Không sửa lịch sử.

### Crash safety

Test:

    write
    crash
    restart

và:

    migration failure
    transaction failure
    partial import

* * *

28\. 🔥 PHASE R6 — Production mobile
====================================

Bắt buộc nếu mục tiêu App Store/Google Play:

    android/
    ios/
    path_provider
    secure local storage
    SQLCipher
    app lifecycle
    database close/reopen
    migration upgrade

Database:

    ApplicationSupportDirectory
        ↓
    shiftease.db

không:

    $HOME/.shiftease

* * *

29\. Notifications
==================

MVP nên có ít nhất:

    30 min before shift
    10 min before shift
    Shift starts

và:

    Night shift ending

có thể để optional.

Quan trọng:

> notification phải dựa trên UTC instant của occurrence.

Không dựa vào device timezone một cách ngây thơ.

* * *

30\. Settings — hiện đang thiếu rất nhiều
=========================================

Trước publish cần một Settings thực sự:

    Settings
    
    Jobs
    Templates
    Pay Rules
    
    Notifications
      ○ 30 min before
      ○ 60 min before
    
    Calendar
      First day of week
      12h / 24h
    
    Time
      Default timezone
    
    Data
      Backup
      Restore
      Export .ics
    
    Privacy
      Local data
      Encryption status
    
    About
      Version
      Privacy Policy
      Terms
      Support

* * *

31\. Các tính năng mình KHÔNG khuyên code trong batch cuối
==========================================================

Không nên để agent bị phân tán sang:

### ❌ OCR ngay

Chỉ làm:

    M4.5 spike

sau khi có 20–30 roster thật.

### ❌ Cloud

Chưa cần.

### ❌ AI health

Chưa cần.

### ❌ Partner sharing

Chưa cần.

### ❌ B2B

Chưa cần.

### ❌ Health AI

Chưa cần.

* * *

32\. Release MVP nên có những gì?
=================================

Mình sẽ định nghĩa **ShiftEase v1.0** như sau:

                        ShiftEase v1.0
                             │
            ┌────────────────┼────────────────┐
            │                │                │
           WORK             LIFE             MONEY
            │                │                │
       Patterns          Calendar         Pay Rules
       Templates         Today            Income
       Overrides         Week/Month       Breakdown
       Quick Add         Notifications    OT
       Import            Timezone         Differential
            │                │                │
            └────────────────┼────────────────┘
                             │
                     OFFLINE FIRST
                             │
                   SQLite + Encryption
                             │
                      Backup / Restore

* * *

33\. Release blocker matrix
===========================

| Hạng mục | Hiện tại | Release |
| --- | --- | --- |
| Time Engine | 🟢 tốt | OK |
| Pattern Engine | 🟢 tốt | OK sau preset fix |
| Import Engine | 🟡 | cần hardening |
| Persistence | 🟠 | **cần hardening** |
| Override audit | 🟠 | **cần hardening** |
| Money Engine | 🟢 core | cần UI/integration |
| Pay Rules UI | 🔴 thiếu | **bắt buộc** |
| Income UI | 🔴 thiếu | **bắt buộc** |
| DST UI | 🔴 thiếu | **bắt buộc** |
| CSV Mapping | 🔴 thiếu | nên có |
| Re-import Diff | 🔴 thiếu | nên có |
| Notifications | 🔴 thiếu | nên có |
| Backup/Restore | 🔴 thiếu | **nên có trước release** |
| Android/iOS | 🔴 thiếu | **bắt buộc nếu mobile** |
| SQLCipher | 🔴 chưa verify | **bắt buộc trước production** |
| Settings | 🔴 thiếu | **bắt buộc** |
| Privacy/Terms/Support | 🔴 thiếu | **store release** |

* * *

34\. Thứ tự mình chốt cho agent
===============================

Mình sẽ **không cho agent code M3 Pay ngay lập tức**. Batch cuối nên là:

    R0  DATA INTEGRITY
    │
    ├─ Import state machine
    ├─ Import conflicts
    ├─ ImportSession immutable
    ├─ Override immutable
    ├─ Atomic roster version
    ├─ Effective occurrence persistence
    └─ Adversarial tests
            │
            ▼
    R1  PAY / INCOME
    │
    ├─ PayRule editor
    ├─ PayRule versioning
    ├─ Template library
    ├─ Money ↔ Schedule integration
    ├─ Income dashboard
    └─ Missing-config handling
            │
            ▼
    R2  CALENDAR / UX
    │
    ├─ DST dialog
    ├─ real-time Today
    ├─ better Month/Week
    ├─ Shift Detail
    └─ conflict indicators
            │
            ▼
    R3  IMPORT UX
    │
    ├─ CSV mapping
    └─ Re-import diff
            │
            ▼
    R4  RELIABILITY
    │
    ├─ Backup / Restore
    ├─ Undo
    └─ crash/restart/migration tests
            │
            ▼
    R5  MOBILE RELEASE
    │
    ├─ Android
    ├─ iOS
    ├─ path_provider
    ├─ SQLCipher
    ├─ notifications
    ├─ Settings
    └─ privacy / terms / support
            │
            ▼
           RC
            │
            ▼
       FINAL REVIEW

* * *

35\. Một việc nữa mình rất khuyến nghị: đừng để agent tự quyết scope lần nữa
============================================================================

Sau review này, mình nghĩ **đã đến lúc khóa release scope**.

Nếu cứ tiếp tục:

    agent code
    → result
    → thêm feature
    → review
    → phát hiện persistence issue
    → agent sửa
    → feature mới

thì project sẽ kéo dài vô hạn.

Mình khuyên batch tiếp theo phải được coi là:

> **Release Candidate Batch — không mở thêm feature ngoài danh sách.**

Và sau batch đó mình sẽ review theo 5 trục:

    1. Correctness
    2. Data integrity
    3. Crash / recovery
    4. UX completeness
    5. Store readiness

* * *

Verdict cuối cùng của mình
--------------------------

**ShiftEase hiện đã vượt qua giai đoạn "proof of concept".** Core Time/Pattern/Import/Persistence đã có nền khá nghiêm túc, và 179 tests là một nền tốt.

Nhưng **chưa được publish**.

Có **5 việc mình coi là phải sửa trước khi đi xa hơn**:

1.  🔴 `EXTRACTED → COMMIT` phải bị chặn ở core.
    
2.  🔴 `changeRosterFrom()` phải atomic.
    
3.  🔴 Override cùng ID nhưng payload khác phải reject, không silent-ignore.
    
4.  🔴 Không để materialized `occurrences` stale sau DELETE/import suppression.
    
5.  🔴 Fix `2-2-3` preset.
    

Sau đó mới nên làm **một batch cuối gồm Pay/Income + DST UI + Import CSV/Diff + reliability + mobile/security + Settings**, rồi đóng **Release Candidate**.

Và có một điểm mình muốn agent sửa ngay trong hồ sơ: **`features.md` hiện không còn là tài liệu trạng thái đáng tin cậy**, còn `result13_gate_m2.txt` đang được reference dù file không tồn tại. Đây không phải lỗi app runtime, nhưng nếu tiếp tục dùng AI agent thì nó là nguồn gây sai lệch kế hoạch rất dễ xảy ra.