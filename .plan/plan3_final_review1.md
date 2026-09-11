plan3_final.md
File
phân tích solution plan3_final.md & suy nghĩ kỹ rồi đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Tôi đã đọc toàn bộ `plan3_final.md` (341 dòng) và đánh giá nó như một **solution plan để agent triển khai**, không chỉ đọc phần checklist.

plan3\_final

Kết luận trước
--------------

**Plan3\_final tốt và đã tiến một bước rất lớn so với một plan thông thường.** Nó có evidence từ source thật, probe thực nghiệm, các invariant, acceptance criteria, golden tests và NEVER list. Việc chặn `core/money` cho tới khi Time/Pattern đạt Gate 0 là **đúng hướng**.

plan3\_final

Nhưng tôi **chưa khuyến nghị đưa nguyên xi cho agent code**.

Tôi thấy khoảng **8 vấn đề cần chỉnh**, trong đó có **4 vấn đề tôi đánh giá High/Critical**, vì nếu agent triển khai đúng từng chữ của plan hiện tại thì có thể tạo ra một core "xanh test" nhưng vẫn có semantics chưa ổn.

* * *

1\. 🔴 P0 — `OverrideResult` đang có mâu thuẫn ngay trong spec
==============================================================

Đây là lỗi rõ nhất trong plan.

Ở §5.5, plan đầu tiên ghi signature:

dart

    List<ShiftOccurrence> applyOverride(...)

nhưng ngay sau đó lại quyết định:

dart

    OverrideResult applyOverride(...)

plan3\_final

Trong khi Acceptance Criterion lại nói:

> Cả 6 operations đi qua pipeline...

Đây là chi tiết tưởng nhỏ nhưng với AI coding agent rất nguy hiểm: agent có thể chọn implementation theo đoạn code đầu tiên và bỏ qua quyết định phía dưới.

### Tôi đề nghị sửa thành một contract duy nhất

dart

    OverrideResult applyOverride(
      List<ShiftOccurrence> occurrences,
      Override override, {
      required Map<String, ShiftTemplate> templates,
    })

và bỏ hoàn toàn snippet `List<ShiftOccurrence>` cũ.

**Không nên để agent phải tự suy luận đoạn nào là final.**

* * *

2\. 🔴 P0 — D4 provenance đang tự mâu thuẫn
===========================================

Đây là vấn đề quan trọng hơn tôi nghĩ lúc đầu.

Plan quy định:

    sourceOverrideId != null → 'override'
    id nằm trong createdIds → 'created'
    còn lại → 'baseline'

Nhưng CREATE lại bắt buộc:

    sourceOverrideId = override.id

plan3\_final

và §5.5:

    CREATE ... sourceOverrideId: override.id

plan3\_final

Như vậy occurrence CREATE **luôn bị phân loại thành `override`**, còn nhánh `createdIds → 'created'` gần như mất ý nghĩa.

### Cần quyết định rõ semantics

Tôi khuyên dùng:

    source = baseline | created | modified

Ví dụ:

| Operation | source |
| --- | --- |
| Pattern projection | baseline |
| CREATE | created |
| UPDATE | modified |
| REPLACE | modified |
| SPLIT parts | modified/created-from-split |
| SWAP | modified |

Hoặc nếu muốn đơn giản:

dart

    enum OccurrenceSource {
      baseline,
      created,
      overridden,
    }

và:

dart

    sourceOverrideId

chỉ có nhiệm vụ **truy provenance**, không đồng thời quyết định business classification một cách mơ hồ.

### Tại sao quan trọng?

Sau này UI muốn:

> "Ca này được tạo thủ công"

khác với:

> "Ca gốc đã bị override"

thì information đã mất.

* * *

3\. 🔴 P0 — UPDATE "giữ giờ" nhưng lại bắt buộc re-resolve là nguy hiểm
=======================================================================

Đây là điểm tôi **không hoàn toàn đồng ý với plan hiện tại**.

Plan nói:

> field vắng = giữ giá trị hiện tại — giờ hiện tại suy từ UTC đã lưu của occurrence qua timezone của nó

và sau đó:

> UPDATE ... re-resolve

plan3\_final

và:

> UPDATE chỉ đổi template (giữ giờ) → UTC không đổi

