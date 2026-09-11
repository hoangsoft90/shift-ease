# Yêu cầu sửa vòng cuối cho `plan2.md`

Cảm ơn — 5/6 điểm đã sửa đúng và có bằng chứng đối chiếu được (DST-001/002/003, overtime double-counting, CalendarEvent subtypes, PayRuleTemplate, Money Engine golden tests, OCR Spike Test milestone). Nhưng có **1 vấn đề mới nghiêm trọng** phát sinh từ chính bước "sửa encoding", và **1 lỗi mới** trong DST-005. Cần sửa cả hai trước khi tôi duyệt.

---

## 🔴 Việc 1 (ưu tiên cao nhất): Khôi phục dấu tiếng Việt — KHÔNG dùng script tự động

Tôi chỉ yêu cầu sửa 3 chỗ ký tự lạ cụ thể (dòng ~324, ~765, ~786 ở bản trước). Nhưng bạn đã chạy một lượt khử encoding trên **toàn bộ văn bản** (từ dòng 36 trở đi, gần 1500 dòng) và xóa sạch dấu tiếng Việt luôn thể — vượt xa yêu cầu.

Hậu quả nghiêm trọng nhất: đúng 2 câu cảnh báo quan trọng nhất tài liệu bị đổi nghĩa hoàn toàn.

**Mục 1.2, dòng đầu:**
```
Bản hiện tại: "Copy nguyen tu plan1_final_v2.md muc 10. Duoc sua/nloi long."
```
Chữ "Không được phép" đã biến mất, câu giờ đọc thành "Được sửa/nới lỏng" — **ngược lại hoàn toàn** với ý định gốc. Sửa lại đúng nguyên văn:
```
"Copy nguyên từ plan1_final_v2.md mục 10. Không được phép sửa/nới lỏng."
```

**Mục 1.3, dòng đầu** — lỗi y hệt:
```
Bản hiện tại: "Copy nguyen tu plan1_final_v2.md. Duoc sua/nloi long."
Sửa lại:      "Copy nguyên từ plan1_final_v2.md. Không được phép sửa/nới lỏng."
```

**Yêu cầu cụ thể:**
1. Khôi phục dấu tiếng Việt cho **toàn bộ văn bản**, không chỉ 2 câu trên — sửa thủ công từng đoạn, không chạy lại script transliteration/ASCII-strip.
2. Sau khi sửa, đọc lại toàn bộ mục 1.2 và 1.3 để xác nhận nghĩa câu đúng với bản gốc `plan1_final_v2.md` (Invariants và NEVER list là "không được sửa", không phải "được sửa").
3. Quét lại toàn file một lần nữa tìm các cụm phủ định khác có khả năng bị mất chữ tương tự (tìm kiểu "Khong duoc", "khong duoc phep", "Duoc" đứng đầu câu) — xác nhận không còn chỗ nào bị đảo nghĩa.
4. Nếu công cụ bạn dùng để sửa 3 ký tự lỗi ban đầu là script tự động toàn văn bản, đừng dùng lại cách đó — sửa trực tiếp từng vị trí lỗi cụ thể.

## 🟡 Việc 2: Redesign DST-005 (EU fall-back case)

Case hiện tại có 2 vấn đề:

**(a) Mâu thuẫn nội bộ:** `utcStart: 2026-10-25T22:30:00Z` và `utcEnd: 2026-10-26T00:30:00Z` chênh nhau đúng 2 giờ, nhưng field `durationHours` lại ghi 3.0.

**(b) Lỗi thiết kế case, không chỉ lỗi tính toán:** Ca 23:30→01:30 (chỉ 2 tiếng theo giờ tường) **không bao giờ chạm được** khung giờ nhập nhằng của fall-back (2:00–3:00 sáng), vì ca đã kết thúc lúc 1:30, trước 2:00. Vậy dù chọn `shiftDate` nào, case này cũng không kiểm tra được điều nó tuyên bố kiểm tra (ca cắt ngang đêm đổi giờ).

**Yêu cầu:** Thiết kế lại DST-005 với một ca thực sự trải dài qua khung 2:00–3:00 sáng giờ địa phương của `Europe/Berlin` vào ngày chuyển giờ mùa thu 2026 (Chủ Nhật cuối cùng của tháng 10). Gợi ý: dùng cấu trúc tương tự DST-002 đã đúng (ca đêm dài, VD 22:00 → 06:00 hôm sau) nhưng với timezone Berlin, để đảm bảo ca thực sự bao trùm thời điểm chuyển giờ.

Sau khi thiết kế lại, tính `utcStart`/`utcEnt`/`durationHours` bằng cùng phương pháp đã dùng cho DST-001/002 (Intl API dựa trên IANA tz database), và tự kiểm tra chênh lệch `utcEnd - utcStart` khớp với `durationHours` ghi trong case trước khi nộp lại.

---

## Sau khi sửa xong

Gửi lại `plan2.md` kèm:
1. Đoạn trích mục 1.2 và 1.3 sau khi khôi phục, để tôi đối chiếu trực tiếp với bản gốc `plan1_final_v2.md`
2. Case DST-005 mới kèm phép tính `utcEnd - utcStart` cho thấy khớp với `durationHours`
3. Xác nhận đã quét toàn file tìm các cụm phủ định khác có nguy cơ bị đảo nghĩa tương tự

Nếu cả hai việc trên đạt, tôi sẽ duyệt `plan2.md` để chuyển sang bước viết Golden Test Suite đầy đủ và bắt đầu implementation `core/time` trước tiên.
