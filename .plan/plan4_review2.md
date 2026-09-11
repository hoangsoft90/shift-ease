plan4_review1.md
MD 10.6KB
plan4.md
MD 23.17KB
phân tích plan4.md và review của các AI khác plan4_review*.md rồi suy nghĩ đưa ra các ý kiến đóng góp/bổ xung/phản biện.
--------------------
Phân tích tổng hợp `plan4.md` và `plan4_review1.md` – Ý kiến đóng góp & phản biện
=================================================================================

Tôi đã đọc kỹ cả hai tài liệu. Nhìn chung, `plan4.md` là một bản review thực tế, sắc bén, phát hiện các lỗ hổng nghiêm trọng về wiring, transaction, re-import semantics và documentation integrity. `plan4_review1.md` đã đồng tình và bổ sung các giải pháp kiến trúc cụ thể (window semantics, SWAP fix, transaction pattern). Cả hai đều thống nhất: **M2 chưa sẵn sàng production, cần dừng lại để sửa các lỗi P1 trước khi chạy M3 Pay UI**.

Tôi hoàn toàn nhất trí với hướng đi này. Dưới đây là những đóng góp, bổ sung và phản biện của tôi, tập trung vào các điểm chưa được khai thác triệt để hoặc cần được làm rõ thêm.

* * *

1\. Điểm đồng ý tuyệt đối với cả `plan4.md` và `plan4_review1.md`
-----------------------------------------------------------------

*   **Unreachable M2 Import**: `main.dart` không truyền `ImportRepository` vào `ScheduleService` là một lỗi nghiêm trọng, khiến toàn bộ tính năng Import không thể truy cập từ app thật. Đây là hệ quả của việc chỉ test unit mà không có integration test cho production composition.
    
*   **Commit không atomic**: Lưu session `COMMITTED` và ghi occurrences trong hai bước riêng biệt không nằm trong cùng transaction dẫn đến trạng thái bất nhất nếu bước sau fail. Cần bọc toàn bộ trong một transaction SQLite.
    
*   **Bug re-import OFF date**: Query loại bỏ session có `committedOffDatesJson = '[]'` là sai semantics, vì roster mới có thể ghi đè OFF thành WORK. Cần sửa query để lấy session mới nhất theo window.
    
*   **Documentation lệch**: `checklist.md` ghi có `result13_gate_m2.txt` nhưng file không tồn tại. Đây là vấn đề về tính toàn vẹn của quy trình báo cáo, cần khắc phục bằng script tự động kiểm tra sự khớp giữa test count và báo cáo.
    
*   **SWAP với imported occurrence**: `pattern_engine.dart` dùng `templateId` để suy `jobId`; với imported occurrence `templateId` có thể rỗng, dẫn đến `MISSING_TEMPLATE` dù cùng job. Cần thêm `effectiveJobId`.
    
*   **Version immutability không được enforce ở persistence**: `PayRuleRepository` và `PatternRepository` dùng `ON CONFLICT DO UPDATE`, cho phép ghi đè lên version cũ. Cần thay đổi để ném exception khi cố ghi đè một version đã tồn tại.
    

* * *

2\. Các bổ sung và phản biện chi tiết (chưa được đề cập đầy đủ)
---------------------------------------------------------------

### 🔴 P1 – Semantics của `replaceImportedOccurrences` và re-import window

`plan4_review1.md` đã đề xuất thêm `windowStart` và `windowEnd` vào `ImportSession` và sử dụng chúng để xóa các occurrence cũ trong khoảng đó. Tôi đồng ý, nhưng cần làm rõ thêm:

*   **Nếu `windowStart` và `windowEnd` không được cung cấp (ví dụ import file toàn bộ lịch không có ngày cụ thể) thì sao?** Có thể để `null` và coi đó là toàn bộ lịch của job, nhưng điều này có thể gây xóa toàn bộ dữ liệu cũ. Cần có quy tắc xử lý rõ ràng.
    
*   **Khi re-import với window nhỏ hơn window cũ**, ví dụ Import A (1-30/09), Import B (10-20/09): theo semantics "replacement toàn bộ window mới", các ngày ngoài window mới (1-9, 21-30) vẫn giữ nguyên dữ liệu của import cũ. Điều này có thể dẫn đến lịch bị lai ghép giữa hai lần import khác nhau, gây nhầm lẫn. **Tôi đề xuất một lựa chọn khác:** Khi import mới, hãy coi đó là **thay thế toàn bộ lịch của job từ ngày bắt đầu đến ngày kết thúc của import mới, và xóa mọi dữ liệu import cũ trong khoảng đó**, nhưng **không xóa dữ liệu ngoài khoảng**. Nếu user muốn thay thế toàn bộ lịch, họ nên import một file bao phủ toàn bộ khoảng thời gian. Điều này cần được ghi rõ trong spec và test.
    

