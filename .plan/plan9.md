Agent đang code xong, bạn cần review đánh giá lại toàn bộ. Đọc những file sau để biết những gì đã thay đổi:

- checklist.md
- features.md
- result*.txt (mới nhất)
- next.md

> Xem tính năng đã code có lỗ hổng không như: sai logic, khi sử dụng có thể mất mát dữ liệu, crash bug...
> Tính năng đã đầy đủ để xuất bản app chưa, nếu chưa gợi ý đầy đủ tính năng hữu ích một lần cuối để cho agent code một thể rồi review.

Toàn bộ files+code của project tại /Users/hoang/htdocs_apps/ShiftEase.

Đọc handoff_20260907_093210.md
duyệt plan m3  .plan/plan8_m3_income.md
Show more
--------------------
Mình đã đọc lại **source hiện tại trên `/Users/hoang/htdocs_apps/ShiftEase`**, cùng:

*   `checklist.md`
    
*   `features.md`
    
*   `next.md`
    
*   `result15_gate_c.txt`
    
*   `handoff_20260907_093210.md`
    
*   `.plan/plan8_m3_income.md`
    
*   và kiểm tra trực tiếp các phần quan trọng trong `lib/core`, `lib/domain`, `lib/features`, `pubspec.yaml`, Android/iOS.
    

Mình **không tin hoàn toàn vào claim 207/207** mà đối chiếu lại logic source. Kết luận có vài điểm quan trọng.

* * *

1\. Verdict tổng thể
====================

### Hiện tại: **chưa nên publish**

Nhưng khác với giai đoạn trước, project đã đi khá xa:

| Khu vực | Đánh giá |
| --- | --- |
| Time/DST engine | 🟢 Rất tốt |
| Pattern/versioning | 🟢 Tốt |
| Import architecture | 🟢 Tốt |
| DB transaction/integrity | 🟢 Đã harden đáng kể |
| Override append-only | 🟢 Tốt |
| Basic Pay engine | 🟢 Khá tốt |
| Basic Income | 🟡 Mới ở mức baseline |
| Calendar UX | 🟡 MVP |
| Notification | 🟡 Baseline, chưa production |
| Backup/restore | 🔴 Thiếu |
| Security/encryption | 🔴 Chưa production |
| Mobile release | 🔴 Chưa verify |
| Import-only roster workflow | 🔴 Có gap |
| Error handling UI | 🟡 Còn crash path |
| M3 Income | ⏳ Chưa làm |
| CSV/re-import diff | ⏳ Chưa làm |

**207/207 pass là tín hiệu rất tốt, nhưng không đồng nghĩa production-ready.**

Đặc biệt mình phát hiện một số vấn đề mà `result15_gate_c.txt` chưa bắt được.

* * *

2\. Những lỗi cần sửa trước M3
==============================

🔴 P1 — `updateShift/delete/replace/create` vẫn có đường crash UI
-----------------------------------------------------------------

Trong:

`lib/features/occurrence/override_actions.dart`

các hàm như:

    updateShift()
    replaceShiftTemplate()
    deleteShift()
    createShiftOnDate()

gọi:

    service.applyOverride(...)

nhưng **không catch exception**.

Trong khi persistence layer có thể throw:

*   `ImmutableHistoryError`
    
*   SQLite exception
    
*   constraint violation
    
*   malformed data
    
*   transaction/database failure
    

Ví dụ:

    service.applyOverride(...)
    return null;

Nếu DB throw → exception chạy thẳng lên widget event handler.

`OccurrenceSheet` chỉ xử lý:

    final error = updateShift(...)
    if (error != null) ...

nhưng exception không được chuyển thành `error`.

### Hậu quả

Người dùng bấm **Update/Delete/Replace** → DB lỗi → app có thể crash/unhandled exception.

Không phải đường xảy ra thường xuyên, nhưng production app **không được có write path không được handle**.

### Cần sửa

Domain/service nên có boundary rõ:

    try
      persist
      return success
    catch
      return typed/domain error

