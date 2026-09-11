# Gate A + Gate B — Fix M2 Correctness, Production Wiring & Documentation Integrity

## Bối cảnh

Đã tự đọc trực tiếp code thật (không chỉ tin `checklist.md`/`features.md`) và xác nhận **toàn bộ lỗi P1 dưới đây vẫn còn nguyên trên đĩa**, đúng như `plan4.md` + 4 review (`plan4_review1` → `review4`) đã phát hiện:

- `lib/main.dart` dòng 38-41: `ScheduleService(...)` không có tham số `imports:` → Import không reachable từ app thật.
- `find_path` toàn project: `result13_gate_m2.txt` không tồn tại, dù `checklist.md` khẳng định có.
- `schedule_repository.dart` dòng 145: query vẫn còn điều kiện `committedOffDatesJson != '[]'`.
- `import_screen.dart` dòng 460 (`_canCommit`): vẫn cho phép commit khi còn candidate ở trạng thái `pending`.
- `import_types.dart`: chưa có field `windowStart`/`windowEnd` nào trong `ImportSession`.
- `checklist.md`: có đoạn text hỏng/gibberish (mục "SSS", phần hỏi M3 Pay) — dấu hiệu lỗi sinh text hàng loạt, giống sự cố mất dấu tiếng Việt đã từng xảy ra ở vòng Golden Test Suite trước đây.

**Không cần agent tự điều tra lại từ đầu** — 6 điểm trên đã được verify chắc chắn, đi thẳng vào sửa.

## Phạm vi

Chỉ sửa: `lib/main.dart` (hoặc factory production composition), `ScheduleService`, `ImportRepository`/`ScheduleRepository`, `pattern_engine.dart` (chỉ phần SWAP), `import_screen.dart` (UI commit guard), `PayRuleRepository`, `PatternRepository`, test tương ứng, và 3 file trạng thái (`checklist.md`, `features.md`, `next.md`).

**NGHIÊM CẤM:** M3 Pay/Income UI, OCR, Cloud/Sharing, bất kỳ tính năng mới nào ngoài danh sách dưới đây.

---

## GATE A — Correctness & Wiring

### A1. Wire Import vào production composition

`main.dart` phải truyền `ImportRepository(db)` vào `ScheduleService`, giống hệt cách widget test M2 đang làm. Thêm **composition test** (không phải widget test) xác nhận:
```dart
test('production ScheduleService has import enabled', () {
  // Dựng service theo ĐÚNG đường main.dart dùng — nếu main.dart có hàm
  // factory riêng, gọi thẳng factory đó, không viết lại logic composition
  // trong test (để tránh lặp lại đúng lỗi lần này: test đi con đường khác
  // với app thật).
  expect(service.importEnabled, isTrue);
});
```

### A2. Transaction-atomic Import Commit

Bọc `saveSession` + `replaceImportedOccurrences` trong **một** `db.transaction()` duy nhất. Đảm bảo cả 2 repository dùng chung 1 connection/transaction object (không phải 2 connection riêng — nếu vậy transaction vô nghĩa). Fail bất kỳ bước nào → rollback toàn bộ, session **không** được ở trạng thái `COMMITTED`.

### A3. Sửa query OFF-date theo window — CHỐT semantics (đã trọng tài giữa các review)

Thêm `windowStart`/`windowEnd` (bắt buộc, không cho null) vào `ImportSession`, gán khi commit dựa trên khoảng ngày của roster được import.

**Quy tắc CHỐT (review1/3/4 đồng thuận, review2 về bản chất tương đương):**
- Commit session mới → xóa/thay thế toàn bộ imported occurrences cũ của cùng `jobId` nằm **trong** `[windowStart, windowEnd]` của session mới.
- `committedOffDatesJson` của session mới — **kể cả khi là `[]`** — ghi đè hiệu lực OFF trong window đó (không filter theo `!= '[]'`).
- Ngày **ngoài** window của session mới vẫn giữ nguyên dữ liệu import trước đó (không đụng tới).
- Nếu người dùng muốn thay toàn bộ lịch job, họ phải import 1 file bao phủ toàn bộ khoảng thời gian mong muốn — hệ thống không tự suy diễn "thay toàn bộ".