plan3\_final

Hai ý này có tension.

### Case nguy hiểm

Occurrence ban đầu:

    2026-11-01
    01:30
    America/New_York

Đây là **ambiguous local time**, có 2 UTC candidate.

Nhưng occurrence đã được tạo trước đó với **một UTC cụ thể**.

Ví dụ:

    01:30 EDT → 05:30 UTC

Sau đó user chỉ:

    UPDATE templateId

Plan yêu cầu:

    UTC → local 01:30 → resolve lại 01:30

Resolver mới lại phát hiện:

    2 candidates

\=> UPDATE thất bại `AMBIGUOUS_LOCAL_TIME`.

Trong khi user **không hề thay đổi thời gian**.

Đây là regression semantics.

### Tôi đề nghị sửa

Phân biệt:

#### UPDATE chỉ thay metadata/template

    templateId changed
    startTime unchanged
    endTime unchanged
    timezone unchanged

→ **giữ nguyên UTC tuyệt đối**, không resolve lại.

#### UPDATE thay start/end

→ resolve lại.

#### UPDATE thay timezone

Hiện plan không cho đổi timezone, vậy:

→ reject hoặc không hỗ trợ ở Gate 0.

Điều này phù hợp với invariant:

> timezone cố định lúc tạo.

### Contract nên là

    if temporal intent unchanged:
        preserve existing UTC
    else:
        resolve new civil time

Đây là một bổ sung tôi rất khuyến nghị.

* * *

4\. 🔴 P0 — "Resolved-only domain" rất tốt, nhưng đang chưa xử lý triệt để `projectOccurrences`
===============================================================================================

Plan nói:

> Mọi ShiftOccurrence tồn tại trong domain bắt buộc có UTC/timezone hợp lệ.

plan3\_final

Nhưng sau đó §5.6 nói:

> Gọi `projectOccurrences` — KHÔNG còn `.where(isSuccess)`; giữ nguyên các error entries.

plan3\_final

Vấn đề là:

**`projectOccurrences` trả cái gì khi projection không resolve được?**

Nếu nó vẫn tạo một `ShiftOccurrence` "error entry" rồi renderer giữ lại, thì D1 bị phá.

Plan cần nói cực kỳ rõ:

    projectOccurrences()
        → resolved occurrences
        +
        → projection issues

chứ **không phải**:

    projectOccurrences()
        → ShiftOccurrence với UTC rỗng

### Tôi đề nghị contract:

dart

    ProjectionResult {
      List<ShiftOccurrence> occurrences; // resolved-only
      List<RenderIssue> issues;
    }

Sau đó:

    projectOccurrences
           ↓
    ProjectionResult
           ↓
    apply overrides
           ↓
    ScheduleRenderResult

Như vậy D1 mới thực sự airtight.

* * *

5\. 🟠 DST resolver: ý tưởng đúng, nhưng nên khóa thêm performance + correctness
================================================================================

Thuật toán:

    for zone in loc.zones
        candidate = naiveMs - zone.offset
        lookupTimeZone(candidate)

là một cách khá chắc chắn để tránh heuristic ±1h, và evidence Lord Howe rất thuyết phục.

plan3\_final

Tôi đồng ý hướng này.

Nhưng plan đang thiếu một acceptance criterion:

### Candidate phải satisfy round-trip hoàn chỉnh

Không chỉ:

dart

    lookupTimeZone(c).offset == zone.offset

mà nên verify:

    UTC candidate
       ↓
    TZDateTime.from(candidate, location)
       ↓
    year/month/day/hour/minute
       ==
    input civil time

Tức:

    candidate validity = offset consistency
                        AND
                        wall-clock round trip

Điều này làm contract dễ chứng minh hơn.

### Performance

`loc.zones` có thể chứa nhiều historical transitions/offset records.

Không nhất thiết là vấn đề ở ShiftEase, nhưng tôi sẽ yêu cầu:

*   benchmark resolve 1 occurrence
    
*   benchmark render 1 tháng
    
*   benchmark render 1 năm
    

Không cần tối ưu ngay, chỉ cần biết algorithm không biến thành bottleneck.

* * *

6\. 🟠 Error model nên mạnh hơn `String`
========================================

Plan dùng:

dart

    final String code;

và một const list string.