hoặc UI bắt exception tại một boundary duy nhất.

**Không nên bắt `Exception` rồi nuốt.**

* * *

3\. 🔴 P1 — Import-only roster vẫn không thể Add Shift
======================================================

Đây là gap đáng chú ý.

`createShiftOnDate()`:

    final patterns = service.patterns(jobId);
    final pattern = patterns.where((p) => p.isActiveOn(date)).firstOrNull;
    
    if (pattern == null) {
      return 'No active pattern for $date — cannot attach a CREATE.';
    }

Nhưng M2 đã thiết kế:

> imported roster là authoritative schedule.

Điều này có nghĩa user có thể:

    Import roster
          ↓
    COMMIT
          ↓
    Calendar có ca

nhưng nếu job **chỉ có imported roster, không có pattern**, user không thể:

> Add một ca thủ công vào ngày đó.

Đây là một inconsistency giữa architecture M2 và M1.

### Ví dụ thực tế

User chưa tạo pattern.

Import roster bệnh viện tháng 9.

Ngày 15 bệnh viện đổi ca.

User muốn:

> *   Add shift 15/09
>     

→ `No active pattern`.

### Cần quyết định

CREATE phải attach được vào:

1.  active pattern **hoặc**
    
2.  imported roster / imported occurrence context.
    

Mình đánh giá đây là **P1 functional gap**, không chỉ UX.

* * *

4\. 🔴 P1 — Notification có thể để lại reminder cũ
==================================================

`shift_reminder.dart` đã sửa một bug tốt:

    _reminderId = 1001

nên reschedule không tạo hàng loạt notification.

Nhưng:

    syncFromOccurrences()

làm:

    final spec = nextReminderSpec(...);
    
    if (spec == null) return;

Nếu trước đó có reminder:

    Shift A → reminder scheduled

sau đó roster bị sửa:

    Shift A bị DELETE
    không còn upcoming shift

`spec == null`

→ function **return**

→ notification cũ vẫn có thể tồn tại.

Tương tự nếu user thay đổi lịch khiến reminder cũ không còn hợp lệ.

### Production bug

User xóa ca 8:00.

Nhưng 7:00 sáng hôm sau vẫn nhận:

> Shift starting soon

### Cần

Có:

    cancelReminder()

và:

    if spec == null:
        cancel(_reminderId)

Đồng thời sync reminder sau:

*   override
    
*   import commit
    
*   roster re-version
    
*   app resume
    

* * *

5\. 🔴 P1 — Android notification permission chưa hoàn chỉnh
===========================================================

Trong `shift_reminder.dart`, permission hiện tại chủ yếu request:

    IOSFlutterLocalNotificationsPlugin

nhưng Android 13+ cần runtime notification permission.

Hiện tại B4 mới thực sự là:

> baseline scheduling

chưa phải:

> production notification flow.

`result15` cũng thừa nhận:

> exact alarm permissions/OS UI flow deferred.

Điều này **không thể coi là done nếu publish Android**.

Cần:

*   Android 13+ POST\_NOTIFICATIONS permission
    
*   permission denied state
    
*   permanently denied state
    
*   Settings fallback
    
*   notification channel
    
*   notification initialization
    
*   reschedule after reboot/app update nếu cần
    
*   test trên real Android
    

* * *

6\. 🔴 P1 — SQLCipher vẫn chưa tồn tại
======================================

Đây vẫn là blocker lớn.

`db.dart`:

    final db = sqlite3.open(path);

và:

    PRAGMA key = '$key'

**không biến SQLite thường thành SQLCipher.**

Source comment cũng nói rất rõ đây chỉ là seam:

> caller chooses an opener matching its platform

Nhưng `main.dart`:

    openDatabase(
      opener: defaultOpener,
      path: defaultDbPath()
    )

không truyền key.

Vậy DB production hiện tại vẫn là plain SQLite.

### Nếu app chứa:

*   lịch làm việc
    
*   thu nhập
    
*   job information
    
