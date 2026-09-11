# Yêu cầu sửa trước khi duyệt Bước 1 (vòng 3)

Đã kiểm tra trực tiếp file thật trong dự án (`/Users/hoang/htdocs_apps/ShiftEase/source/`), không chỉ đọc báo cáo. Toán học ở SH-002 và PAY-005 đã đúng. Nhưng phát hiện 1 vấn đề nghiêm trọng về độ tin cậy báo cáo và 2 việc kỹ thuật cần hoàn thiện.

---

## 🔴 Việc 1 (ưu tiên cao nhất): File CI không tồn tại

`result1.txt` và `result2.txt` đều liệt kê `.github/workflows/test.yml` là đã tạo, đánh dấu `[x]` đã sửa. Nhưng file này **không tồn tại ở bất kỳ đâu trong dự án** — tôi đã tìm toàn bộ thư mục, không có file `.yml` nào.

**Yêu cầu:**
- Tạo thật file `.github/workflows/test.yml` với đúng 5 CI job đã mô tả (`core-time-tests`, `core-pattern-tests`, `core-money-tests`, `import-tests`, `static-analysis`), gate rule chặn merge nếu golden test fail hoặc có analyzer warning trong `lib/core/`.
- Đây là lần thứ 2 tôi phát hiện có sự khác biệt giữa "báo cáo nói đã làm" và "thực tế trên đĩa" (lần 1 là thiếu file thật nói chung, lần 2 là file cụ thể không tồn tại dù được đánh dấu hoàn thành). **Trước khi nộp báo cáo lần tới, tự chạy `find`/`ls` xác nhận từng file trong danh sách "đã tạo" thực sự tồn tại trên đĩa**, không chỉ liệt kê theo trí nhớ những gì định làm.

## 🔴 Việc 2: Sửa `verify_all_cases.mjs` — đọc file JSON thật, không hard-code bản sao

Script hiện tại tự hard-code lại 16 case ngay trong file `.mjs`, không đọc từ `test/golden/time_engine_cases.json`. Hậu quả: 4 case mới nhất (`MIDNIGHT-001`, `INVARIANT-002-001`, `PATTERN-PROP-001`, `PATTERN-PROP-002`) chưa từng được script chạy qua, dù metadata của file JSON tự nhận "tất cả giá trị UTC đã được verify bằng script".

**Yêu cầu:**
- Sửa script để **đọc trực tiếp** `test/golden/time_engine_cases.json` (VD: `JSON.parse(fs.readFileSync(...))`), không giữ bản sao hard-code trong `.mjs`.
- Đảm bảo script verify được toàn bộ case có `utcStart`/`utcEnd` trong file, bao gồm `MIDNIGHT-001` và `INVARIANT-002-001` (2 case này tôi đã tự tính tay và thấy đúng — nhưng cần script xác nhận độc lập, không chỉ tôi).
- `PATTERN-PROP-001`/`002` không có UTC nên không thuộc phạm vi script này — không cần thêm, chỉ cần verify khi `core/pattern` đã code (Bước 3).
- Chạy lại script sau khi sửa, output phải hiện đúng **"Total cases: 18"** (16 case có UTC + DST-003/004 dạng error, hoặc theo cách đếm bạn chọn — miễn là con số khớp với số case thực có trong JSON, không lệch nữa) và gửi log đầy đủ.

## 🟡 Việc 3: PAY-005 — bổ sung case multi-shift/tuần

Câu hỏi tôi hỏi ở vòng 2 vẫn chưa được trả lời: khi tuần có **nhiều ca thật** cộng lại thành >40h, hệ thống quyết định gán giờ OT cho ca nào?

**Yêu cầu:** thêm 1 case mới (VD `PAY-014`) với **ít nhất 3 ca cụ thể trong cùng 1 tuần**, tổng cộng vượt ngưỡng 40h (VD: 3 ca 14h = 42h). Case phải cho thấy:
- Input là danh sách nhiều ca riêng biệt (ngày, giờ, không phải 1 con số `weeklyHours` cho sẵn)
- Output: mỗi ca nhận breakdown pay riêng, tổng OT hours toàn tuần = đúng phần vượt ngưỡng (không nhân đôi ở ca nào)
- Ghi rõ quy tắc phân bổ đã chọn (VD: OT tính vào ca cuối cùng theo thứ tự thời gian trong tuần, hay chia đều, hay theo rule khác) — đây là quyết định thiết kế cần document lại, không chỉ code ngầm.

Nếu logic phân bổ theo tuần chưa tồn tại trong `plan2.md`, bổ sung luôn một đoạn ngắn vào mục 5 của `plan2.md` mô tả quy tắc này trước khi viết case.

---

## Sau khi sửa xong

Gửi lại:
1. File `.github/workflows/test.yml` thật, kèm xác nhận đường dẫn đã kiểm tra tồn tại
2. `verify_all_cases.mjs` đã sửa (đọc từ JSON thật) + log chạy đầy đủ cho toàn bộ case có UTC
3. Case `PAY-014` mới + đoạn bổ sung vào `plan2.md` mục 5 giải thích quy tắc phân bổ OT theo tuần

Sau khi cả 3 việc đạt và tôi tự kiểm tra lại trực tiếp trên file, sẽ duyệt để chuyển sang Bước 2: Implement `core/time`.
