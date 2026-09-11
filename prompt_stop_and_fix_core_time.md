# Dừng lại — quay lại hoàn thành Bước 1 trước, và sửa 1 bug thiết kế trong core/time

Đã đọc code `core/time` bạn vừa viết (`time_engine.dart`, `time_types.dart`, `EXPLANATION.md`, test file). Nhìn chung cấu trúc tốt, nhiều test khớp đúng golden cases. Nhưng có vấn đề quy trình cần chỉnh trước khi tiếp tục, cộng 2 việc kỹ thuật.

---

## 🔴 Vấn đề quy trình: Bước 1 chưa được duyệt, không nên bắt đầu Bước 2

Tôi chưa duyệt Golden Test Suite (Bước 1) — vẫn còn 2 việc tồn đọng nhiều vòng chưa xong: **file `.github/workflows/test.yml`** và **mục 5.7 trong `plan2.md`**. Yêu cầu ban đầu đã nói rõ: *"Dừng lại sau Bước 1... không bắt đầu code trước khi tôi duyệt Golden Test Suite."*

**Yêu cầu:** Tạm dừng thêm code mới cho `core/pattern`, `core/money`, hoặc bất kỳ module nào khác. Quay lại xử lý 2 việc còn nợ của Bước 1 trước — xem lại `prompt_diagnose_ci_and_57.md` đã gửi trước đó, trả lời đúng theo cấu trúc đã yêu cầu ở đó (đặc biệt: nếu có rào cản kỹ thuật khi tạo file CI, phải nói rõ thay vì im lặng bỏ qua).

Code `core/time` đã viết không bị bỏ — sẽ giữ lại và sửa tiếp sau khi Bước 1 được duyệt chính thức, không cần viết lại từ đầu.

---

## 🔴 Bug thiết kế trong `core/time`: End-time ambiguity bị tự động xử lý ngầm

Trong `resolveShift()`, khi **start time** rơi vào giờ nhập nhằng (ambiguous, do fall-back), code đúng: trả `error: 'AMBIGUOUS_LOCAL_TIME'` kèm `options`, không tự quyết định.

Nhưng khi **end time** rơi vào giờ nhập nhằng, code lại tự động chọn `options!.first` và trả về `isSuccess: true` — không có lỗi, không yêu cầu xác nhận:

```dart
if (endResult.ambiguity == DstAmbiguityType.ambiguous) {
  // For end time ambiguity, default to the first occurrence (before fall-back)
  // This is the safer default for shift end times
  final utcEnd = endResult.options!.first;
  ...
```

Đây vi phạm trực tiếp **D4** đã khóa ở `plan1_final_v2.md`: *"Không tự quyết định. Hiện dialog xác nhận thay vì tự làm tròn."* Không có ngoại lệ nào cho "end time" so với "start time" trong quyết định D4 gốc — cả hai đều phải xử lý giống nhau.

**Yêu cầu sửa:**
1. Khi `endResult.ambiguity == DstAmbiguityType.ambiguous`, trả về `error: 'AMBIGUOUS_LOCAL_TIME'` kèm `options`, giống hệt cách xử lý start time — **không tự chọn ngầm**.
2. Xóa comment "safer default" — đây không phải quyết định đã được duyệt, không nên tự thêm vào logic domain mà không hỏi.
3. Nếu bạn cho rằng có lý do chính đáng để xử lý end-time khác với start-time (VD: lý do UX cụ thể), **dừng lại và hỏi tôi trước khi code**, đúng tinh thần đã ghi ở `plan2.md` mục 1.2/1.3 — không tự quyết định rồi giải thích sau.

## 🟡 Bổ sung golden test case cho end-time ambiguous

Toàn bộ `time_engine_cases.json` hiện chỉ có `DST-004` test **start-time** ambiguous (`startTime: "01:00"` là giờ nhập nhằng). Không có case nào test khi **end-time** rơi vào giờ nhập nhằng trong khi start-time bình thường — đúng chỗ bug vừa phát hiện lọt qua vì không có test.

**Yêu cầu:** thêm case mới (VD `DST-008`) với start time bình thường + end time rơi vào giờ nhập nhằng của fall-back (VD: `shiftDate: 2026-10-31`, `startTime: 23:30`, `endTime: 01:30+1` tại `America/New_York` — giờ 01:00-02:00 sáng 01/11 là giờ lặp lại). Expected: `error: 'AMBIGUOUS_LOCAL_TIME'`, có `options`.

## 🟡 Sửa test Dart để đọc từ JSON gốc, không hard-code lại

`time_engine_test.dart` hiện gõ tay lại toàn bộ input/expected value trùng với `time_engine_cases.json` — đúng loại vấn đề đã sửa ở `verify_all_cases.mjs` trước đây (hard-code bản sao thay vì đọc nguồn thật), giờ lặp lại ở chỗ khác.

**Yêu cầu:** viết test Dart để **đọc trực tiếp** `test/golden/time_engine_cases.json` (parse JSON, loop qua từng case, gọi `resolveShift()` với input từ file, so sánh với expected cũng từ file) — thay vì liệt kê từng test case bằng tay với số liệu gõ lại. Điều này đảm bảo sửa JSON gốc sau này sẽ tự động phản ánh vào test, không bị trôi dạt giữa 2 nguồn.

---

## Thứ tự xử lý

1. Trả lời chẩn đoán về file CI + hoàn thành mục 5.7 (Bước 1) — **làm trước tiên**
2. Sau khi Bước 1 được duyệt chính thức, quay lại sửa bug end-time ambiguity + bổ sung DST-008 + sửa test Dart đọc từ JSON gốc

Không cần gộp tất cả vào 1 lần nộp — có thể xử lý theo đúng thứ tự trên và tôi sẽ review từng phần khi có kết quả.
