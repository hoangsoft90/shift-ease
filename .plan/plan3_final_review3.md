plan3_final_review1.md
MD 23.45KB
plan3_final_review2.md
MD 11.57KB
plan3_final.md
MD 32.99KB
phân tích solution plan3_final.md và review của các AI khác plan3_final_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Phân tích tổng hợp `plan3_final.md` và các review – Ý kiến đóng góp & phản biện
===============================================================================

Tôi đánh giá rất cao chất lượng của ba tài liệu này. `plan3_final.md` thể hiện một bước tiến lớn: từ một ý tưởng trừu tượng, chúng ta đã có một bản kế hoạch kỹ thuật chi tiết, dựa trên bằng chứng thực nghiệm và các quyết định thiết kế rõ ràng. Các review, đặc biệt là `plan3_final_review1.md` và `review2.md`, đã chỉ ra chính xác các điểm nghẽn và đề xuất các giải pháp cụ thể.

Tuy nhiên, tôi vẫn nhận thấy một số điểm còn thiếu hoặc chưa được thống nhất hoàn toàn. Dưới đây là phân tích của tôi.

* * *

1\. Điểm mạnh tuyệt đối của `plan3_final.md`
--------------------------------------------

*   **Bằng chứng thực nghiệm**: Plan không chỉ suy đoán mà đã `probe` trực tiếp code và thư viện `timezone`, đưa ra các kết quả cụ thể (E1–E12). Điều này giúp các quyết định thiết kế có cơ sở vững chắc.
    
*   **Phân loại lỗi rõ ràng**: Các lỗi P0 được xác định và có vị trí cụ thể, giúp AI agent biết chính xác cần sửa gì.
    
*   **Quyết định thiết kế (D-series) được khóa chặt**: Các lựa chọn về semantics được ghi rõ, tránh để agent tự suy diễn.
    
*   **Spec code chi tiết**: Đưa ra pseudo-code và hướng dẫn cụ thể cho từng file, giảm thiểu rủi ro agent hiểu sai.
    
*   **Test spec và NEVER list**: Đây là những ràng buộc mạnh mẽ để đảm bảo chất lượng và ngăn agent “sáng tạo” sai hướng.
    
*   **Phạm vi Gate 0 được giới hạn nghiêm ngặt**: Cấm chạm vào money/UI/persistence, đúng với chiến lược.
    

* * *

2\. Những điểm cần bổ sung hoặc điều chỉnh
------------------------------------------

### 🔴 P0-9: Thiếu mã lỗi `OCCURRENCE_NOT_FOUND`

Cả hai review đều nhấn mạnh sự cần thiết của mã lỗi này, nhưng `plan3_final.md` chưa đưa vào danh sách error codes (D7). Hiện tại, nếu một `UPDATE`, `REPLACE`, `SPLIT`, `SWAP`, `DELETE` trỏ tới một `occurrenceId` không tồn tại (do đã bị xóa, hoặc ID thay đổi sau SPLIT, hoặc do lỗi nhập), engine sẽ không có cách nào báo lỗi một cách rõ ràng. Nếu không, agent có thể quyết định trả về list cũ mà không issue, gây **silent no-op** – điều mà toàn bộ plan đang cố gắng loại bỏ.

**Đề xuất:** Thêm `OCCURRENCE_NOT_FOUND` vào danh sách error codes (D7) và bổ sung trong spec cho từng operation (UPDATE, DELETE, REPLACE, SPLIT, SWAP) rằng nếu target id không có trong list, trả về `OverrideResult` với issues chứa `OCCURRENCE_NOT_FOUND` và `occurrences` giữ nguyên list cũ.

* * *

### 🟠 P1-1: SPLIT invariants cần được định nghĩa rõ hơn

Trong spec §5.5, SPLIT được mô tả là thay occurrence gốc bằng các part. Tuy nhiên, không có quy tắc nào về:

*   Các part có được phép **overlap** (ví dụ: 07:00–10:00 và 09:00–12:00)?
    
*   Các part có bắt buộc phải nằm **trong khoảng thời gian của occurrence gốc** (nếu occurrence gốc là 07:00–19:00, có được tạo part 06:00–08:00)?
    
*   Thứ tự thời gian của các part có được bảo toàn không?
    

Nếu không siết chặt, sau này payroll có thể tính trùng giờ, hoặc lịch hiển thị các ca chồng chéo gây nhầm lẫn.

**Đề xuất:** Thêm vào spec SPLIT:

*   Tất cả các part phải được sắp xếp theo thời gian tăng dần.
    
*   Không có sự overlap giữa hai part bất kỳ.
    
*   Toàn bộ khoảng thời gian của các part **phải nằm trong** khoảng thời gian của occurrence gốc (tức là `partStart >= originalStart` và `partEnd <= originalEnd`), ngoại trừ trường hợp overnight đã được xử lý đúng (part đầu kết thúc lúc 00:00, part tiếp theo bắt đầu 00:00).
    
*   Nếu một part vi phạm, toàn bộ SPLIT sẽ fail (atomic) – điều này đã được nêu, nhưng cần ràng buộc thêm.
    

* * *

### 🟠 P1-2: Error constants – nên dùng `abstract final class` như review2 đề xuất

`plan3_final.md` vẫn giữ các error code dạng `String` literal rời rạc. Mặc dù có một list constants, nhưng không có cơ chế bảo vệ khỏi typo trong code. Review2 đã đề xuất giải pháp dung hòa: dùng `abstract final class ErrorCodes` với các `static const String` để vừa tương thích JSON, vừa bắt lỗi biên dịch. Tôi khuyến nghíchấp nhận giải pháp này và đưa vào spec `time_types.dart`.

