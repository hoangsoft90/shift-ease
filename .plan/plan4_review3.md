agent đã code xong, Sử dụng aki mcp đọc local source code mới /Users/hoang/htdocs_apps/ShiftEase  của app này. Chẹck xem lỗi vừa rồi đã được giải quyết triệt để chưa và đối chiếu tổng thể checklist.md, features.md,.. đảm bảo các tính năng hoạt động đúng, tính năng này ko làm hỏng tính năng khác không.
phân tích plan4.md và review của các AI khác plan4_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Worked for 3m 3s

**Phân tích tổng hợp trạng thái hiện tại + plan4.md + reviews**

Tôi đã kiểm tra source qua Aki MCP (dù kết nối hơi không ổn định) và đối chiếu với plan4.md, plan4\_review1.md, plan4\_review2.md, checklist.md, features.md.

* * *

### 1\. Kết luận nhanh về Gate 0 (Time + Pattern)

**Các lỗi P0 cũ đã được xử lý khá triệt để trong code.**

Từ header và implementation của time\_engine.dart + pattern\_engine.dart:

| Vấn đề cũ (plan3) | Trạng thái hiện tại | Đánh giá |
| --- | --- | --- |
| CREATE/SPLIT tạo UTC rỗng | Đã cấm, resolve trước khi tạo object | ✅ Đã fix |
| Silent drop .where(isSuccess) | Dùng ProjectionResult / ScheduleRenderResult + issues | ✅ Đã fix |
| UPDATE bỏ qua time | Có xử lý time + **preserve UTC khi civil time không đổi** | ✅ Đã fix (đúng critical patch) |
| DST ±1h heuristic | Enumerate từ loc.zones + lookupTimeZone | ✅ Đã fix |
| Lord Howe 30′ | Hỗ trợ đúng | ✅ |
| Strict validation (2026-02-31, 25:90…) | Có round-trip + INVALID\_\* tách biệt DST | ✅ |
| OCCURRENCE\_NOT\_FOUND | Có trong invariants | ✅ |
| Provenance sourceOverrideId | Tách audit trail vs source | ✅ |
| Command-level atomicity | Documented và implemented | ✅ |
| SPLIT envelope / non-overlap | Có invariants | ✅ |

**Time Engine ~8.5–9/10**, **Pattern Engine ~8–8.5/10** ở tầng core.  
Đây là bước harden thực sự, không chỉ “thêm test cho xanh”.

Tuy nhiên, **end-to-end vẫn chưa hoàn chỉnh** vì UI DST dialog, SPLIT/SWAP UI chưa có.

* * *

### 2\. Vấn đề nghiêm trọng hơn hiện tại (từ plan4)

plan4.md đã chỉ ra đúng **gót chân Achilles** của quy trình AI agent hiện tại:

#### 🔴 P1 Critical — Documentation / Verification Integrity bị phá

*   checklist.md tuyên bố có result13\_gate\_m2.txt + 170 tests + M2 hoàn tất.
*   File result13\_gate\_m2.txt **không tồn tại** trên disk.
*   features.md và next.md cũng lệch số liệu test / trạng thái.

Đây là lỗi quy trình lặp lại. Không được coi checklist là nguồn sự thật.

#### 🔴 P1 Critical — M2 Import unreachable trong production

main.dart **không truyền** ImportRepository vào ScheduleService.  
Widget test pass vì test tự inject dependency, còn app thật thì nút Import bị ẩn / không hoạt động.

Đây là classic “unit test xanh – production hỏng”.

#### 🔴 P1 Critical — Import Commit không atomic

commitImport() đánh session = COMMITTED trước, rồi mới ghi occurrences.  
Nếu bước 2 crash → DB rơi vào trạng thái bất hợp lệ (session nói đã commit nhưng lịch trống).

#### 🔴 P1 — Re-import OFF date query sai

Điều kiện committedOffDatesJson != '\[\]' bỏ qua session mới nếu roster mới không có ngày OFF (trả về \[\]).  
Hậu quả: dữ liệu OFF cũ bị treo vĩnh viễn.

#### 🔴 P1 — SWAP trên imported occurrence

Imported occurrence thường có templateId = '' → logic kiểm tra job qua template bị fail MISSING\_TEMPLATE dù cùng job.