### 🟠 P1 – Atomic commit: cần xử lý rollback cả ở tầng engine lẫn repository

`plan4_review1.md` đã đưa ra code pattern sử dụng `db.transaction`. Tuy nhiên, cần đảm bảo rằng cả `_importRepo.saveSession` và `_scheduleRepo.replaceImportedOccurrences` đều sử dụng chung một kết nối SQLite và tham gia vào transaction. Nếu repository tạo kết nối riêng, transaction sẽ không có hiệu lực. **Cần truyền `db` hoặc một `Transaction` object vào các phương thức repository**, hoặc đảm bảo repository sử dụng cùng một instance `Database` đã được mở. Ngoài ra, nếu `commitImport()` ở engine cũng có logic phức tạp (ví dụ validate), cần kiểm tra xem có side-effect nào ngoài việc tạo dữ liệu không; nếu có, cần đảm bảo chúng cũng được rollback khi transaction fail.

### 🔴 P1 – `_canCommit()` và semantics của pending items

`plan4.md` đã chỉ ra rằng `_canCommit()` cho phép commit khi còn pending items. `plan4_review1.md` đề xuất không cho commit nếu còn pending, và cần có nút "Accept All Pending" trước. Tôi đồng ý với hướng này, nhưng tôi muốn nhấn mạnh thêm:

*   **Trải nghiệm user**: Khi có hàng trăm ca, việc user phải duyệt từng cái một rất mệt. Do đó, cần có cơ chế "Accept All High Confidence" và "Accept All Pending" (với cảnh báo) để tăng tốc. Nhưng **commit chỉ được phép khi không còn pending nào**.
    
*   **Lưu ý**: Nếu user chọn "Accept All Pending" với những ca có confidence thấp, họ vẫn có cơ hội xem lại trước khi commit (vì commit vẫn tách biệt). Điều này đảm bảo minh bạch.
    

### 🟡 P2 – SQLCipher và production security

`plan4.md` đã nhắc đến SQLCipher, và `plan4_review1.md` đề xuất `DatabaseFactory` với dev/prod. Tôi đồng ý, nhưng cần cụ thể hóa:

*   **Trên Android/iOS**, SQLCipher yêu cầu native library (`.so` hoặc `.dylib`). Cần đảm bảo build script tích hợp đúng.
    
*   **Khóa (key)** nên được lưu trong secure storage (Android Keystore / iOS Keychain) chứ không được hardcode.
    
*   **Trên desktop/development**, vẫn có thể dùng `sqlite3` thuần để test nhanh, nhưng phải có một `DatabaseProvider` khác cho production.
    
*   **Hiện tại `main.dart` chưa truyền key**, nên dữ liệu không được mã hóa. Đây là một **production blocker** thực sự, cần được ưu tiên sau khi sửa các lỗi correctness.
    

### 🟡 P2 – Kiểm tra tính toàn vẹn của báo cáo và filesystem

Cả `plan4.md` và `plan4_review1.md` đều chỉ ra sự lệch lạc giữa `checklist.md` và filesystem. Tôi đề xuất:

*   **Tự động hóa**: Tạo một script (ví dụ `scripts/verify_reports.sh`) chạy sau mỗi gate để:
    
    *   Đếm số lượng test thực tế (`flutter test --plain-name`).
        
    *   So sánh với các con số ghi trong `checklist.md`, `features.md`, `next.md`.
        
    *   Kiểm tra sự tồn tại của các file `result*.txt` được tham chiếu.
        
    *   Nếu có sai lệch, script sẽ fail và ngăn chặn việc chuyển gate.
        
*   Điều này sẽ ngăn chặn tình trạng "báo cáo ảo" tái diễn.
    

### 🟡 P2 – Thêm integration test cho production composition

`plan4.md` đã chỉ ra rằng test M2 không bắt được lỗi wire vì chúng tạo service với đầy đủ dependencies, khác với `main.dart`. Cần có:

*   Một integration test chạy `main()` hoặc ít nhất là tạo `ScheduleService` bằng cách gọi hàm `createProductionService()` (nếu có) để xác nhận `importEnabled == true`.
    
*   Tương tự, kiểm tra `JobDetailScreen` có hiển thị nút Import khi service được wire đúng.
    

### 🟢 Tôi đồng tình với các giải pháp `plan4_review1.md` đưa ra:

*   Sửa query `committedOffDatesInRange` để lấy session mới nhất theo window, không bỏ qua `[]`.
    
*   Thêm `windowStart`/`windowEnd` vào `ImportSession`.
    
*   Sửa SWAP dùng `effectiveJobId`.
    
*   Thêm transaction cho commit.
    

* * *

