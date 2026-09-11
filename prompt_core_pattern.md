# Bước 3 — Implement `core/pattern` (CHỈ việc này, không việc gì khác)

Bước 1 (Golden Test Suite + CI) và Bước 2 (`core/time`) đã được duyệt chính thức. Giờ làm **Bước 3: `core/pattern`** — module bảo vệ thứ 2 trong chuỗi `core/time → core/pattern → core/money`.

**Đây là việc DUY NHẤT của lượt này.** Không động vào `core/time`, không bắt đầu `core/money`, không viết UI/features, không sửa CI hay plan2.md. Nếu thấy vấn đề ở chỗ khác trong lúc làm — ghi chú lại, báo cáo cuối, đừng tự tiện sửa.

---

## Phạm vi

Đọc kỹ `plan2.md` mục 4 (Quy trình Pattern / Override) trước khi code — đây là spec nguồn duy nhất, không suy diễn thêm.

Tạo:
```
lib/core/pattern/pattern_types.dart      (interfaces/types tương ứng mục 2.1, 2.2, 2.4, 11 của plan1_final_v2 + plan2)
lib/core/pattern/pattern_engine.dart     (3 hàm chính bên dưới)
lib/core/pattern/EXPLANATION.md          (giải thích model, giống EXPLANATION.md của core/time)
```

### 3 hàm bắt buộc (mục 4.1, 4.2, 4.3 của plan2.md)

1. **`projectOccurrences(pattern, rangeStart, rangeEnd)`** — sinh baseline occurrences từ Pattern trong khoảng ngày.
   - **Bắt buộc gọi hàm `resolveShift()`/tương đương đã có sẵn trong `core/time`** để tính `startDateTimeUtc`/`endDateTimeUtc` — **KHÔNG tự viết lại logic timezone/DST**. `core/pattern` phụ thuộc `core/time`, không phải ngược lại (xem sơ đồ dependency mục 1.1 của plan2.md).
   - Nếu `resolveShift()` trả về lỗi (`AMBIGUOUS_LOCAL_TIME`/`NONEXISTENT_LOCAL_TIME`) cho một occurrence nào đó trong lúc projection hàng loạt — occurrence đó phải được đánh dấu rõ (không được âm thầm bỏ qua hoặc âm thầm chọn 1 phương án), trả về kèm theo danh sách occurrences khác vẫn resolve bình thường. Nếu spec không nói rõ hành vi này, dừng lại hỏi tôi thay vì tự quyết định.

2. **`applyOverride(occurrences, override)`** — áp dụng 1 `Override` lên danh sách occurrences. Phải xử lý đủ **cả 6 operation**: `CREATE`, `UPDATE`, `DELETE`, `REPLACE`, `SPLIT`, `SWAP` — xem payload cụ thể từng loại ở mục 4.2. Không được chỉ làm 2-3 loại rồi để lại TODO.

3. **`renderEffectiveSchedule(pattern, overrides, rangeStart, rangeEnd)`** — `baseline + overrides`, tính khi render (không lưu cứng), theo đúng mục 4.3.

### Pattern Versioning (mục 2.2, 4.4, D1)

- `ShiftPattern` dùng chung `VersionedEntity { effectiveFrom, effectiveUntil }`.
- Viết hàm resolve version đang active tại 1 ngày cụ thể (tương tự `getActivePayRule` ở mục 5.5, áp dụng logic tương tự cho Pattern).
- **INVARIANT-001**: sửa 1 occurrence (override) không bao giờ được mutate Pattern gốc — Pattern chỉ đổi qua tạo version mới (D1), không bao giờ patch tại chỗ.

---

## Yêu cầu test (bắt buộc, đọc kỹ trước khi code để thiết kế đúng ngay từ đầu)

### 1. Property tests — theo đúng mục 7.2 của plan2.md, cả 3 property, không được bớt:
- **Property 1 — Cycle repetition**: `occurrence[n + cycleLengthDays]` cùng vị trí pattern như `occurrence[n]`.
- **Property 2 — Override isolation (INVARIANT-001)**: sửa occurrence #N không làm thay đổi occurrence #N+1 trở đi.
- **Property 3 — Duration correctness (INVARIANT-002)**: duration luôn tính từ UTC instants đã resolve qua `core/time`, không tự tính tay.

File: `test/core/property/pattern_property_test.dart` (đúng path CI đã cấu hình sẵn ở `.github/workflows/test.yml` — path đó hiện đang trỏ tới `test/`, bạn cần tạo cấu trúc thư mục để khớp).

### 2. Example-based tests cho từng Override operation
Không có golden JSON cho pattern (khác với time/money) — viết test case cụ thể trực tiếp trong Dart cho cả 6 operation (CREATE/UPDATE/DELETE/REPLACE/SPLIT/SWAP), tối thiểu 1 case rõ ràng mỗi loại, bám theo đúng ví dụ trong mục 4.2 của plan2.md.

File: `test/core/pattern/pattern_engine_test.dart`

### 3. Integration test với core/time (bắt buộc — đây là chỗ dễ bug nhất)
Ít nhất 1 test case pattern sinh ra occurrence **bắc qua DST transition** (dùng lại 1 trong các case đã có ở `time_engine_cases.json`, VD DST-001 hoặc DST-002) để xác nhận `projectOccurrences` thật sự gọi đúng `core/time` chứ không tự tính riêng. Nếu ai đó vô tình viết lại logic DST trong `core/pattern`, test này phải bắt được.

### 4. Test versioning boundary
Case switch pattern version giữa chừng (giống ví dụ mục 4.4: Pattern A hết hạn Sep 30, Pattern B bắt đầu Oct 1) — xác nhận occurrences trước Sep 30 dùng Pattern A, từ Oct 1 dùng Pattern B, và occurrences cũ (trước Oct 1) giữ nguyên khi Pattern B được tạo (INVARIANT-001 áp dụng cho version switch, không chỉ cho override).

---

## Deliverable đi kèm

`EXPLANATION.md` — giải thích rõ mô hình **Pattern = source of truth, Occurrence = projection, Override = lớp ghi đè, Effective Schedule = Pattern + Overrides tính khi render** (đúng nguyên văn định nghĩa ở đầu mục 4 của plan2.md), có annotation `INVARIANT-001`/`D1`/`D2` ngay trong code comment ở chỗ liên quan — giống cách đã làm tốt ở `core/time/EXPLANATION.md`.

---

## Sau khi xong

**Dừng lại, báo cáo, không tự động sang `core/money`.** Tôi sẽ review — đúng quy trình "Human-in-the-loop cho module lõi" đã ghi ở mục 10 của `plan1_final_v2.md`: mỗi module lõi cần unit test + file giải thích, con người review trước khi merge.