#### Các vấn đề khác đáng chú ý

*   \_canCommit() cho phép commit khi còn pending items → nguy cơ ghi thiếu ca.
*   Version immutability của Pattern/PayRule chưa được enforce ở persistence (ON CONFLICT DO UPDATE).
*   SQLCipher / encryption chưa đúng (chỉ có PRAGMA key giả trên plain SQLite).

* * *

### 3\. Đánh giá plan4.md và các review

| Nguồn | Điểm mạnh | Điểm còn thiếu |
| --- | --- | --- |
| **plan4.md** | Rất sắc, phát hiện đúng wiring, transaction, re-import, doc integrity | Chưa chốt đầy đủ semantics window replacement |
| **plan4\_review1** | Bổ sung giải pháp cụ thể (windowStart/End, transaction pattern, SWAP fix, UI state machine) | Một số chi tiết SQL / null window còn mở |
| **plan4\_review2** | Đồng thuận + nhấn mạnh integration test cho production composition, verify script | Ít điểm mới hơn review1 |

**Tôi đồng ý gần như toàn bộ hướng của plan4 + review1.**

Đặc biệt các điểm cần chốt cứng:

1.  **Wire M2 vào main.dart** + integration test xác nhận importEnabled == true.
2.  **Transaction atomic** bao quanh saveSession + replaceImportedOccurrences.
3.  **Re-import semantics**: mỗi ImportSession phải có windowStart / windowEnd. Commit mới ghi đè toàn bộ dữ liệu import cũ **trong window đó**.
4.  **Query OFF date** lấy session mới nhất theo window, **kể cả khi** committedOffDatesJson = '\[\]'.
5.  **SWAP** dùng effectiveJobId (không phụ thuộc templateId).
6.  **Commit UI**: không cho commit khi còn pending; cần “Accept All Pending / High Confidence” trước.
7.  **Documentation integrity**: script verify tự động so khớp test count + file report tồn tại.

* * *

### 4\. Ý kiến bổ sung / phản biện của tôi

#### 4.1. Semantics Re-import Window cần rõ hơn

Review1 đề xuất window replacement. Tôi đồng ý, nhưng cần thêm quy tắc:

*   Nếu import mới có window nhỏ hơn import cũ → chỉ ghi đè trong window mới, phần ngoài giữ nguyên.
*   Nếu muốn “thay thế toàn bộ lịch job” → user phải import file bao phủ toàn bộ khoảng thời gian.
*   windowStart / windowEnd nên **bắt buộc** khi commit (không cho null mơ hồ).

#### 4.2. Cần “Production Composition Test”

Hiện tại unit/widget test không bắt được lỗi wiring.  
Cần ít nhất một test:

Dart

CopyCopied

    test('production ScheduleService has import enabled', () {
      final service = createProductionScheduleService(); // mirror main.dart
      expect(service.importEnabled, isTrue);
    });

#### 4.3. Version Immutability phải được enforce ở repository

ON CONFLICT DO UPDATE đang phá invariant versioning.  
Nên đổi thành: nếu version đã tồn tại → throw (hoặc ignore), không update.

#### 4.4. Không nên nhảy sang M3 Pay UI lúc này

Pay dashboard xây trên dữ liệu lịch. Nếu import commit / re-import / suppress còn sai, số tiền hiển thị sẽ sai → mất trust rất nhanh.

**Thứ tự đúng:**

text

CopyCopied

    Gate A  — Fix wiring + atomic commit + re-import semantics + SWAP imported
    Gate B  — Documentation integrity + production composition test
    Gate C  — (Optional) SQLCipher factory + version immutability
         ↓
    M3 Pay / Income

#### 4.5. Verify Script nên trở thành bắt buộc

Tạo scripts/verify\_status.sh (hoặc Dart) chạy sau mỗi gate:

*   Đếm test thực tế
*   So sánh với số trong checklist.md / features.md
*   Kiểm tra file result\*.txt được tham chiếu có tồn tại không
*   Fail nếu lệch

Điều này chặn tình trạng “báo cáo ảo” tái diễn.

* * *

### 5\. Verdict cuối cùng