3\. Những điểm tôi muốn phản biện nhẹ với `plan4_review1.md`
------------------------------------------------------------

### Về "Accept All Pending" – tôi thấy nên có thêm tùy chọn "Auto-accept high confidence, ask for low"

Thay vì chỉ có một nút "Accept All Pending", có thể cung cấp hai nút:

*   **Accept All High Confidence**: tự động approve các ca có confidence >= ngưỡng (ví dụ > 0.8).
    
*   **Review Low Confidence**: chuyển đến danh sách các ca có confidence thấp để user duyệt.  
    Điều này cải thiện UX mà vẫn đảm bảo không commit khi còn pending.
    

### Về `effectiveJobId` – nên là một getter trong `ShiftOccurrence` nhưng cần xem xét trường hợp `templateId` null

Nếu `templateId` là null (hoặc rỗng) và `jobId` không có, `effectiveJobId` có thể trả về `''`. Khi đó SWAP cross-job sẽ không thể phát hiện, nhưng nếu cả hai đều có `jobId` rỗng, có thể coi là cùng job? **Tôi đề xuất:** nếu `effectiveJobId` rỗng, engine vẫn cho phép SWAP (vì không có job để ràng buộc), nhưng ghi log cảnh báo. Điều này an toàn hơn là từ chối SWAP.

* * *

4\. Đề xuất thêm một số acceptance criteria cho Gate A và B
-----------------------------------------------------------

Dựa trên các phân tích, tôi bổ sung các tiêu chí kiểm thử sau vào danh sách cần pass trước khi chuyển M3:

*   □
    
    **AC-A1:** `ScheduleService` tạo từ `main.dart` có `importEnabled == true`.
    
*   □
    
    **AC-A2:** Nút "Import roster" hiển thị trên màn hình chi tiết job khi service được wire đúng.
    
*   □
    
    **AC-A3:** Commit roster trong transaction: nếu xảy ra lỗi khi ghi occurrences, session vẫn ở trạng thái `PENDING` (hoặc `PARSED`), không bị ghi là `COMMITTED`.
    
*   □
    
    **AC-A4:** Re-import với window nhỏ hơn: các ngày nằm ngoài window mới vẫn giữ dữ liệu từ import cũ, các ngày trong window mới được thay thế hoàn toàn.
    
*   □
    
    **AC-A5:** Khi import mới có `committedOffDatesJson = []`, nó ghi đè các OFF ngày trong window, các ngày đó trở thành WORK (không bị suppress).
    
*   □
    
    **AC-A6:** SWAP giữa hai imported occurrence cùng job (dù `templateId` rỗng) thành công, không báo `MISSING_TEMPLATE`.
    
*   □
    
    **AC-A7:** Cố gắng lưu một `PayRule` hoặc `Pattern` với ID đã tồn tại nhưng nội dung khác → ném exception, không ghi đè.
    
*   □
    
    **AC-A8:** Tất cả các file `result*.txt` được tham chiếu trong `checklist.md` đều tồn tại và có nội dung khớp với số lượng test thực tế.
    

* * *

5\. Kết luận và hành động tiếp theo
-----------------------------------

Tôi đánh giá `plan4.md` là một bản review đúng đắn và cần thiết. `plan4_review1.md` đã bổ sung các giải pháp kiến trúc hợp lý. Tuy nhiên, tôi vẫn thấy cần làm rõ thêm semantics của re-import window, transaction boundary, và UI commit flow.

**Thứ tự ưu tiên cho agent:**

1.  **Sửa `main.dart`** để wire `ImportRepository` và thêm integration test cho composition.
    
2.  **Sửa `commitRoster()`** để bọc trong transaction, đảm bảo atomicity.
    
3.  **Sửa `committedOffDatesInRange()`** theo window semantics và thêm test cho trường hợp `[]`.
    
4.  **Thêm `windowStart`/`windowEnd` vào `ImportSession`** và cập nhật `replaceImportedOccurrences()`.
    
5.  **Sửa `pattern_engine.dart` SWAP** để dùng `effectiveJobId`.
    
6.  **Sửa `PayRuleRepository` và `PatternRepository`** để không cho ghi đè version cũ (throw exception).
    
7.  **Đồng bộ `checklist.md`, `features.md`, `next.md`** với filesystem và số lượng test thực tế.
    
8.  **Chạy lại toàn bộ test suite**, tạo `result13_gate_m2.txt` thật, và xác nhận tất cả AC trên đều xanh.
    
9.  **Sau đó mới mở Gate M3** cho Pay UI.
    

Nếu các bước trên được thực hiện đầy đủ, tôi tin rằng nền tảng M2 sẽ đủ vững để xây dựng các tính năng tiếp theo. Chúc quá trình phát triển suôn sẻ!