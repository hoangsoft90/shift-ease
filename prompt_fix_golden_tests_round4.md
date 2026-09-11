# Yêu cầu hoàn thành 2 việc còn lại (vòng 4)

Đã đọc trực tiếp code trong project tại `/Users/hoang/htdocs_apps/ShiftEase/`. 2/3 việc của vòng trước đã đúng:

- ✅ `verify_all_cases.mjs` — đã sửa đúng, đọc trực tiếp từ `time_engine_cases.json`, không còn hard-code bản sao (review code, logic đúng)
- ✅ `PAY-014` — dữ liệu tốt, đã tự tính tay khớp hoàn toàn ($1505 = $490+$490+$525), quy tắc LIFO rõ ràng

Còn 2 việc chưa xong:

---

## 🔴 Việc 1: File CI vẫn không tồn tại — lần thứ 3

Đã tìm toàn bộ `/Users/hoang/htdocs_apps/ShiftEase/` (không chỉ `source/`), kiểm tra riêng cả khả năng có thư mục `.github` — **không có file `.yml` nào, không có thư mục `.github`**. Đây là lần thứ 3 tôi xác nhận file này không tồn tại, dù 2 báo cáo trước đó (`result1.txt`, `result2.txt`) đều đánh dấu đã hoàn thành.

**Yêu cầu:**
1. Tạo thật file `.github/workflows/test.yml` tại đúng vị trí gốc của repo (không phải trong `source/` nếu đó không phải root — xác nhận rõ cấu trúc thư mục repo trước khi tạo, vì tôi thấy `plan2.md` thực tế nằm ở `.plan/plan2.md` tại root, không phải trong `source/`, nên cấu trúc thư mục có thể không như bạn nghĩ).
2. **Dán toàn bộ nội dung file trực tiếp vào báo cáo lần này** — không chỉ liệt kê "đã tạo [x]". Tôi sẽ đọc trực tiếp file trên đĩa để đối chiếu với nội dung bạn dán, xác nhận khớp.
3. Trước khi nộp báo cáo, tự chạy lệnh liệt kê file (`find`, `ls -la`, hoặc tương đương) trên chính đường dẫn file vừa tạo và dán output đó vào báo cáo làm bằng chứng — không dựa vào việc "tool report success" là đủ.

## 🟡 Việc 2: Bổ sung mục 5.7 vào `plan2.md`

`PAY-014` đã document rule LIFO trong test case, nhưng `plan2.md` (tại `.plan/plan2.md`) mục 5 vẫn dừng ở "5.6 PayRuleTemplate" — chưa có phần mô tả chính thức quy tắc phân bổ OT theo tuần.

**Yêu cầu:** thêm mục **"5.7 Weekly Overtime Allocation"** vào `plan2.md`, nội dung tối thiểu gồm:
- Quy tắc đã chọn: **LIFO** (ca cuối cùng theo thứ tự thời gian trong tuần nhận giờ OT trước)
- Lý do chọn LIFO thay vì các cách khác (chia đều theo tỷ lệ giữa các ca, hoặc gán vào ca đầu tiên/FIFO) — nêu ngắn gọn trade-off
- Pseudo-code hoặc mô tả thuật toán: khi có N ca trong tuần, tổng giờ vượt ngưỡng W, thuật toán duyệt ca theo thứ tự nào và dừng khi nào
- Edge case cần lưu ý: nếu ca cuối cùng không đủ giờ để hấp thụ hết phần OT còn lại (VD: 3 ca 14h+14h+14h+1h, ca cuối chỉ 1h nhưng cần hấp thụ 2h OT) — hệ thống xử lý thế nào? Tràn sang ca trước đó, hay giữ nguyên logic khác?
- Tham chiếu ngược lại `PAY-014` như ví dụ minh họa

---

## Sau khi sửa xong

Gửi lại:
1. Nội dung đầy đủ file `.github/workflows/test.yml` dán trực tiếp trong báo cáo, kèm output lệnh `find`/`ls` xác nhận file tồn tại trên đĩa
2. Đoạn mục 5.7 đã thêm vào `plan2.md`, dán trực tiếp trong báo cáo để tôi đối chiếu

Sau khi cả 2 việc đạt và tôi tự kiểm tra lại trực tiếp trên file (không chỉ đọc báo cáo), sẽ duyệt để chuyển sang Bước 2: Implement `core/time`.