*   personal events sau này
    

thì đây là vấn đề security/privacy.

### Verdict

**Không claim G7/Data encryption đã hoàn thành.**

Cần một production task riêng:

> SQLCipher native integration + key storage + migration/open verification + Android/iOS test.

* * *

7\. 🔴 P1 — Backup/Restore vẫn thiếu
====================================

Hiện tại app local-first nhưng:

    database = local SQLite

và chưa có:

*   backup
    
*   restore
    
*   export full data
    
*   import backup
    
*   corruption recovery
    
*   migration-aware restore
    

Đây là một rủi ro **data loss thực tế**.

Ví dụ:

> update app lỗi / user xóa app / device mất dữ liệu

→ toàn bộ lịch + pay rules + overrides mất.

ICS export **không thay thế backup**.

ICS chỉ backup calendar projection, không backup:

*   patterns
    
*   overrides
    
*   pay rules
    
*   import sessions
    
*   historical data
    
*   app configuration.
    

* * *

8\. 🟠 P2 — Materialized `occurrences` vẫn có nguy cơ stale
===========================================================

Đây là vấn đề mình vẫn giữ sau lần review trước.

`saveOccurrences()` chỉ:

    INSERT ... ON CONFLICT(id) DO UPDATE

Nó **không xóa occurrence cũ không còn nằm trong projection mới**.

Ví dụ:

    Ngày 10:
    Pattern → Night shift

render → DB có occurrence.

Sau đó:

    DELETE override

render mới:

    Ngày 10 = empty

`saveOccurrences([])` không xóa row cũ.

Vì vậy:

    renderJobSchedule()

có thể trả đúng,

nhưng:

    occurrencesInRange()

có thể vẫn nhìn thấy stale row.

Hiện tại một số UI dùng render projection nên chưa lộ.

### Cần quyết định rõ

Nếu `occurrences` là:

> materialized cache

thì mỗi render scope phải **replace transactionally**.

Nếu là:

> historical record

thì không được coi nó là projection cache.

Hiện architecture đang hơi trộn hai semantics.

Mình khuyến nghị:

> `occurrences` = materialized effective-schedule cache  
> historical truth = patterns + overrides + import sessions.

Khi đó render scoped nên replace projection scoped.

* * *

9\. 🟠 P2 — DST dialog hiện tại an toàn nhưng chưa thực sự "resolve"
====================================================================

Đây là điểm rất quan trọng.

UI nói:

> AMBIGUOUS → hiện 2 candidate để user chọn.

Nhưng implementation thực tế lại:

    selectedIndex = null

và:

> acknowledging still refuses write.

Tức là:

    Fall-back 01:30
            ↓
    2 possibilities
            ↓
    user sees them
            ↓
    cannot choose one
            ↓
    must change time

Điều này **an toàn**, nhưng không đúng hoàn toàn với feature spec ban đầu:

> user chọn EDT hoặc EST.

### Có 2 lựa chọn

**A. Giữ như hiện tại**

Đổi wording:

> "This time is ambiguous. Please choose another time."

→ coi DST dialog là validation blocker.

**B. Tốt hơn**

Cho user:

    01:30 EDT
    01:30 EST

chọn một.

Sau đó lưu resolution/offset tương ứng.

Mình nghiêng **B** nếu muốn gọi feature là DST resolution thật sự.

* * *

10\. 🟠 P2 — `PayRuleEditDialog` vẫn có silent invalid input
============================================================

Đây là một điểm Gate C đã fix một phần nhưng chưa hết.

Base:

    numOf()

có validation.

Nhưng:

    final night = double.tryParse(...) ?? 0;
    final weekend = double.tryParse(...) ?? 0;

Nếu user nhập:

    night = abc

→ biến thành:

    0

Nếu nhập giá trị âm:

    -20

thì vẫn có khả năng bị xử lý như:

    if (night > 0)

→ âm bị silently bỏ.

Tương tự OT threshold:

    final otT = double.tryParse(...)