Query mới:
```sql
SELECT committedOffDatesJson FROM import_sessions
WHERE jobId = ? AND state = 'committed'
  AND ? BETWEEN windowStart AND windowEnd
ORDER BY createdAt DESC, id DESC
LIMIT 1;
```

### A4. SWAP trên imported occurrence — CHỐT xử lý khi jobId rỗng

Thêm `effectiveJobId` (occurrence.jobId ?? template?.jobId ?? ''), dùng nó thay `templateId` để so sánh job khi SWAP.

**Quyết định CHỐT (khác với đề xuất "cho phép + log warning" của review2):** nếu `effectiveJobId` rỗng ở **bất kỳ bên nào** của cặp SWAP → **từ chối** với error code rõ ràng (thêm `ErrorCodes.ambiguousJob` hoặc tương đương), không tự suy đoán là an toàn rồi cho qua. Lý do: đây đúng loại "hành vi ngầm không tường minh" mà toàn bộ Gate 0 đã được lập ra để loại bỏ — không nên tái áp dụng ở Gate A.

### A5. Commit guard — CHỐT partial-commit là hành vi CÓ CHỦ ĐÍCH

Đọc code hiện tại (`_commitLabel`: *"Commit N approved row(s)"*) cho thấy ý định thiết kế ban đầu là **cho phép commit một phần** (chỉ ca đã duyệt, bỏ qua phần pending), không phải một bug ngẫu nhiên.

**Quyết định CHỐT — giữ partial-commit, nhưng làm UX tường minh thay vì mơ hồ:**
- Giữ hành vi: commit chỉ áp dụng cho candidate `approved`/`modified`; candidate `pending`/`rejected` bị bỏ qua, không đưa vào lịch.
- **Bắt buộc bổ sung:** trước khi commit, nếu còn candidate `pending`, hiển thị **cảnh báo rõ ràng** dạng: *"3 ca vẫn đang chờ duyệt (pending) sẽ KHÔNG được đưa vào lịch nếu bạn commit ngay. Bạn có muốn duyệt tiếp hay commit chỉ N ca đã duyệt?"* — yêu cầu xác nhận (dialog), không commit ngầm.
- Nút "Accept All High" giữ nguyên (không đổi thành "Accept All Pending" như review1 đề xuất — vì điều đó sẽ tự động approve cả LOW confidence, đi ngược INVARIANT-004).
- Cập nhật docstring/comment trong `import_screen.dart` ghi rõ đây là partial-commit có chủ đích, kèm lý do, để lần sau không ai lại tưởng là bug.

### A6. Version immutability ở persistence boundary

Sửa `PayRuleRepository.savePayRule()` và `PatternRepository.savePattern()`: nếu `id` đã tồn tại nhưng nội dung khác với bản đã lưu → ném exception, không `ON CONFLICT DO UPDATE` âm thầm ghi đè. Convention "ID mới cho mỗi version" phải được persistence layer enforce, không chỉ dựa vào caller tự giác.

---

## GATE B — Documentation & Verification Integrity

### B1. Đồng bộ trạng thái thật

Chạy `flutter test` toàn bộ, lấy số liệu thật, cập nhật khớp 100% giữa `checklist.md`, `features.md`, `next.md`. Không được để 3 file có 3 con số khác nhau như hiện tại (`checklist.md` nói 170, `features.md`/`next.md` nói số khác).

### B2. Dọn văn bản hỏng trong `checklist.md`

Mục "SSS" và đoạn "lý do UIP lummática, bị isolation-recloned..." ở phần M3 Pay trong `checklist.md` là text gibberish/hỏng — xóa và viết lại rõ ràng bằng tiếng Việt bình thường. Kiểm tra luôn `features.md`/`next.md` xem có đoạn tương tự không.

