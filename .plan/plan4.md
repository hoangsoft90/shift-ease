agent đang tự làm thêm, bạn cần review đánh giá lại toàn bộ. Đọc những file sau để biết những gì đã thay đổi:

checklist.md
features.md
result*.txt (mới nhất)
next.md

Toàn bộ files+code của project tại /Users/hoang/htdocs_apps/ShiftEase.
--------------------
Mình đã review lại **trạng thái hiện tại trên disk**, không lấy `features.md/result*.txt` làm nguồn sự thật duy nhất. Mình đối chiếu ngược lại với code thật trong `lib/` và test.

Kết luận nhanh
--------------

**ShiftEase đã tiến khá xa so với lần review trước, đặc biệt Time Engine + Pattern + Money + Import + SQLite + M1/M1b/M2. Nhưng hiện tại mình chưa duyệt trạng thái “production-ready”.**

Có một vấn đề rất đáng chú ý:

> **Agent báo M2 đã xong, nhưng code M2 hiện chưa được wire vào production entrypoint.**

Ngoài ra mình phát hiện một số vấn đề persistence/import mà test hiện tại chưa bắt được.

* * *

1\. Trước tiên: hồ sơ trạng thái đang bị lệch nhau
==================================================

Đây là việc mình đánh giá khá nghiêm trọng về quy trình.

### `checklist.md` nói

*   Core = **157**
    
*   Domain = 3
    
*   UI = 10
    
*   Tổng = **170**
    
*   Schema = **v3**
    
*   M2 đã hoàn tất
    
*   Có `result13_gate_m2.txt`
    

### Nhưng `features.md` lại nói

*   Time = 24 tests
    
*   Pattern = 31 engine + 5 property + 4 integration
    
*   Tổng core theo các phần cũ
    
*   M2 chưa hoàn toàn phản ánh trạng thái mới.
    

### `next.md` lại nói

> core Gates 0–3 = **155/155**

và vẫn mô tả M1/M2 theo trạng thái cũ.

### Quan trọng hơn

Mình kiểm tra filesystem hiện tại:

*   `result11_gate_m1.txt` tồn tại
    
*   `result12_m1b.txt` tồn tại
    
*   `result10_review_round2.txt` tồn tại
    
*   `result9_gate3.txt` tồn tại
    
*   **`result13_gate_m2.txt` KHÔNG tồn tại**
    
*   `git status` cũng không cho thấy file này.
    

Trong khi `checklist.md` ghi:

> `result13_gate_m2.txt` — report mới nhất

\=> **Không thể coi checklist là bằng chứng M2 đã hoàn tất.**

Đây đúng kiểu vấn đề mà trước đây project đã từng gặp: report nói file tồn tại nhưng filesystem không có.

### Verdict

**P1 — Documentation / verification integrity**

Trước khi mở gate tiếp theo, phải đồng bộ:

    actual filesystem
        ↓
    actual test count
        ↓
    actual source
        ↓
    result report
        ↓
    features.md
        ↓
    checklist.md
        ↓
    next.md

Không được để 3 nguồn trạng thái khác nhau.

* * *

2\. Time Engine hiện tại: tốt hơn rất nhiều
===========================================

Mình đã đọc lại `lib/core/time/time_engine.dart`.

Những vấn đề mình bắt trước đây đã được xử lý khá đúng:

### Đã fix

*   strict date validation
    
*   `2026-02-31` không còn rollover thành March
    
*   strict `HH:mm`
    
*   INVALID\_DATE / INVALID\_TIME tách khỏi DST
    
*   không còn heuristic ±1h
    
*   không dùng `offset.inHours`
    
*   enumerate candidate UTC từ timezone transition table
    
*   Lord Howe 30-minute DST có khả năng xử lý đúng
    
*   duration vẫn tính từ UTC
    
*   ambiguous time không tự chọn
    
*   nonexistent time không tự sửa
    
*   overnight xử lý ở Time Engine
    