invalid → **không tạo OT rule**.

Trong khi Correctness Contract nói:

> Không silent đưa ra kết quả khi input/rule không đủ.

Đây là P2 nhưng nên sửa trong M3.

* * *

11\. 🔴 P1/P2 — Income estimator hiện tại chưa đủ parity với Money Engine
=========================================================================

Đây là lý do mình **không approve Plan8 nguyên bản**.

Trong:

`lib/domain/income_estimate.dart`

hiện:

    isNightShift: _isNightShift(o)

và `_isNightShift()` dùng:

    19:00 → 06:00

Nhưng Money Engine hỗ trợ:

    DifferentialScope.hoursInWindow

và cần:

    shiftStartLocal
    shiftEndLocal

Estimator **không truyền hai field này**.

Vì vậy một PayRule:

    Night differential:
    22:00 → 06:00

có thể tính sai hoặc mất differential.

Chính `plan8` đã phát hiện điều này.

### Đây là finding rất quan trọng:

**Plan8 T1 là bắt buộc, không phải enhancement.**

* * *

12\. 🔴 P1 — Plan8 đang có một quyết định thiết kế nguy hiểm về PayRule version
===============================================================================

Plan8 đề xuất:

> phân đoạn theo version + chỉ phân đoạn theo ranh giới tuần, trong tuần dùng rule active ngày đầu tuần.

Mình **không approve câu này**.

Ví dụ:

    Monday–Sunday

PayRule:

    Mon–Wed = $30
    Thu–Sun = $35

Nếu lấy rule của Monday cho cả tuần:

    Thu–Sun bị tính $30

→ **sai tiền**.

Không thể gọi đây là Correctness Contract.

### Mình đề xuất thay D-M3-1 thành:

**Rule active phải được resolve theo từng occurrence.**

Sau đó:

    Calendar week
     ├── occurrence 1 → Rule A
     ├── occurrence 2 → Rule A
     ├── occurrence 3 → Rule B
     └── occurrence 4 → Rule B

OT weekly cần có semantics rõ ràng.

Nếu một tuần có nhiều PayRule version:

### An toàn nhất cho MVP:

    Regular/differential:
        tính theo rule của từng occurrence
    
    Weekly OT:
        nếu một tuần chứa >1 PayRule version
            → UNAVAILABLE
            → giải thích rõ lý do

Sau này mới implement payroll-grade prorating.

**Đừng lấy rule ngày đầu tuần cho cả tuần.**

* * *

13\. Plan8 M3: mình CHƯA duyệt nguyên bản
=========================================

Sau khi đọc source thật, mình đánh giá:

### T1 — Estimator parity

🟢 **Approve**

Nhưng phải bổ sung:

*   `HOURS_IN_WINDOW`
    
*   DST-aware local window
    
*   DAY OT
    
*   SHIFT OT
    
*   WEEK OT
    
*   multiple weeks
    
*   multiple PayRule versions
    
*   zero-hour
    
*   overnight
    
*   DST week.
    

* * *

### T2 — Income breakdown

🟢 **Approve**

Nên có:

    Regular
    Night differential
    Weekend differential
    Holiday
    OT
    Total
    Hours

và mỗi line phải trace được về calculation.

* * *

### T3 — Template library

🟢 **Approve**, nhưng cần cực kỳ cẩn thận:

**Template không được ngầm khẳng định legal payroll rules.**

Ví dụ:

> US-CA Nurse

nên hiển thị:

> Preset / starting point — verify with your employer/payroll policy.

Không nên marketing:

> California payroll rule = ...

vì luật lao động/payroll thực tế phức tạp.

* * *

### T4 — Income Impact

🟢 **Approve**

Đây là feature rất có giá trị.

Nhưng phải đảm bảo:

    old schedule
        ↓
    old estimate
    
    new schedule
        ↓
    new estimate
    
    difference

và **không persist snapshot chỉ vì preview**.

Plan8 đã đi đúng hướng ở điểm này.

* * *

### T5 — Weekly strip + multi-job