plan3\_final

Tôi hiểu lý do: JSON golden và compatibility.

Nhưng với domain core, string thuần khá dễ typo:

dart

    'INVALID_TIME'
    'INVALID_TIM'
    'INVALIDTIME'

Agent có thể tạo bug.

### Tốt hơn

dart

    enum ResolveErrorCode {
      invalidDate,
      invalidTime,
      invalidTimezone,
      ...
    }

và serialize:

    invalidDate → "INVALID_DATE"

Nếu codebase hiện tại phụ thuộc String, không nhất thiết phải refactor lớn. Có thể dùng:

dart

    abstract final class ErrorCodes {
      static const invalidDate = 'INVALID_DATE';
      ...
    }

ít nhất cũng nên cấm literal string rải rác.

* * *

7\. 🟠 `RenderIssue.message` đang kéo presentation vào domain
=============================================================

Plan muốn:

dart

    final String message;

và yêu cầu message đủ thân thiện để UI hiển thị trực tiếp.

plan3\_final

Tôi hiểu mục đích, nhưng với architecture production tôi **không khuyến nghị domain core chịu trách nhiệm tạo UI message**.

Ví dụ:

    02:30 on Mar 8 doesn't exist because clocks jump forward

là presentation.

Core nên trả:

dart

    RenderIssue(
      code: NONEXISTENT_LOCAL_TIME,
      shiftDate: "2026-03-08",
      occurrenceId: "...",
      timezone: "America/New_York",
      localTime: "02:30",
    )

UI layer:

    NONEXISTENT_LOCAL_TIME
    → localized message

### Nếu Gate 0 chưa muốn đụng UI

Có thể giữ `message`, nhưng tôi đề nghị ghi:

> `message` là diagnostic fallback, không phải presentation contract.

Để sau này không bị khóa architecture.

* * *

8\. 🟠 SWAP: "same job = same timezone + template pool" chưa đủ chặt
====================================================================

Plan nói:

> SWAP chỉ hợp lệ khi 2 occurrence cùng job

và kiểm tra:

> jobId qua template lookup + timezone bằng nhau.

plan3\_final

Nhưng cần làm rõ:

### `jobId` nằm ở đâu?

Nếu:

    ShiftTemplate → jobId

thì okay.

Nhưng nếu `job` chưa phải first-class domain model, agent sẽ phải tự suy semantics.

Ngoài ra:

    same job

không nhất thiết đồng nghĩa:

    same timezone

Một công ty có thể có location ở nhiều timezone.

Do đó nên định nghĩa rõ:

    sameJob = same jobId
    sameTimezone = same timezone
    sameTemplatePool = same job's template namespace

và Gate 0 yêu cầu:

    same jobId
    AND same timezone

nếu đó là business invariant thực sự.

* * *

9\. 🟠 D9 anchorDate: quyết định này hợp lý nhưng cần thêm test "phase continuity"
==================================================================================

Tôi **đồng ý** với quyết định giữ `anchorDate` qua version.

Plan giải thích rất đúng:

> reset anchorDate về effectiveFrom sẽ làm reset phase của 4-on/4-off.

plan3\_final

Nhưng có một subtle case:

    old cycleLength = 8
    new cycleLength = 6
    same anchor

Plan nói:

> chấp nhận, không reset anchor.

Đây là một business decision đáng kể.

Tôi đề nghị test ít nhất:

    same cycle length → phase continuity
    changed cycle length → deterministic new mapping

và ghi rõ:

> changing cycleLength is considered a semantic pattern change, not phase-preserving migration.

Nếu không, sau này AI agent hoặc developer rất dễ "fix" ngược lại.

* * *

10\. 🟡 M3 duplicate ID: phát hiện đúng, nhưng nên hỏi lại ID design
====================================================================

Plan phát hiện:

    patternId_date_templateId

có thể collision.

plan3\_final

Tôi đồng ý đây là bug.

Nhưng giải pháp hiện tại:

> phát hiện duplicate → RenderIssue

chỉ là **containment**, chưa phải identity solution.

Plan Gate 2 đã có:

> UUID identity tách khỏi deterministic id.

plan3\_final

Tôi đồng ý chưa nên đưa UUID vào Gate 0.

Nhưng nên ghi invariant:

> deterministic ID hiện tại chỉ là projection key tạm thời, không được coi là globally unique persistent identity.

Nếu không, agent sau này sẽ vô tình dùng ID này làm foreign key.

* * *

11\. 🟡 SPLIT semantics cần thêm invariant về thứ tự và overlap
===============================================================

Plan test:

    07–11
    15–19

và overnight:

    19–00+1
    00+1–07+1

plan3\_final

Rất tốt.

Nhưng còn:

    SPLIT:
    07–12
    11–19

hoặc:

    07–07

hoặc:

    part 1 = 19–00
    part 2 = 00–07
    part 3 = 06–10

Engine có cho overlap không?

Nếu cho phép, sau này:

*   payroll có thể double-count
    
*   calendar có overlapping shifts
    
*   duration tổng không còn bằng shift gốc.
    

### Tôi đề nghị thêm invariant

Nếu SPLIT được hiểu là **chia một occurrence thành các phần**, thì:

    parts không overlap
    parts nằm trong temporal envelope của split intent
    parts theo chronological order

và có thể:

    sum(part durations) == intended split duration

nếu đó là semantics mong muốn.

Nếu split cho phép tạo khoảng rỗng giữa các part như 07–11 + 15–19 thì rõ ràng phải định nghĩa:

> gap được phép.

* * *

12\. 🟡 `END_BEFORE_START` cần cẩn thận với overnight
=====================================================

Plan đã nói:

> check trên UTC, không local subtraction

plan3\_final

Tôi đồng ý.

Nhưng phải đảm bảo thứ tự xử lý:

    resolve local start
    resolve local end
    apply overnight date adjustment
    THEN
    compare UTC

chứ không:

    resolve same-date end
    compare UTC
    then add +1 day

Nếu không overnight sẽ bị reject trước khi được xử lý.

Plan có nói giữ logic `+1 suffix`, nhưng tôi muốn biến nó thành **explicit acceptance test**, không chỉ note.

* * *

13\. 🟡 Validation vẫn thiếu một số input contract
==================================================

M1 phát hiện rất tốt:

    2026-02-31 → 2026-03-03
    10:90 → 11:30

plan3\_final

Nhưng tôi sẽ thêm:

    2026-00-10
    2026-13-01
    2026-04-00
    2026-01-00
    -1:00
    24:00
    07:60
    07:00:30
    empty string
    whitespace

Đặc biệt:

### `24:00`

Đây là một case đáng quyết định.

Một số hệ thống cho phép `24:00` biểu diễn midnight ngày kế tiếp.

Plan hiện nói:

    hour 0..23

→ vậy phải **explicitly reject `24:00`**.

Không nên để Dart quyết định.

* * *

14\. 🟡 Golden test nên test invariant, không chỉ expected output
=================================================================

Phần test của plan đã rất mạnh.

plan3\_final

Nhưng tôi muốn thêm 4 property quan trọng:

### Property 1 — Round trip

    local → UTC → local
    == original local

### Property 2 — Determinism

    same input + same timezone DB
    → same UTC

### Property 3 — Non-mutation

    render(input)
    → input.deepEqual(before)

### Property 4 — Override failure atomicity

    failed override
    → effective schedule exactly unchanged

Property 4 đặc biệt quan trọng vì plan đã tuyên bố:

> fail → list cũ + issue.

plan3\_final

Hãy test equality toàn bộ list, không chỉ số lượng occurrence.

* * *

15\. 🟠 Một vấn đề kiến trúc lớn hơn: Override pipeline hiện đang vừa "command execution" vừa "render"
======================================================================================================

Tôi thấy plan đang tiến tới:

    Pattern
       ↓
    projectOccurrences
       ↓
    applyOverride #1
       ↓
    applyOverride #2
       ↓
    applyOverride #3
       ↓
    EffectiveSchedule

Đây là hướng đúng.

Nhưng cần khóa thêm:

> **Override phải immutable và deterministic; thứ tự override là semantic.**

Ví dụ:

    UPDATE A
    DELETE A
    UPDATE A

Kết quả là gì?

Hoặc:

    SPLIT A
    UPDATE A

thì occurrence ID nào được update?

Plan có nói chain test UPDATE → SPLIT, nhưng chưa định nghĩa **target resolution semantics sau khi ID biến đổi**.