### B3. Tạo report thật cho Gate A/B

Tạo file report mới (VD `result14_gate_a.txt`) — **phải tồn tại thật trên đĩa**, tự kiểm tra bằng `ls`/`find` trước khi báo cáo "đã tạo", đúng bài học từ sự cố file CI trước đây (4 lần báo "đã tạo" nhưng không tồn tại).

### B4. Verify script (khuyến nghị, không bắt buộc P0)

Nếu có thời gian, viết `scripts/verify_status.sh` chạy sau mỗi gate: đếm test thật, so khớp với checklist, kiểm tra file `result*.txt` tồn tại — fail nếu lệch. Không bắt buộc cho Gate A/B này nhưng nên làm trước khi mở M3.

---

## NEVER List

- NEVER để Import chỉ hoạt động trong widget test mà không reachable từ `main.dart`.
- NEVER đánh session = `COMMITTED` trước khi occurrences được ghi thành công trong cùng transaction.
- NEVER lọc bỏ session có `committedOffDatesJson = '[]'` khi resolve OFF/suppress.
- NEVER cho phép SWAP khi `effectiveJobId` rỗng ở bất kỳ bên nào — phải từ chối tường minh, không suy đoán an toàn.
- NEVER cho phép commit một phần mà không cảnh báo rõ số lượng pending sẽ bị bỏ qua.
- NEVER silent overwrite version Pattern/PayRule.
- NEVER tuyên bố file report tồn tại trong checklist khi filesystem không có — tự `ls`/`find` xác nhận trước khi ghi vào báo cáo.
- NEVER mở M3 Pay UI trong task này.
- NEVER tự sửa expected của golden test cũ chỉ để "làm xanh".

## Acceptance Criteria

- [ ] AC-1: `main.dart` truyền `imports:`; composition test xác nhận `importEnabled == true` theo đúng đường production.
- [ ] AC-2: Commit trong 1 transaction; test giả lập lỗi ở bước ghi occurrences → session giữ nguyên trạng thái cũ, không thành `COMMITTED`.
- [ ] AC-3: `ImportSession` có `windowStart`/`windowEnd` bắt buộc; test Import A (OFF) → Import B cùng ngày (Day, `[]`) → render đúng là Day.
- [ ] AC-4: SWAP hai occurrence cùng `effectiveJobId` (kể cả imported) thành công; SWAP khi 1 bên `effectiveJobId` rỗng → bị từ chối có error code rõ ràng.
- [ ] AC-5: Commit hiển thị cảnh báo rõ số pending bị bỏ qua trước khi xác nhận; docstring ghi rõ đây là thiết kế có chủ đích.
- [ ] AC-6: Lưu `PayRule`/`Pattern` với ID trùng nhưng nội dung khác → exception, không ghi đè.
- [ ] AC-7: `result14_gate_a.txt` tồn tại thật (tự `find` xác nhận), `checklist.md`/`features.md`/`next.md` khớp số liệu thật.
- [ ] AC-8: `checklist.md` không còn đoạn text gibberish.
- [ ] AC-9: Toàn bộ test cũ (Gate 0-3, M1/M1b/M2) vẫn pass, không regression.

## Định nghĩa "xong"

1. Diff tóm tắt từng file.
2. Log `flutter test` đầy đủ, số test trước/sau.
3. Bằng chứng riêng cho AC-3 (test Import A/B OFF→Day) và AC-2 (test rollback).
4. Output `find`/`ls` xác nhận `result14_gate_a.txt` tồn tại — dán trực tiếp vào báo cáo.
5. Trích đoạn `checklist.md`/`features.md`/`next.md` sau khi đồng bộ.

**Nếu có điểm nào trong 6 quyết định CHỐT ở trên (window semantics, effectiveJobId rỗng, partial-commit) chưa rõ khi implement — dừng lại và hỏi, không tự suy diễn thêm.**

Gate A + B chỉ đóng khi báo cáo được human review chấp nhận. Sau đó mới mở M3 Pay/Income.