🟡 **Approve có sửa**

Multi-job total cần cực kỳ rõ:

    Job A     $1,200
    Job B       $800
    ----------------
    Available $2,000

Nếu Job C không có rule:

    Job C     Unable to calculate

Không được:

    Job C = $0

Điểm này Plan8 đang hiểu đúng.

* * *

14\. Có một vấn đề lớn hơn: M3 chưa phải "Income Dashboard hoàn chỉnh"
======================================================================

Nếu agent chỉ làm đúng Plan8 hiện tại thì vẫn còn thiếu vài thứ mình muốn đưa vào **final batch**.

* * *

15\. Final Batch mình đề xuất cho agent
=======================================

Mình khuyên **không tiếp tục chia thành M3 → M3b → M3c → M3d vô tận**.

Hãy cho agent làm **Release Candidate Batch** cuối.

RC-1 — Data integrity
---------------------

### Bắt buộc

*    write boundary không crash
    
*    override exception handling
    
*    stale occurrence projection fix
    
*    imported-only roster CREATE
    
*    notification stale cancellation
    
*    ImportSession state transition đầy đủ
    
*    PayRule input validation
    
*    database corruption/error handling
    
*    migration failure handling
    
*    adversarial tests.
    

* * *

16\. RC-2 — M3 Income
=====================

### Income Dashboard

    Income
     ├── Today
     ├── This week
     ├── This month
     ├── Custom range
     └── By job

Breakdown:

    Regular          $840
    Night differential $90
    Weekend            $60
    Overtime          $315
    ----------------------
    Estimated Total  $1,305

Luôn:

> **Ước tính — không phải bảng lương chính thức**

* * *

17\. RC-3 — PayRule Template Library
====================================

Seed:

*   US-CA
    
*   US-NY
    
*   US-TX
    
*   UK NHS
    
*   DE
    

Nhưng:

*   không auto-save
    
*   user review
    
*   user sửa
    
*   explicit confirmation
    
*   disclaimer rằng đây là preset.
    

* * *

18\. RC-4 — Income Impact
=========================

Khi:

### Change roster

    Estimated weekly income
    
    Before     $1,505
    After      $1,330
    ----------------
    Impact      -$175

### Override

    Change Night → Day
    
    This week:
    $1,505 → $1,435
    Impact: -$70

Đây là một trong những feature có giá trị UX cao nhất của app.

* * *

19\. RC-5 — M2b CSV + Re-import Diff
====================================

Mình nghĩ đây **quan trọng hơn OCR**.

Flow:

    CSV
     ↓
    Map columns
     ↓
    Preview
     ↓
    Compare existing roster
     ↓
    Added
    Removed
    Modified
    Unchanged
     ↓
    Income impact
     ↓
    Review
     ↓
    Commit

Ví dụ:

    3 shifts added
    2 shifts changed
    1 shift removed
    
    Hours: +8h
    Estimated income: +$280

Đây mới thực sự biến import thành killer feature.

* * *

20\. RC-6 — Backup / Restore
============================

Đây là feature mình nâng mức ưu tiên lên.

### Export backup

    ShiftEase Backup
        ↓
    encrypted archive
        ↓
    patterns
    templates
    overrides
    pay rules
    imports
    settings

### Restore

Phải có:

    Preview
    ↓
    Backup created at...
    ↓
    Restore
    ↓
    Validate schema
    ↓
    Transaction
    ↓
    Success

Không overwrite database trực tiếp trước khi validate.

* * *

21\. RC-7 — Production Security
===============================

Trước publish:

*    SQLCipher thật
    
*    key không hardcode
    
*    secure key storage
    
*    Android/iOS verification
    
*    migration test encrypted DB
    
*    backup encryption
    
*    no plaintext sensitive backup.
    

* * *

22\. RC-8 — Mobile production
=============================

Phải test thật:

### Android

*    install
    
*    upgrade
    
*    fresh DB
    
*    existing DB migration
    
*    notification permission
    