* * *

### 🟠 P1-3: Cần làm rõ `sourceOverrideId` và `source` cho các operation trong chuỗi override

Trong D4, quy định `sourceOverrideId = override.id` cho mọi occurrence được tạo/sửa bởi override. Tuy nhiên, nếu một occurrence được tạo bởi `CREATE` (gán `sourceOverrideId = override.id`), sau đó bị `UPDATE` bởi override khác, thì `sourceOverrideId` sẽ được gán lại là id của override sau. Điều này đúng. Nhưng cần ghi rõ trong spec rằng `source` (để phân loại `baseline`, `created`, `override`) được suy từ `sourceOverrideId != null` – tức là bất kỳ occurrence nào đã từng bị chạm bởi override đều mang nhãn `override` (hoặc `modified`). Điều này có nghĩa là một `CREATE` thủ công sau khi bị `UPDATE` sẽ không còn được gọi là `created` nữa, mà trở thành `override`. Điều này có thể chấp nhận được, nhưng cần được nêu rõ để tránh nhầm lẫn khi UI hiển thị.

**Đề xuất:** Thêm một dòng trong D4: "Khi một occurrence được tạo bởi CREATE sau đó bị một override khác sửa, `source` sẽ được ghi đè thành `override`; thông tin `created` ban đầu có thể được suy từ override log nếu cần, nhưng không phải là trách nhiệm của engine."

* * *

### 🟡 P2-1: Performance của `resolveUtcInstant` – có thể cần benchmark

Thuật toán enumerate `Location.zones` và `lookupTimeZone` cho mỗi lần resolve có thể tốn kém nếu `zones` dài (một số location có nhiều transition). Tuy nhiên, trong thực tế, số lượng zone của một location thường ít (vài chục), và ứng dụng offline nên khó thành bottleneck. Tuy nhiên, tôi đề xuất thêm một acceptance criterion về hiệu năng: "Resolve một occurrence mất dưới 10ms trên thiết bị trung bình." Điều này không bắt buộc ở Gate 0, nhưng có thể ghi vào backlog để kiểm tra sau.

* * *

### 🟡 P2-2: Round-trip test cho resolver – cần cụ thể hóa

Trong §6.2, có property test round-trip cho resolved instants. Tuy nhiên, cần thêm một test đặc biệt: với các input local time rơi vào **khoảng thời gian lặp** (ambiguous), khi ta chọn một trong hai candidate UTC, việc round-trip phải trả về đúng local time đã chọn. Điều này đảm bảo rằng engine lưu trữ đúng candidate mà user đã chọn (nếu sau này cho phép user chọn). Mặc dù Gate 0 không lưu lựa chọn của user, nhưng việc này sẽ được xử lý khi có UI, và engine cần đảm bảo rằng candidate được chọn vẫn round-trip đúng.

* * *

### 🟢 Điểm đã được xử lý tốt (không cần thay đổi)

*   `applyOverride` signature đã được chốt là `OverrideResult`.
    
*   UPDATE temporal semantics đã được xác định rõ (không re-resolve nếu time không đổi).
    
*   Resolved-only domain đã được đảm bảo qua `OverrideResult` và `ScheduleRenderResult`.
    
*   SWAP cross-job/timezone đã bị cấm.
    
*   Render không silent-drop, trả về issues.
    
*   Versioning anchorDate giữ nguyên.
    

* * *

3\. Đề xuất thêm các Acceptance Criteria để hoàn thiện Gate 0
-------------------------------------------------------------

Bổ sung thêm vào §8:

*   □
    
    **AC-11:** Khi một override command (UPDATE, DELETE, REPLACE, SPLIT, SWAP) trỏ tới `occurrenceId` không tồn tại trong list hiện tại, engine trả về `OverrideResult` với `issues` chứa `OCCURRENCE_NOT_FOUND` và list `occurrences` không thay đổi.
    
*   □
    
    **AC-12:** SPLIT luôn đảm bảo các part không overlap, được sắp xếp theo thời gian, và toàn bộ thời gian của các part nằm trong khoảng thời gian của occurrence gốc. Nếu vi phạm, SPLIT fail atomic.
    
*   □
    
    **AC-13:** Mọi error code được tham chiếu thông qua hằng số (dạng `ErrorCodes.invalidDate`) thay vì literal string rải rác trong code.
    
*   □
    
    **AC-14:** Đối với RESOLVED candidate, round-trip `local → UTC → local` phải trả về chính xác local input (kiểm tra trong property test).
    

* * *

4\. Kết luận
------------

`plan3_final.md` hiện tại đã đạt khoảng **85-90%** mức độ sẵn sàng cho AI agent. Hai review đã chỉ ra các điểm yếu và đề xuất giải pháp. Tôi đồng tình với hầu hết, và bổ sung thêm ba điểm còn thiếu (OCCURRENCE\_NOT\_FOUND, SPLIT invariants, và error constants). Nếu các điểm này được bổ sung, tôi tin rằng đây sẽ là một kế hoạch tuyệt vời để bắt tay vào code.

**Trạng thái cuối cùng của tôi**: `plan3_final.md` cần được **patch** với các nội dung trên trước khi giao cho agent. Sau đó, nó sẽ sẵn sàng 100%.