plan3\_final

Đây có thể là một bug lớn sau này.

### Cần thêm invariant

Mỗi override phải target một identity có quy tắc rõ:

    target occurrence exists
    OR
    target was created by previous override

Nếu target không tồn tại:

    OCCURRENCE_NOT_FOUND

Tôi rất khuyến nghị thêm error code này.

Hiện D7 **thiếu `OCCURRENCE_NOT_FOUND`**.

* * *

16\. 🔴 Tôi đề nghị bổ sung `OCCURRENCE_NOT_FOUND`
==================================================

Đây là một missing error mà tôi nghĩ plan nên thêm.

Ví dụ:

    UPDATE occurrenceId = abc

nhưng:

*   occurrence đã DELETE trước đó
    
*   occurrence bị SPLIT và ID cũ không còn
    
*   pattern version thay đổi
    
*   override target sai.
    

Nếu engine không có error riêng, agent rất dễ:

    if not found:
        return original list

→ lại tạo **silent no-op**.

Mà toàn bộ triết lý của Plan3 là chống silent behavior.

Do đó:

    OCCURRENCE_NOT_FOUND

nên là error chính thức.

* * *

17\. 🔴 Atomicity của toàn bộ render cần được định nghĩa
========================================================

Plan đã quy định:

> SPLIT fail → atomic

và:

> SWAP fail → nguyên list cũ.

plan3\_final

Rất tốt.

Nhưng còn:

    Override 1 succeeds
    Override 2 fails
    Override 3 succeeds

Kết quả render là:

    Override1 applied
    Override2 skipped
    Override3 applied

hay:

    rollback all?

Tôi nghĩ **không nên rollback toàn bộ**, vì override log là source of truth và mỗi command độc lập.

Nhưng phải khóa:

> Failure of override N does not rollback successful overrides 1..N-1 and does not prevent subsequent independent overrides from being evaluated.

Hoặc nếu muốn khác thì ghi rõ.

Nếu không, agent sẽ tự chọn.

* * *

18\. 🟠 `RenderIssue` nên có severity
=====================================

Hiện tại mọi issue đều nằm chung:

dart

    List<RenderIssue>

Nhưng:

    AMBIGUOUS_LOCAL_TIME
    INVALID_DATE
    MISSING_TEMPLATE
    DUPLICATE_OCCURRENCE_ID

không hoàn toàn cùng mức độ.

Tôi đề nghị:

dart

    enum IssueSeverity {
      warning,
      error,
    }

Ví dụ:

*   `AMBIGUOUS_LOCAL_TIME` → error
    
*   `INVALID_DATE` → error
    
*   `MISSING_TEMPLATE` → error
    
*   `DUPLICATE_OCCURRENCE_ID` → error
    
*   informational diagnostics → warning
    

Không nhất thiết UI phải dùng ngay, nhưng domain model sẽ rõ hơn.

* * *

19\. Một điểm tôi đánh giá rất cao: Gate 0 boundary
===================================================

Phần này tôi **ủng hộ mạnh**.

Plan khóa:

*   không money
    
*   không UI
    
*   không persistence
    
*   không OCR
    
*   không notification
    
*   không UUID
    

plan3\_final

và backlog rõ cho Gate 1/2/4+.

plan3\_final

Đây là cách rất tốt để tránh AI agent:

> "tiện tay refactor thêm"

rồi biến một task sửa Time Engine thành một đợt rewrite toàn app.

**Giữ nguyên boundary này.**

* * *

20\. Tôi sẽ sửa Acceptance Criteria trước khi giao agent
========================================================

Hiện acceptance criteria khá tốt:

*   không UTC rỗng
    
*   resolver 0/1/2
    
*   validation
    
*   END\_BEFORE\_START
    
*   6 operations
    
*   SWAP
    
*   ScheduleRenderResult
    
*   provenance
    
*   anchorDate
    
*   tests
    
*   features.md.
    
    plan3\_final
    