*    notification after reboot
    
*    timezone change
    
*    DST
    
*    background
    
*    force kill
    
*    restore backup
    

### iOS

Tương tự.

**207 unit/widget tests không thay thế được nhóm này.**

* * *

23\. RC-9 — App lifecycle
=========================

Hiện `TodayScreen` chỉ schedule reminder trong `initState`.

Comment trong source đã thừa nhận limitation.

Production nên có:

    App resumed
          ↓
    reload schedule
          ↓
    recalculate next reminder
          ↓
    cancel old
          ↓
    schedule new

Đặc biệt sau:

*   import
    
*   edit shift
    
*   delete shift
    
*   roster change
    
*   timezone change
    
*   app resume.
    

* * *

24\. RC-10 — Settings tối thiểu
===============================

Hiện Settings gần như chưa có.

Trước publish nên có:

    Settings
    
    General
     ├── Default timezone
     ├── Week starts on
     └── Time format
    
    Notifications
     ├── Shift reminder
     ├── Reminder lead time
     └── Permission status
    
    Data
     ├── Backup
     ├── Restore
     ├── Export ICS
     └── Delete all data
    
    Privacy
     ├── Local data
     └── Encryption status
    
    About
     ├── Version
     ├── Privacy Policy
     ├── Terms
     └── Support

* * *

25\. Những thứ KHÔNG nên nhét vào final batch
=============================================

Mình **không khuyến nghị** agent làm ngay:

*   OCR
    
*   Cloud sync
    
*   AI
    
*   Health AI
    
*   B2B
    
*   Partner sharing
    
*   Webcal server
    
*   complicated social features.
    

Lý do rất đơn giản:

> Core calendar → import → pay → backup → mobile reliability vẫn chưa đạt RC.

Đừng mở thêm attack surface.

* * *

26\. Một vấn đề documentation cần sửa ngay
==========================================

`features.md` root hiện vẫn là **snapshot cũ**, mặc dù `checklist.md` mới hơn.

Nó vẫn ghi:

    core/money chưa code
    Import pipeline chưa code
    UI chưa code

trong khi source hiện tại đã có.

Đây là **documentation integrity bug**.

AI agent tiếp theo rất dễ đọc:

    features.md

rồi hiểu sai trạng thái project.

### Nên làm

Chỉ giữ **một canonical feature status**.

Ví dụ:

    .project/features.md

hoặc:

    features.md

và những file cũ phải ghi:

    ARCHIVED — historical snapshot

* * *

27\. `result13_gate_m2.txt` vẫn là discrepancy
==============================================

`checklist.md` vẫn nói:

> result13\_gate\_m2.txt trên đĩa

nhưng lần kiểm tra trước file này không tồn tại; hiện root cũng không thấy nó trong listing.

Trong khi:

    result14
    result15

có thật.

Đây là lỗi nhỏ nhưng phản ánh **evidence registry chưa sạch**.

Không nên để agent sau này dựa vào evidence file không tồn tại.

* * *

28\. Test suite cần thêm một vòng "production adversarial"
==========================================================

207 test hiện tại rất tốt nhưng mình muốn thêm tối thiểu:

### DB

*   crash giữa transaction
    
*   migration from v1
    
*   migration from v2
    
*   malformed migration state
    
*   duplicate IDs
    
*   stale occurrence cleanup
    

### Import

*   EXTRACTED → COMMIT
    
*   REVIEWING → COMMIT
    
*   zero approved
    
*   OFF + SHIFT same day
    
*   duplicate candidate
    
*   empty import
    
*   re-import empty window
    
*   import-only job
    

### Override

*   same ID same payload
    
*   same ID different payload
    
*   chained CREATE → UPDATE
    
*   CREATE → DELETE
    
*   imported occurrence → UPDATE
    
*   imported occurrence → DELETE
    

### Pay

*   DST spring
    
*   DST fall
    
*   overnight differential
    
*   window differential
    
*   DAY OT
    
*   SHIFT OT
    