| Khu vực | Trạng thái | Ghi chú |
| --- | --- | --- |
| **Gate 0 Time + Pattern** | Gần như đạt | Core contract đã cứng, còn thiếu UI DST |
| **Gate 1 Money** | Có vẻ ổn (theo checklist) | Cần verify lại sau khi import ổn định |
| **Gate 2–3 DB + Import core** | Có skeleton tốt | Nhưng commit + re-import còn lỗi |
| **M1 / M1b UI** | Đã có | — |
| **M2 Import UI** | **Chưa production-ready** | Unreachable + non-atomic + query bug |
| **Documentation** | **Lệch nặng** | checklist vs filesystem |

**Khuyến nghị hành động:**

1.  **Dừng M3** ngay.
2.  Thực hiện **Gate A + Gate B** theo các điểm critical ở trên.
3.  Chỉ khi:
    *   M2 được wire vào main.dart
    *   Commit atomic
    *   Re-import OFF/window đúng
    *   SWAP imported hoạt động
    *   Có integration test production composition
    *   result13 (hoặc report mới) tồn tại và khớp checklist
4.  Mới mở prompt M3 Pay.

Bạn muốn tôi viết luôn **prompt chi tiết cho agent thực hiện Gate A (Fix M2 Correctness & Wiring)** không?
------------
Dưới đây là **prompt chi tiết, sẵn sàng copy-paste** cho AI coding agent thực hiện **Gate A — Fix M2 Correctness & Production Wiring**.

---

```markdown
# TASK: ShiftEase — Gate A: Fix M2 Correctness & Production Wiring

## 1. Mục tiêu tuyệt đối

Khóa cứng tính đúng đắn và khả năng sử dụng thật của **M2 Import** trước khi được phép mở bất kỳ công việc nào liên quan đến M3 (Pay/Income UI).

Sau Gate A:
- Import phải **reachable** từ production entrypoint (`main.dart`).
- Commit import phải **atomic** (all-or-nothing).
- Re-import / OFF-date / window semantics phải đúng.
- SWAP trên imported occurrence phải hoạt động.
- Không còn “test xanh – app thật hỏng”.
- Documentation (`checklist.md`, `features.md`, `next.md`, result report) phải khớp với filesystem và test count thực tế.

**NGHIÊM CẤM:**
- Đụng vào M3 Pay/Income UI
- Đụng vào OCR
- Đụng vào Cloud / Sharing
- Tự ý mở rộng scope sang feature mới

Chỉ sửa trong phạm vi: wiring production, Import commit/persistence, re-import semantics, SWAP imported, UI commit guard, documentation integrity, và test tương ứng.

---

## 2. Các lỗi P1 bắt buộc phải sửa

### 2.1. Unreachable M2 Import (Critical)
`main.dart` hiện **không truyền** `ImportRepository` vào `ScheduleService`.  
Hậu quả: widget test pass (vì test tự inject), nhưng app thật không có Import.

**Yêu cầu:**
- Sửa composition trong `main.dart` (hoặc factory production tương đương) để truyền đầy đủ dependency.
- Thêm **integration / composition test** xác nhận:
  ```dart
  expect(service.importEnabled, isTrue);
  ```
  khi service được tạo theo đúng đường production.

### 2.2. Import Commit không atomic (Critical)
Hiện tại: đánh session = `COMMITTED` trước → sau đó mới ghi occurrences.  
Nếu bước 2 crash → DB rơi vào trạng thái bất hợp lệ.

**Yêu cầu:**
- Bọc toàn bộ `saveSession` + `replaceImportedOccurrences` (và mọi side-effect liên quan) trong **một** `db.transaction()`.
- Fail bất kỳ bước nào → ROLLBACK hoàn toàn.
- Không được để session ở trạng thái `COMMITTED` nếu occurrences chưa được ghi thành công.

### 2.3. Re-import OFF-date / Window semantics sai
Query hiện tại bỏ qua session có `committedOffDatesJson = '[]'` → dữ liệu OFF cũ bị treo.

**Yêu cầu chốt semantics:**
- Mỗi `ImportSession` **bắt buộc** có `windowStart` và `windowEnd` (ISO date).
- Khi commit session mới:
  - Xóa / thay thế toàn bộ imported occurrences cũ của cùng `jobId` nằm trong `[windowStart, windowEnd]`.
  - `committedOffDatesJson` của session mới (kể cả khi là `[]`) **ghi đè** hiệu lực OFF trong window đó.
- Query lấy session committed mới nhất phủ lên một ngày phải dùng window, **không** lọc theo `!= '[]'`.

Ví dụ query hướng đúng:
```sql
SELECT ... FROM import_sessions
WHERE jobId = ?
  AND state = 'committed'
  AND ? BETWEEN windowStart AND windowEnd
