# Plan11 — M4.5 OCR Spike Test (GATE — không phải kiến trúc lớn)

Ngày: 2026-09-10 · Trạng thái: **SPEC — CHỜ USER DUYỆT** (không code OCR trước khi duyệt)
Nguồn: `plan1_final_v2.md` roadmap (M4.5), `next.md` (M4.5 section), plan8 §14 (deferred — chỉ mở sau khi RC pass review; RC review PASS 2026-09-10 → đủ điều kiện mở spike).

---

## 1. Mục đích — trả lời MỘT câu hỏi

> **OCR có đủ chính xác cho roster thật của người dùng mục tiêu không?**

M4.5 là **gate thí nghiệm, không phải feature build**. Kết quả = 1 báo cáo số liệu
để quyết định có mở M5 (OCR Import) hay không. Không commit kiến trúc OCR đầu cơ.

## 2. Ngưỡng chốt (đề xuất — user duyệt trước khi chạy)

| Metric | Ngưỡng | Ý nghĩa |
|---|---|---|
| Dates đúng | **≥ 70%** | Ngày ca parse đúng |
| Shift types đúng | **≥ 60%** | Day/Night/OFF phân loại đúng |
| Start–End đúng (thông tin thêm) | ghi nhận, không chốt | ảnh hưởng đến review workload |

**Nếu dates < 70% hoặc shift types < 60% → KHÔNG làm M5.** Ghi rõ vào spec để
tránh tranh cãi sau khi có số liệu (plan1 mandate E3).

## 3. Phạm vi spike — làm gì / KHÔNG làm gì

### Làm (chỉ metrics)
1. Thu thập **20–30 roster thật** (ảnh chụp màn hình app bệnh viện / ảnh giấy lịch / PDF).
2. Chạy qua OCR pipeline thử nghiệm (Tesseract hoặc PaddleOCR — chạy off-app).
3. Parse output qua regex/parser TÁI DÙNG `core/import` hiện có (parseDocument với
   sourceType pasteText — OCR chỉ là bước sinh TEXT, sau đó đi đúng pipeline M2).
4. Đo % đúng bằng cách so từng case với kết quả người đánh dấu (ground truth).

### KHÔNG làm
- ❌ Tích hợp OCR vào app (pubspec dependency mới, platform channel).
- ❌ UI mới (màn hình chọn ảnh), model mới, migration.
- ❌ Sửa `core/import` cho "khớp" OCR output — pipeline dùng nguyên trạng.

## 4. Nguồn roster — cần USER cung cấp

- 20–30 ảnh/PDF roster thật (nurse shift workers US/UK/DE).
- Ưu tiên đa dạng: ảnh nét/ảnh mờ, bảng/nhân dòng, có/không header.
- Ground truth: mỗi roster đi kèm 1 bản chép tay đúng (user hoặc người đánh dấu ghi).

## 5. Thước đo chi tiết (định nghĩa "đúng")

- **Date đúng**: ngày + tháng trùng ground truth (năm lấy từ reference date).
- **Shift type đúng**: phân loại Day/Night/Evening/OFF trùng (từ label hoặc giờ).
- Tính trên TỔNG số dòng ca của tất cả roster (không phải trung bình per-roster).
- Ghi thêm: số dòng OCR bỏ sót (miss) / bịa thêm (hallucination).

## 6. Quy trình thực thi (khi được duyệt + có roster)

```
1. User cung cấp 20–30 roster + ground truth
2. Setup máy chạy OCR ngoài app (python/tesseract hoặc paddle — off-repo)
3. Mỗi roster: OCR → raw text → parseDocument(pasteText) → candidates
4. So candidates vs ground truth → bảng metric
5. Báo cáo result19_ocr_spike.txt: số liệu + verdict PASS/FAIL ngưỡng
6. User quyết định: mở M5 (nếu PASS) hoặc dừng ở CSV/paste (nếu FAIL)
```

## 7. Rủi ro / lưu ý

- OCR tiếng Việt/hợp đồng hóa hoa văn từng bệnh viện — ground truth phải từ chính
  những roster đó, không dùng template giả.
- **Không thay thế được CSV/paste**: ngay cả khi PASS, OCR là nguồn bậc 4 (sau
  pattern/paste/CSV), luôn qua Review bắt buộc (INVARIANT-004 không đổi).
- Chi phí spike: thấp (off-app, không đụng code app) — rủi ro chính là không đủ
  roster thật để có ý nghĩa thống kê.

## 8. Điều kiện mở spike (checklist)

- [ ] User duyệt spec này (đặc biệt: ngưỡng 70/60)
- [ ] User cung cấp 20–30 roster thật + ground truth
- [ ] Quyết định machine chạy OCR (máy user — sandbox không có python/tesseract)