*   WEEK OT
    
*   multiple rule versions
    
*   multiple weeks
    
*   missing rule
    
*   malformed rule
    

### UI

*   DB exception
    
*   notification denied
    
*   empty job
    
*   empty template
    
*   deleted occurrence
    
*   imported-only schedule.
    

* * *

29\. Đánh giá Plan8 cuối cùng
=============================

**Không approve nguyên bản.**
-----------------------------

Nhưng mình **approve để agent triển khai sau khi sửa spec**.

### Các quyết định mình chốt:

| Plan8 | Verdict |
| --- | --- |
| T1 estimator parity | ✅ Bắt buộc |
| T2 breakdown | ✅ |
| T3 template library | ✅ |
| T4 income impact | ✅ |
| T5 weekly strip | ✅ |
| Multi-job total | ✅ có điều kiện |
| Version change giữa tuần | ❌ Không dùng rule ngày đầu tuần |
| Window differential | ✅ phải dùng engine thật |
| Monthly calculation | ✅ |
| Tax/net pay | ❌ |
| OCR | ❌ |
| Cloud | ❌ |

### Quan trọng nhất:

**Không được triển khai quy tắc:**

> "trong tuần dùng PayRule active ngày đầu tuần".

Thay bằng:

> **PayRule được resolve theo từng occurrence. Weekly OT chỉ được tính khi semantics của toàn bộ tuần là xác định được; nếu nhiều PayRule version trong cùng payroll week mà chưa có semantics phân bổ được chứng minh bằng test, trả UNAVAILABLE thay vì đoán.**

Điều này phù hợp hoàn toàn với Correctness Contract:

> **Không biết → báo không tính được, không tính sai.**

* * *

30\. Verdict cuối cùng cho ShiftEase
====================================

Mình chấm trạng thái hiện tại khoảng:

**8.2/10 về architecture/core**  
**6.5/10 về production readiness**

Không phải vì code tệ — ngược lại, **core hiện tại khá chắc**. Vấn đề là app đang ở trạng thái:

> **Strong technical MVP / Release Candidate candidate**

chứ chưa phải:

> **Store-ready production app**.

### Những blocker mình muốn agent xử lý trước khi publish:

**P0/P1**

1.  🔴 Error boundary cho toàn bộ write UI
    
2.  🔴 Imported-only roster phải hỗ trợ CREATE
    
3.  🔴 Notification phải cancel stale reminder
    
4.  🔴 Android notification permission
    
5.  🔴 SQLCipher thật + secure key
    
6.  🔴 Backup/restore
    
7.  🔴 Income estimator parity với Money Engine
    
8.  🔴 PayRule version semantics không được lấy rule ngày đầu tuần
    
9.  🔴 M3 Income Dashboard
    
10.  🔴 CSV + re-import diff
     
11.  🔴 Mobile real-device verification
     
12.  🔴 App lifecycle/resume synchronization
     

**P2 nhưng nên làm cùng batch:**

13.  🟠 stale occurrence projection
     
14.  🟠 DST ambiguous selection hoặc sửa wording/spec cho đúng
     
15.  🟠 PayRule input validation
     
16.  🟠 Settings
     
17.  🟠 privacy/terms/support/about
     
18.  🟠 documentation/evidence cleanup
     
19.  🟠 production adversarial tests
     

* * *

Và mình khuyên **chưa cho agent code Plan8 ngay**
-------------------------------------------------

Thay vào đó, hãy sửa `.plan/plan8_m3_income.md` thành **Plan8 RC/M3 final** với các điều chỉnh trên, đặc biệt là **PayRule-version semantics + estimator parity + imported-only roster + backup/security/error handling**.

Sau đó cho agent **code một batch cuối**, chạy full suite, device test, rồi mình review **lần cuối trước closed testing/store**.

Nếu mục tiêu của bạn là **"code một thể rồi mình review lần cuối"**, thì đây là thời điểm rất phù hợp để khóa scope — **đừng mở OCR/Cloud/AI nữa**.