Đây là một bước **harden thực sự**, không chỉ thêm test.

Đặc biệt đoạn:

    candidate = naiveMs - zone.offset
    lookupTimeZone(candidate)

là hướng đúng hơn rất nhiều so với heuristic cũ.

### Verdict

**Time Engine: khoảng 8.5–9/10 ở tầng core.**

Nhưng UI DST dialog vẫn chưa có, nên end-to-end chưa hoàn chỉnh.

* * *

3\. Pattern Engine: các bug lớn trước đây đã được xử lý
=======================================================

`pattern_engine.dart` hiện tại đã:

*   không tạo occurrence với UTC rỗng
    
*   CREATE resolve UTC
    
*   UPDATE có thể thay start/end
    
*   REPLACE resolve lại khi civil time thay đổi
    
*   SPLIT atomic
    
*   SPLIT check envelope
    
*   SWAP resolve lại local civil time
    
*   chain override
    
*   duplicate ID detection
    
*   pattern version giữ anchor
    
*   không mutate pattern.
    

Đặc biệt đây là điểm tốt:

> UPDATE không re-resolve nếu civil time không thay đổi.

Điều này quan trọng với ambiguous DST occurrence.

Nếu occurrence trước đó đã được user chọn một trong hai instant của fall-back, việc render lại không được tự nhiên biến nó thành ambiguous lần nữa.

### Verdict

**Pattern core hiện tại: tốt.**

Nhưng vẫn còn một số vấn đề persistence bên dưới.

* * *

4\. P1 — M2 UI đã code nhưng production app hiện KHÔNG bật Import
=================================================================

Đây là finding quan trọng nhất.

Trong `lib/features/jobs/job_detail_screen.dart`:

dart

    if (service.importEnabled)
      OutlinedButton.icon(
        ...
        label: const Text('Import roster'),

Tức là Import chỉ xuất hiện nếu:

dart

    ScheduleService.importEnabled == true

Trong `ScheduleService`:

dart

    bool get importEnabled => _imports != null;

Nhưng `lib/main.dart` hiện tại tạo service:

dart

    final service = ScheduleService(
      patterns: patterns,
      schedule: ScheduleRepository(db, patterns),
    );

**Không truyền `imports:`.**

Do đó:

    _imports == null
            ↓
    importEnabled == false
            ↓
    Import roster button không xuất hiện
            ↓
    M2 UI không thể truy cập từ app thật

Trong widget test M2, agent tạo service kiểu:

dart

    ScheduleService(
      patterns: PatternRepository(db),
      schedule: ...,
      imports: ImportRepository(db),
    )

nên test pass.

Nhưng **production entrypoint lại không làm vậy.**

### Đây là bug thật, không phải opinion.

### Severity

**P1 — M2 feature unreachable in actual app.**

M2 test đang test một dependency graph khác với production app.

### Cần fix

Wire:

    ImportRepository(db)
            ↓
    ScheduleService
            ↓
    Jobs → JobDetail → ImportScreen

và phải có integration test theo đúng `main` composition.

* * *

5\. P1 — Import commit chưa thực sự atomic ở mức transaction
============================================================

Đây là vấn đề mình quan tâm hơn cả UI.

`ScheduleService.commitRoster()`:

    commitImport(session)
            ↓
    _importRepo.saveSession(result.session)
            ↓
    _schedule.replaceImportedOccurrences(...)

Tức là:

### Bước 1

Session được ghi:

    state = committed

### Bước 2

Calendar rows mới được ghi.

Nhưng hai bước này **không nằm trong cùng transaction**.

Nếu bước 2 fail:

    import_sessions = COMMITTED
    occurrences = old / incomplete

\=> database nói import đã commit nhưng calendar không phản ánh commit.

Điều này phá chính tinh thần:

> “commit atomic”

Mặc dù `commitImport()` atomic ở tầng **engine**, nhưng toàn bộ use-case:

    Import → Session → Calendar

**không atomic.**

### Severity

**P1**

### Cần làm

Commit seam phải trở thành một transaction ở persistence boundary:

    BEGIN
      save committed session
      replace imported occurrences
    COMMIT

Nếu bất kỳ bước nào fail:

    ROLLBACK

và session không được lưu thành committed.

Đây là một trong những việc mình sẽ bắt agent sửa trước M3.

* * *

6\. P1 — Re-import OFF date có bug về “newest session”
======================================================

Đây là bug subtle và test hiện tại chưa bắt.

`ScheduleRepository.committedOffDatesInRange()`:

SQL

    SELECT committedOffDatesJson
    FROM import_sessions
    WHERE jobId = ?
      AND state = 'committed'
      AND committedOffDatesJson IS NOT NULL
      AND committedOffDatesJson != '[]'
    ORDER BY createdAt DESC, id DESC

Nó bỏ qua session có:

JSON

    []

Điều này sai trong trường hợp:

### Import lần 1

    Sep 10 = OFF

\=> session A:

JSON

    ["2026-09-10"]

### Import lần 2

User re-import roster mới:

    Sep 10 = Day

\=> session B:

JSON

    []

Session B là **newest authoritative roster**.

Nhưng query lại loại B vì:

SQL

    committedOffDatesJson != '[]'

nên nó lấy session A.

Kết quả:

    Sep 10 vẫn bị suppress

dù roster mới nói Sep 10 là Day.

### Severity

**P1 — correctness bug**

Đây chính là loại bug nguy hiểm của app lịch: **user thấy lịch cũ nhưng không có error.**

### Test cần thêm

    Import A:
      09-10 OFF
    
    Import B:
      09-10 Day
    
    render:
      09-10 MUST be Day
      NOT OFF

* * *

7\. P1 — `replaceImportedOccurrences()` có semantic “window” chưa đủ chặt
=========================================================================

Hiện tại re-import:

    DELETE imported rows
    WHERE jobId
    AND isImported = 1
    AND shiftDate BETWEEN from AND to

rồi insert roster mới.

Điều này hoạt động cho cùng window.

Nhưng nếu import lần sau có **window nhỏ hơn window trước**, ví dụ:

### Import A

    Sep 1 → Sep 30

### Import B

    Sep 10 → Sep 20

thì:

    Sep 1–9
    Sep 21–30

vẫn còn import cũ.

Câu hỏi quan trọng là:

> Import B có phải “replacement của roster” hay chỉ là “partial patch”?

`features.md` và comment code đang có xu hướng nói **replacement**, nhưng implementation lại mang semantics **partial window replacement**.

Đây cần khóa spec trước khi đi xa.

### Severity

**P1/P2 tùy intended semantics.**

Mình nghiêng **P1** vì đây là dữ liệu lịch authoritative.

* * *

8\. P1 — PayRule repository vẫn chưa bảo vệ version immutability ở persistence boundary
=======================================================================================

`PayRuleRepository.savePayRule()` dùng:

SQL

    ON CONFLICT(id) DO UPDATE SET
      ...

và sau đó:

SQL

    DELETE FROM pay_differentials ...
    DELETE FROM pay_overtime_rules ...

Trong khi invariant nói:

> Historical PayRule version không được rewrite.

Code hiện tại **chỉ đúng nếu caller luôn tạo ID mới cho từng version**.

Test cũng đang làm:

    rule-v1
    rule-v2

nên pass.

Nhưng repository không ngăn:

    save rule-v1
    save rule-v1 với rate mới

\=> historical rule bị rewrite.

Đây là một invariant chỉ được bảo vệ bằng convention, không phải persistence boundary.

### Severity

**P1**

### Nên làm

PayRule version phải immutable:

    same version ID + different content
            ↓
    ERROR

Nếu muốn thay rule:

    rule-v1
    rule-v2

Không được update v1.

* * *

9\. Tương tự: PatternRepository đang phụ thuộc version ID convention
====================================================================

`PatternRepository.savePattern()` cũng:

SQL

    ON CONFLICT(id) DO UPDATE

Điều này hiện phù hợp với convention:

    pat-v1
    pat-v2

và `createNewVersion()` tạo ID mới.

Nhưng repository không thực sự enforce:

> version immutable.

Một caller có thể reuse ID.

### Severity

**P2**

Không nguy hiểm ngay ở UI hiện tại, nhưng nếu mục tiêu là production-grade domain contract thì nên chặn.

* * *

10\. Import UI: Review bắt buộc nhìn chung đúng
===============================================

`import_screen.dart` mình đánh giá khá ổn.

Có:

*   parse riêng
    
*   review riêng
    
*   approve
    
*   reject
    
*   modify
    
*   Accept All High
    
*   pending state
    
*   explicit Commit
    
*   error state
    
*   session persistence
    
*   audit
    
*   không auto commit.
    

Đặc biệt:

    Accept All High

không commit.

Đây là đúng INVARIANT-004.

Widget test cũng có kiểm tra:

    parse
    → Accept All High
    → DB vẫn 0 occurrence

rồi mới:

    Commit

\=> tốt.

* * *

11\. Nhưng Import UI còn một điểm UX/logic cần harden
=====================================================

Hiện `_canCommit()` cho phép commit khi:

    có ít nhất 1 approved/modified

nghĩa là:

    5 candidates
    
    1 approved
    4 pending

vẫn có thể Commit.

Điều này **có thể đúng theo spec**, nhưng UI đang nói:

> “review each row”

trong khi lại cho phép user commit khi còn pending.

Nếu intended semantics là:

> user có thể commit một phần roster

thì phải thể hiện rất rõ:

    3 approved
    2 pending
    Commit 3

Nếu intended semantics là:

> toàn bộ roster phải được review

thì đây là bug.

Mình chưa đánh dấu P1 vì spec hiện tại chưa đủ rõ.

**Cần chốt contract.**

* * *

12\. M2 có một vấn đề test architecture
=======================================

Test M2 tạo:

dart

    PatternRepository(db)

một lần cho service,

nhưng lại tạo một instance khác cho `ScheduleRepository`.

Không sai vì cùng SQLite DB, nhưng nó che mất dependency composition thực tế.

Quan trọng hơn:

**Không có test kiểm tra production composition `main.dart`.**

Đó chính là lý do bug Import unreachable lọt qua.

### Nên thêm test kiểu:

    createProductionService(db)
            ↓
    service.importEnabled == true
            ↓
    JobDetail shows "Import roster"

Hoặc ít nhất một composition root test.

* * *

13\. SQLCipher: vẫn là Production Blocker
=========================================

`db.dart` hiện comment:

> SQLCipher seam

nhưng `defaultOpener()` vẫn:

dart

    final db = sqlite3.open(path);
    
    if (key != null && key.isNotEmpty) {
      db.execute("PRAGMA key = '$key'");
    }

Vấn đề:

**plain SQLite không phải SQLCipher.**

Việc gửi:

SQL

    PRAGMA key = ...

không biến SQLite thường thành encrypted database.

Nói cách khác:

    SQLCipher seam ≠ SQLCipher production implementation

Hiện `main.dart` cũng không truyền key.

Vì vậy dữ liệu local production hiện chưa được chứng minh encrypted.

### Severity

**P1 Production security gap**

Không block việc tiếp tục UI development ngay lập tức, nhưng **block release production có dữ liệu nhạy cảm.**

* * *

14\. Database path cũng chưa production-grade
=============================================

`main.dart`:

    $HOME/.shiftease/shiftease.db

Điều này tạm ổn cho desktop prototype/dev.

Nhưng:

*   không dùng platform application support directory
    
*   chưa có Android/iOS
    
*   chưa có secure storage cho encryption key
    
*   chưa có backup/restore
    
*   chưa có migration recovery strategy.
    

`next.md` đã ghi một số việc này backlog.

\=> **Không sai ở M1/M2**, nhưng không được đánh dấu production-ready.

* * *

15\. SWAP vẫn có hạn chế với imported occurrence
================================================

Trong `pattern_engine.dart`, SWAP kiểm tra job bằng:

    templates[occ.templateId]?.jobId

Imported occurrence có thể có:

    templateId = ''

hoặc template không tồn tại.

Khi đó SWAP có thể fail:

    MISSING_TEMPLATE

dù hai occurrence thực tế thuộc cùng job.

Đây là consequence của việc imported occurrence đang được biểu diễn bằng `ShiftOccurrence` với:

    patternId = ''
    templateId = ''

### Severity

**P2**

Nhưng cần xử lý trước khi bật đầy đủ SPLIT/SWAP cho imported roster.

* * *

16\. Một điểm tốt: imported roster đã được thiết kế thành authoritative layer
=============================================================================

Ý tưởng M2 hiện tại khá hợp lý:

    Pattern baseline
           ↓
    suppress dates covered by imported roster
           ↓
    insert imported occurrences
           ↓
    apply overrides

Đây là hướng tốt hơn việc mutate pattern.

Nó giữ được:

    Pattern = expected roster
    Import = actual roster
    Override = user correction

Đây là architecture mình đồng ý.

Nhưng cần khóa semantics:

> Import là authoritative cho **window nào?**

và:

> re-import là replacement hay patch?

Nếu không khóa, về sau diff / pay / availability sẽ rất khó đảm bảo correctness.

* * *

17\. Đánh giá tổng thể hiện tại
===============================

Nếu chia theo tầng:

| Tầng | Đánh giá |
| --- | --- |
| Time Engine | 🟢 8.5–9/10 |
| Pattern Engine | 🟢 8.5/10 |
| Money Engine | 🟢 Core khá tốt |
| Import Engine | 🟢 khá tốt |
| SQLite persistence | 🟡 7/10 |
| Domain service | 🟡 7/10 |
| M1 UI | 🟡 7/10 |
| M2 UI | 🟡 7/10 nhưng **chưa wired production** |
| Production security | 🔴 chưa đạt |
| Test strategy | 🟢 tốt nhưng còn blind spots |
| Documentation/status | 🔴 đang lệch |

### Overall

**Khoảng 7/10 ở thời điểm hiện tại.**

Không còn là prototype core nữa. Architecture đã có nền khá tốt.

Nhưng **chưa được phép nhảy thẳng vào “M3 Pay UI” rồi coi mọi thứ phía dưới đã ổn.**

* * *

18\. Thứ tự mình khuyên agent làm tiếp
======================================

🔴 Gate A — Fix correctness trước
---------------------------------

### A1. Wire M2 vào production composition

    main.dart
      ↓
    ImportRepository
      ↓
    ScheduleService
      ↓
    Import UI

### A2. Transaction cho Import Commit

    BEGIN
      committed session
      imported occurrences
    COMMIT / ROLLBACK

### A3. Fix newest import OFF semantics

Test:

    Import A: Sep10 OFF
    Import B: Sep10 Day
    → Sep10 MUST be Day

### A4. Chốt import replacement semantics

Phải quyết định:

    re-import = replace whole previous window

hay:

    re-import = patch only supplied range

Đừng để implementation tự quyết.

* * *

19\. 🔴 Gate B — Harden version immutability
============================================

Fix:

    PayRuleRepository
    PatternRepository

để persistence layer cũng bảo vệ:

    old version != mutable record

Không chỉ dựa vào deterministic ID convention.

* * *

20\. 🟡 Gate C — UI correctness
===============================

Sau A/B:

*   DST Dialog
    
*   imported occurrence edit
    
*   clear template semantics
    
*   SWAP imported occurrence
    
*   pending import semantics
    
*   proper empty/error/loading states
    
*   composition-root test.
    

* * *

21\. 🟡 Gate D — Sau đó mới M3 Pay UI
=====================================

Lúc đó mới làm:

    Pay Rules
       ↓
    Income
       ↓
    Weekly Income
       ↓
    Income Impact

Core money hiện đã có nền khá tốt nên M3 không cần quay lại thiết kế engine từ đầu.

* * *

22\. Production feature/UI mình vẫn khuyên giữ trong roadmap
============================================================

Sau khi correctness ổn, mình sẽ ưu tiên UI theo thứ tự này:

### P0

**Today**

    TODAY
    ────────────────
    Next shift
    07:00 → 19:00
    
    Starts in 4h 12m
    
    Today
    Day shift
    
    This week
    36h
    $1,260 estimated
    ────────────────

**Calendar**

*   Week
    
*   Month
    
*   tap shift → detail
    
*   clear baseline/import/override indicator.
    

**Shift Detail**

Quan trọng nhất là:

> **“Why is this shift here?”**

Ví dụ:

    Source
    Imported roster
    
    Original
    Pattern: 4-on / 4-off
    
    Changed
    Sep 3 — Updated 09:00 → 17:00
    
    Pay
    Regular: 8h
    Estimated: $280

Đây sẽ là một UX rất mạnh cho sản phẩm correctness-first.

* * *

### P1

**Income**

    This week
    ────────────────
    Regular       $980
    Night diff    $120
    Weekend        $80
    Overtime      $315
    ────────────────
    Estimated    $1,495

và luôn:

> **Estimated — not official payroll**

**What changed?**

Đặc biệt quan trọng cho re-import:

    Roster changed
    
    Sep 12
    Day → Night
    +4h
    +$84 estimated
    
    Sep 14
    Work → OFF
    -12h
    -$420 estimated

* * *

### P1

**Settings**

Nên có từ khá sớm:

*   Jobs
    
*   Templates
    
*   Pay Rules
    
*   Timezone
    
*   Notifications
    
*   Import history
    
*   Export
    
*   Backup
    
*   Privacy
    
*   Data reset
    

* * *

### P1/P2

**Import history**

Đây sẽ là một UX differentiator:

    Import #12
    Sep 1–30
    Imported Sep 5, 14:32
    
    42 candidates
    39 accepted
    2 modified
    1 rejected
    
    View changes

Nó tận dụng rất tốt `ImportSession` audit architecture hiện tại.

* * *

23\. Final gate decision
========================

Mình **không duyệt M2 “complete” theo nghĩa production** ở thời điểm này.

Không phải vì Import Engine yếu — ngược lại, engine khá ổn.

Mà vì:

    ❌ M2 chưa được wire vào main production composition
    ❌ Import commit chưa atomic xuyên persistence
    ❌ newest import OFF semantics có bug
    ❌ re-import window semantics chưa khóa
    ❌ PayRule persistence chưa enforce immutability
    ❌ SQLCipher chưa được chứng minh/triển khai thật
    ❌ result13 không tồn tại dù checklist nói có
    ❌ features.md / next.md / checklist đang lệch trạng thái

### Nhưng nền tảng hiện tại đã đủ tốt để tiếp tục.

**Thứ tự mình chốt:**

                        CURRENT
                           │
                           ▼
                  🔴 Fix M2 correctness
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
          production    transaction   re-import
           wiring         atomic       semantics
              │            │            │
              └────────────┼────────────┘
                           ▼
                  🔴 version immutability
                           │
                           ▼
                    🟡 DST Dialog
                           │
                           ▼
                     🟡 M3 Pay UI
                           │
                           ▼
                    🟡 Export/Share
                           │
                           ▼
                 🟡 Production hardening
                           │
                           ▼
                       🚀 Release

**Đặc biệt: mình sẽ không để agent tự nhảy sang M3 ngay.** Bốn finding đầu tiên ở trên đáng để sửa và regression-test trước; nếu không, càng làm Pay/Income về sau càng khó sửa dữ liệu lịch đã sai.