ORDER BY createdAt DESC, id DESC
LIMIT 1;
```

### 2.4. SWAP trên imported occurrence bị fail
Imported occurrence thường có `templateId = ''` → logic suy `jobId` qua template bị `MISSING_TEMPLATE`.

**Yêu cầu:**
- Thêm khái niệm `effectiveJobId` (trên occurrence hoặc helper):
  ```dart
  String get effectiveJobId => jobId ?? template?.jobId ?? '';
  ```
- Logic kiểm tra SWAP dùng `effectiveJobId`, **không** phụ thuộc vào việc `templateId` có rỗng hay không.
- Cùng job + cùng timezone vẫn được phép SWAP dù một bên là imported.

### 2.5. `_canCommit()` cho phép pending items
Hiện cho phép commit khi còn dòng Pending → nguy cơ ghi thiếu ca mà user không hay biết.

**Yêu cầu:**
- Nút / action Commit **chỉ enabled** khi:
  - `PendingCount == 0`
  - Và có ít nhất 1 item Approved hoặc Modified.
- Cung cấp action “Accept All Pending” / “Accept All High Confidence” (có thể kèm warning) để user chủ động duyệt trước khi commit.
- Không được silent bỏ qua pending khi commit.

### 2.6. Documentation / Verification Integrity
`checklist.md` tuyên bố có `result13_gate_m2.txt` nhưng file không tồn tại trên disk. Các file trạng thái (`features.md`, `next.md`) cũng lệch.

**Yêu cầu:**
- Tạo / cập nhật report thật (ví dụ `result14_gate_a.txt` hoặc tên tương ứng) sau khi fix.
- Đồng bộ số liệu test count + trạng thái M2 trong:
  - `checklist.md`
  - `features.md`
  - `next.md`
- Report phải tồn tại trên filesystem và được git track (nếu project đang track result files).

### 2.7. (Nên làm trong Gate A) Version immutability ở persistence
`ON CONFLICT DO UPDATE` đang cho phép ghi đè version cũ của Pattern / PayRule → phá invariant versioning.

**Yêu cầu tối thiểu:**
- Không cho phép update đè lên version đã tồn tại.
- Nếu conflict → throw hoặc ignore có kiểm soát (không silent overwrite).

---

## 3. Quyết định kiến trúc đã khóa (KHÔNG được tự đổi)

### D-A1 — Production Composition
Import phải được wire từ `main.dart` (hoặc factory production duy nhất).  
Test composition phải mirror đúng đường production.

### D-A2 — Atomic Commit
Toàn bộ side-effect của một lần commit import nằm trong **một** transaction SQLite.

### D-A3 — Window Replacement
- `ImportSession` có `windowStart` + `windowEnd` bắt buộc khi commit.
- Commit mới chỉ ảnh hưởng dữ liệu import cũ **trong window** của nó.
- OFF dates (kể cả mảng rỗng) của session mới nhất theo window là source of truth cho ngày đó.

### D-A4 — SWAP Imported
Dùng `effectiveJobId`. Không phụ thuộc `templateId` khác rỗng.

### D-A5 — Commit Guard
Không commit khi còn Pending. User phải explicit accept/reject trước.

### D-A6 — Documentation Truth
Checklist / features / next / result report phải khớp filesystem + test count thực tế.  
Không được tuyên bố file/report không tồn tại.

---

## 4. Acceptance Criteria (Gate A chỉ xanh khi TẤT CẢ đạt)

- [ ] `main.dart` (hoặc production factory) truyền `ImportRepository` vào `ScheduleService` → Import reachable.
- [ ] Có integration/composition test xác nhận `importEnabled == true` trên đường production.
- [ ] `commitImport` / `commitRoster` nằm trong một `db.transaction()`; fail → rollback toàn bộ.
- [ ] Không tồn tại trạng thái “session = COMMITTED nhưng occurrences chưa được ghi”.
- [ ] `ImportSession` có `windowStart` + `windowEnd`; commit mới ghi đè đúng window.
- [ ] Query OFF-date / suppress lấy session mới nhất theo window, **không** bỏ qua `committedOffDatesJson = '[]'`.
- [ ] SWAP hai occurrence cùng job (một hoặc cả hai là imported, `templateId` có thể rỗng) thành công.
- [ ] Commit UI/action bị disable khi còn Pending; có đường “Accept All Pending / High Confidence”.
- [ ] Version Pattern/PayRule không bị silent overwrite (ON CONFLICT không còn DO UPDATE vô tội vạ).
- [ ] Report Gate A tồn tại trên disk và được tham chiếu đúng trong `checklist.md`.
- [ ] `checklist.md` / `features.md` / `next.md` đã đồng bộ số liệu + trạng thái M2.
- [ ] Toàn bộ test liên quan (core + import + integration + widget) pass 100%.
- [ ] Không có regression trên Gate 0 (Time/Pattern) và các gate trước.

---

## 5. Test bắt buộc phải có / cập nhật

1. **Composition test**  
   Service tạo theo production path → `importEnabled == true`.

2. **Atomic commit test**  
   Giả lập lỗi ở bước ghi occurrences → session không được để ở `COMMITTED`, data rollback.

3. **Re-import window test**  
   - Import A (1–30), Import B (10–20) → ngày 10–20 lấy data B, ngày ngoài window vẫn giữ A (hoặc đúng semantics đã chốt).  
   - Session mới có `committedOffDatesJson = '[]'` vẫn được ưu tiên trong window.

4. **SWAP imported test**  
   Một occurrence imported (`templateId = ''`) SWAP với occurrence cùng job → thành công, UTC được re-resolve đúng.

5. **Commit guard test**  
   Còn Pending → không commit được. Sau Accept All Pending → commit được.

6. **Version immutability test**  
   Cố ghi đè version đã tồn tại → fail / không overwrite.

7. **Regression**  
   Toàn bộ test Gate 0–3 + M1/M1b/M2 cũ vẫn pass.

---

## 6. NEVER List

- NEVER để Import chỉ hoạt động trong widget test mà không reachable từ `main.dart`.
- NEVER đánh session = `COMMITTED` trước khi occurrences được ghi thành công trong cùng transaction.
- NEVER lọc bỏ session có `committedOffDatesJson = '[]'` khi resolve OFF/suppress.
- NEVER dùng `templateId` rỗng làm lý do từ chối SWAP cùng job.
- NEVER cho phép commit khi còn Pending items.
- NEVER silent overwrite version Pattern/PayRule.
- NEVER tuyên bố file report tồn tại trong checklist khi filesystem không có.
- NEVER mở M3 Pay UI trong task này.
- NEVER tự sửa expected của golden test cũ chỉ để “làm xanh”.

---

## 7. Định nghĩa “xong” — Báo cáo agent phải nộp

1. Diff tóm tắt từng file đã sửa (main.dart, ScheduleService, Import repositories, pattern_engine nếu đụng SWAP, UI commit guard…).
2. Log `flutter test` / `dart test` đầy đủ (số test trước/sau).
3. Xác nhận:
   - Import reachable từ production composition.
   - Commit atomic (có test rollback).
   - Re-import window + OFF `[]` đúng.
   - SWAP imported pass.
   - Commit guard đúng.
4. File report Gate A tồn tại trên disk.
5. `checklist.md` / `features.md` / `next.md` đã được cập nhật khớp thực tế.
6. Xác nhận không regression Gate 0.

**Gate A chỉ đóng khi báo cáo này được human review chấp nhận.  
Sau đó mới được mở prompt cho M3 Pay/Income.**

Bắt đầu làm việc.
```

---

Prompt trên đã khóa chặt các quyết định, liệt kê rõ lỗi phải sửa, acceptance criteria, test bắt buộc và NEVER list. Bạn có thể copy nguyên khối giao cho agent.

Bạn muốn tôi điều chỉnh thêm (ví dụ siết chặt hơn về SQL transaction pattern, hoặc thêm yêu cầu cụ thể cho `windowStart`/`windowEnd` validation) không?