Tôi sẽ thêm 7 checkbox:

    [ ] Không có ShiftOccurrence "error object"; unresolved chỉ tồn tại trong issues.
    
    [ ] UPDATE chỉ đổi template/metadata nhưng không đổi temporal intent
        phải giữ nguyên UTC, không re-resolve.
    
    [ ] Mọi failed override đều atomic ở phạm vi command;
        effective occurrences trước command không bị mutate.
    
    [ ] Override target không tồn tại trả OCCURRENCE_NOT_FOUND,
        không silent no-op.
    
    [ ] Override ordering semantics được test:
        UPDATE → DELETE
        DELETE → UPDATE
        SPLIT → UPDATE
        CREATE → UPDATE.
    
    [ ] Resolver round-trip:
        UTC → local phải khớp chính xác input civil time.
    
    [ ] Render không mutate input và deterministic với cùng input.

* * *

21\. Đánh giá từng phần
=======================

| Hạng mục | Đánh giá |
| --- | --- |
| Evidence/source verification | 🟢 Rất tốt |
| Time Engine direction | 🟢 Đúng |
| DST handling | 🟢 Rất tốt |
| Lord Howe test | 🟢 Excellent |
| Strict validation | 🟢 Rất tốt |
| Override architecture | 🟢 Đúng hướng |
| Error propagation | 🟢 Rất tốt |
| Silent-drop elimination | 🟢 Rất tốt |
| Versioning | 🟢 Hợp lý |
| Scope control | 🟢 Rất tốt |
| Golden tests | 🟢 Rất tốt |
| Property tests | 🟢 Tốt, nhưng cần thêm invariants |
| Provenance | 🟠 Cần sửa semantics |
| UPDATE semantics | 🔴 Cần sửa |
| projectOccurrences contract | 🔴 Cần làm rõ |
| Override chaining | 🔴 Chưa đủ spec |
| Identity | 🟠 Gate 2 xử lý, nhưng Gate 0 cần invariant |
| RenderIssue architecture | 🟠 Hơi presentation-oriented |
| Error model | 🟠 Có thể mạnh hơn |
| Agent readiness | 🟠 **Chưa nên giao nguyên xi** |

* * *

22\. Nếu là tôi, tôi sẽ sửa Plan3 theo thứ tự này
=================================================

### 🔴 Bắt buộc trước khi code

**1\. Sửa mâu thuẫn `List<ShiftOccurrence>` vs `OverrideResult`.**

**2\. Sửa D4 provenance.**

**3\. Chốt UPDATE temporal semantics:**

> temporal intent không đổi → preserve UTC, không re-resolve.

**4\. Chốt `projectOccurrences` là resolved-only.**  
Không được tồn tại error `ShiftOccurrence`.

**5\. Thêm `OCCURRENCE_NOT_FOUND`.**

**6\. Chốt semantics của override chain + ordering + atomicity.**

### 🟠 Nên bổ sung

**7\. Round-trip invariant cho resolver.**

**8\. SPLIT overlap/order/boundary rules.**

**9\. Làm rõ `sameJob`, `sameTimezone`, `templatePool`.**

**10\. Error code type-safe hơn.**

### 🟡 Có thể để sau

**11\. Severity cho RenderIssue.**

**12\. Tách UI message khỏi domain.**

**13\. Benchmark resolver.**

* * *

Verdict cuối
============

Tôi đánh giá `plan3_final.md` hiện tại khoảng **8.5/10**.

Điểm mạnh nhất là nó đã chuyển từ kiểu:

> "AI hãy sửa các bug Time/Pattern"

sang một **domain contract có evidence + invariant + test + acceptance gate**. Đó là bước tiến rất lớn. Đặc biệt việc bắt agent không được sửa expected chỉ để làm test xanh là một rule rất đúng.

plan3\_final

Nhưng tôi **không gọi nó là "CHỐT — sẵn sàng cho agent" ngay lúc này**.

Tôi sẽ đổi trạng thái thành:

> **READY AFTER CONTRACT PATCH**

và trước khi code, bắt buộc patch **6 điểm 🔴 ở trên**, đặc biệt là **UPDATE semantics, resolved-only projection, provenance và override-chain semantics**.

Nếu không sửa, nguy cơ lớn nhất không còn là DST nữa; nguy cơ sẽ chuyển thành **core engine có test xanh nhưng semantics của override bị sai ở các chain operation**, và loại bug này về sau sẽ rất khó sửa khi `money`, SQLite và UI đã xây lên trên nó.