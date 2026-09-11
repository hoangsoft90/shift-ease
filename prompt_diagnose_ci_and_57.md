# File CI và mục 5.7 vẫn chưa xong sau nhiều lần yêu cầu — cần làm rõ nguyên nhân

Đã kiểm tra trực tiếp trên project lần thứ 4: `.github/workflows/test.yml` vẫn không tồn tại, và `plan2.md` chưa được chạm vào để thêm mục 5.7 (xác nhận qua timestamp: `plan2.md` modified lúc 13:28, trong khi `money_engine_cases.json` chứa PAY-014 modified lúc 14:42 — tức là plan2.md không hề được sửa sau đó).

Tôi tách 2 việc này ra riêng, xử lý độc lập, và với việc CI cần bạn trả lời rõ nguyên nhân trước khi thử lại.

---

## Việc 1: File CI — cần chẩn đoán trước khi thử lại

Câu hỏi trực tiếp: **Bạn có gặp lỗi, giới hạn quyền, hoặc rào cản kỹ thuật nào khi tạo file `.github/workflows/test.yml` hoặc thư mục `.github` không?**

Trả lời rõ theo 1 trong 2 hướng:

**(a) Nếu có rào cản** (VD: môi trường chặn tạo file trong `.github/`, giới hạn quyền ghi, hoặc bất kỳ lý do kỹ thuật nào khác): nói rõ chính xác lỗi gặp phải, không cần cố tạo bằng được. Nếu vậy, phương án thay thế: tạo nội dung CI config tại một đường dẫn khác không bị chặn (VD: `ci/test.yml` hoặc `docs/ci-config.yml`) kèm ghi chú rõ "cần di chuyển vào `.github/workflows/` thủ công khi merge vào repo chính thức, do môi trường hiện tại không cho phép tạo thư mục `.github`".

**(b) Nếu không có rào cản gì** (tức là chỉ đơn giản là bị bỏ sót/quên): tạo file thật ngay tại `.github/workflows/test.yml`, rồi **bắt buộc** chạy lệnh xác nhận sự tồn tại (`ls -la .github/workflows/` hoặc tương đương) và dán nguyên văn output đó vào báo cáo — không tự diễn giải "đã tạo thành công" bằng lời, phải có output lệnh làm bằng chứng.


## Việc 2: Mục 5.7 `plan2.md` — chỉ cần viết văn bản, tách riêng để không bị bỏ sót

Đây thuần túy là việc viết thêm 1 đoạn văn bản vào file đã có sẵn, không có rủi ro kỹ thuật nào — nên không có lý do để bị bỏ sót nhiều lần. Yêu cầu lại nguyên văn, không đổi:

Thêm mục **"5.7 Weekly Overtime Allocation"** vào `plan2.md` (đúng file tại `.plan/plan2.md`), sau mục 5.6 hiện có, gồm:

- Quy tắc đã chọn: **LIFO** (ca cuối cùng theo thứ tự thời gian trong tuần nhận giờ OT trước) — đúng như đã dùng trong `PAY-014`
- Lý do chọn LIFO thay vì chia đều theo tỷ lệ hoặc FIFO — nêu ngắn gọn trade-off
- Pseudo-code hoặc mô tả thuật toán: duyệt ca theo thứ tự nào, dừng khi nào
- Edge case: nếu ca cuối cùng không đủ giờ để hấp thụ hết phần OT còn lại thì xử lý thế nào (tràn sang ca trước đó, hay theo logic khác)
- Tham chiếu ngược lại `PAY-014` làm ví dụ minh họa

**Làm việc này trước, độc lập với việc 1**, và dán nguyên văn đoạn mới thêm vào báo cáo để tôi đối chiếu trực tiếp với file trên đĩa.

---

## Sau khi xong

Gửi lại:
1. Câu trả lời rõ ràng cho câu hỏi chẩn đoán ở Việc 1 (a) hoặc (b), kèm bằng chứng tương ứng
2. Đoạn mục 5.7 đã thêm, dán nguyên văn

Tôi sẽ tự kiểm tra lại trực tiếp trên file trước khi duyệt sang Bước 2.
