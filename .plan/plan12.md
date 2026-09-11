Agent đang code xong, bạn cần review đánh giá lại xem đã làm đúng phases/P7_production_verification.md chưa

Toàn bộ files+code của project tại /Users/hoang/htdocs_apps/ShiftEase.
--------------------
Tôi đã rà soát lại **source hiện tại + `phases/P7_production_verification.md` + evidence P7**. Kết luận khá rõ:

🔴 P7 CHƯA HOÀN THÀNH
=====================

Agent đã làm tốt phần **P7.1**, nhưng **chưa làm xong các phần production-critical còn lại**. Quan trọng hơn, có một vấn đề trong CI mà evidence hiện tại đang đánh giá hơi lạc quan.

Tổng quan
---------

| P7 | Hạng mục | Đánh giá |
| --- | --- | --- |
| P7.1 | H1 Backup directory | 🟢 **DONE** |
| P7.1 | M1 Income Impact | 🟢 **DONE** |
| P7.2 | SQLCipher thật | 🔴 **CHƯA LÀM** |
| P7.3 | Android Keystore | 🔴 **CHƯA LÀM** |
| P7.4 | iOS Keychain | 🔴 **CHƯA LÀM** |
| P7.5 | Android notification device | 🟠 **CHƯA VERIFY** |
| P7.6 | iOS notification device | 🟠 **CHƯA VERIFY** |
| P7.7 | Lifecycle real device | 🟠 **CHƯA VERIFY** |
| P7.8 | Migration | 🟢 **PASS phần sandbox**, encrypted migration chưa |
| P7.9 | Backup/restore real device | 🟠 **CHƯA VERIFY** |
| P7.10 | DST/timezone real device | 🟠 **CHƯA VERIFY** |
| P7.11 | Security review | 🟢 **PASS ở source level** |
| P7.12 | Regression | 🟢 **297/297 PASS** |
| CI | Android/iOS verification | 🔴 **CHƯA đủ để unblock** |

* * *

1\. P7.1 — Agent làm đúng
=========================

### H1 Backup

Tôi kiểm tra source:

`lib/features/settings/settings_screen.dart`

đã chuyển production fallback sang:

    getApplicationSupportDirectory()

và loại bỏ `Directory.systemTemp` khỏi backup/restore production path.

Đồng thời có:

*   `backupDir` injection cho test
    
*   `backupDirResolver`
    
*   storage failure → báo lỗi
    
*   không fallback âm thầm sang temp
    
*   restore dùng cùng resolved directory
    

Đây là cách xử lý **đúng**.

### M1 Income Impact

Agent cũng sửa đúng logic nguy hiểm:

Trước:

    resolve failure → continue

Sau:

    resolve failure
    → IncomeImpact.UNAVAILABLE

Đặc biệt có test DST-gap.

**P7.1 = PASS.**

* * *

2\. 🔴 P7.2 SQLCipher — CHƯA LÀM
================================

Đây là blocker lớn nhất.

Tôi kiểm tra:

`pubspec.yaml`

hiện vẫn chỉ có:

    sqlite3: ^3.5.2

Không thấy dependency/native SQLCipher thực sự.

Source `lib/core/db/db.dart` vẫn:

    sqlite3.open(path)

rồi:

    PRAGMA key

Đây **không phải SQLCipher**.

Điểm rất tốt là agent không giả vờ claim encrypted. `security_gate.dart` còn kiểm tra:

    PRAGMA cipher_version

và báo:

> local database is currently NOT encrypted

Đó là **honesty đúng**, nhưng đồng nghĩa:

> 🔴 **database hiện tại chưa được mã hóa.**

Vì vậy P7.2 chưa đạt.

* * *

3\. 🔴 P7.3 Android Keystore — CHƯA LÀM
=======================================

Hiện tại chỉ có abstraction:

    SecretStore

và:

    InMemorySecretStore

Không thấy production implementation Android Keystore.

Agent ghi:

> production = Android Keystore / iOS Keychain

nhưng đó mới là **design/seam**, chưa phải implementation.

Vì vậy:

**P7.3 = NOT DONE.**

* * *

4\. 🔴 P7.4 iOS Keychain — CHƯA LÀM
===================================

Tương tự.

Không thấy production Keychain-backed implementation.

`SecretStore` chỉ là abstraction.

Do đó:

**P7.4 = NOT DONE.**

* * *

5\. 🟠 P7.5 Android Notification
================================

Code notification hiện khá ổn.

Có:

*   `POST_NOTIFICATIONS`
    
*   runtime permission request
    
*   fixed notification ID
    
*   stale cancellation
    
*   RESUME resync
    
*   edit/delete handling
    

Nhưng P7 yêu cầu **physical device verification**.

Hiện evidence cũng trung thực ghi:

    NOT RUN

Nên chưa thể PASS.

Các case phải test thật:

    Android 13+
    permission denied
    permission granted
    permanently denied
    create shift
    edit shift
    delete shift
    restart
    background
    resume
    reboot

Đặc biệt:

> delete shift → notification cũ phải biến mất.

**P7.5 = NOT VERIFIED.**

* * *

6\. 🟠 P7.6 iOS Notification
============================

Logic có, nhưng chưa có physical iPhone verification.

Điểm đúng:

iOS permission nếu không xác định được thì hiển thị:

    Unknown

thay vì tự đoán.

Nhưng vẫn phải test thật:

*   grant
    
*   deny
    
*   schedule
    
*   update
    
*   cancel
    
*   delete
    
*   restart
    
*   background
    
*   resume
    
*   timezone
    
*   DST
    

**P7.6 = NOT VERIFIED.**

* * *

7\. 🟠 P7.7 Lifecycle
=====================

Test suite hiện tại có thể cover rất nhiều logic lifecycle/persistence.

Nhưng P7 yêu cầu:

    Launch
    → foreground
    → background
    → resume
    → force kill
    → reopen

trên thiết bị.

Cái này chưa được thực hiện.

**P7.7 = NOT VERIFIED.**

* * *

8\. 🟢 P7.8 Migration
=====================

Phần migration SQLite hiện có test:

*   v1 → v2
    
*   v2 → v3
    
*   reopen
    
*   rollback
    
*   failure scenarios
    

Đây là phần tốt.

Nhưng cần lưu ý:

    plain SQLite migration = PASS

không đồng nghĩa:

    SQLCipher migration = PASS

Vì SQLCipher chưa tồn tại.

Do đó tôi đánh giá:

**P7.8 = PASS sandbox / BLOCKED encrypted leg.**

* * *

9\. 🟠 P7.9 Backup/Restore
==========================

Code-level backup/restore khá tốt:

    validate
    → checksum
    → preview
    → confirm
    → transaction
    → rollback
    → verify

Corrupt backup cũng đã có test.

Nhưng chưa có real-device test với dataset đầy đủ:

*   multiple jobs
    
*   pattern
    
*   overnight
    
*   override
    
*   imported roster
    
*   CSV
    
*   multiple PayRules
    
*   settings
    
*   notification
    

Do đó:

**P7.9 = PARTIAL.**

* * *

10\. 🟠 P7.10 DST/Timezone
==========================

Engine hiện đã có các cơ chế quan trọng:

### Spring forward

    02:00 nonexistent
    → BLOCK

### Fall back

    ambiguous
    → user chọn candidate
    → offset persisted

Đây là đúng.

Nhưng vẫn chưa test physical device:

    Timezone A
    → tạo shift
    → đổi timezone thiết bị
    → reopen

và verify:

*   wall time
    
*   UTC
    
*   duration
    
*   income
    
*   notification
    

**P7.10 = PARTIAL.**

* * *

11\. 🟢 P7.11 Security source review
====================================

Tôi kiểm tra lại search toàn source.

Không thấy:

*   hard-coded API key
    
*   password
    
*   bearer token
    
*   encryption key hardcoded
    
*   `print`
    
*   `debugPrint`
    

Encryption key được generate bằng:

    Random.secure()

Điểm này tốt.

Tuy nhiên phải phân biệt:

> **Security source review PASS ≠ encrypted database PASS.**

Database vẫn plain SQLite.

**P7.11 = PASS source-level, nhưng overall security chưa production-ready.**

* * *

12\. 🟢 P7.12 Regression
========================

Evidence mới nhất ghi:

    flutter analyze --no-pub
    No issues found
    
    flutter test test/
    297/297 PASS

Đây là một kết quả tốt.

P7.1 thêm 5 tests:

    292 → 297

và không regression.

**P7.12 = PASS.**

* * *

13\. ⚠️ Tôi phát hiện thêm vấn đề CI cần sửa
============================================

Đây là điểm tôi không muốn agent bỏ qua.

Hiện `.github/workflows/test.yml` tồn tại, nhưng workflow vẫn đang cấu hình:

    working-directory: source

và paths:

    source/**

Trong khi project Flutter hiện tại có:

    lib/
    test/
    android/
    ios/
    pubspec.yaml

ở **root của project**.

Không có thư mục Flutter `source/` tương ứng.

Vì vậy workflow này có dấu hiệu là **CI cũ của giai đoạn pure-Dart**, chưa được cập nhật đúng cho project Flutter hiện tại.

Ngoài ra tôi tìm trực tiếp:

    build-debug-apk.yml

→ **không tồn tại**.

Trong khi `next.md`/evidence đang nói workflow này đã được wired.

Đây là một discrepancy cần agent sửa.

### Kết luận

Không được coi:

    CI activation

là DONE.

Phải sửa thành CI thực sự chạy trên project hiện tại:

    Flutter setup
    → flutter pub get
    → flutter analyze
    → flutter test

và thêm Android build artifact nếu đó là mục tiêu P7.

* * *

14\. Có một điểm rất đáng chú ý về `result_p7...`
=================================================

Evidence hiện tại thực ra **không claim P7 PASS**, và tôi đánh giá cao điều này.

Nó ghi:

    P7 overall: NOT COMPLETE

và các device gates:

    NOT RUN

Đó là chính xác.

Vì vậy **không có false claim nghiêm trọng trong evidence file**.

Vấn đề là agent đã làm P7.1 nhưng chưa thực sự chuyển sang phần native/device.

* * *

15\. P7 hiện đạt khoảng bao nhiêu?
==================================

Nếu tính theo gate quan trọng:

    P7.1       ✅
    P7.2       ❌
    P7.3       ❌
    P7.4       ❌
    P7.5       ⚠️
    P7.6       ⚠️
    P7.7       ⚠️
    P7.8       ⚠️
    P7.9       ⚠️
    P7.10      ⚠️
    P7.11      ✅
    P7.12      ✅

Tôi sẽ gọi trạng thái hiện tại:

> **P7 — Code hardening mostly complete, native/device verification NOT complete.**

Không nên gọi là Production Ready.

* * *

16\. Việc agent nên làm tiếp — theo đúng thứ tự
===============================================

Tôi khuyên **không cho agent làm P8**.

Agent tiếp tục P7 theo thứ tự:

### Batch 1 — CI correction

    Fix .github/workflows/test.yml
    Create real Flutter CI
    Create Android build workflow
    Verify workflow configuration

### Batch 2 — Security

    P7.2 SQLCipher
    P7.3 Android Keystore
    P7.4 iOS Keychain

Đây là phần quan trọng nhất.

Đặc biệt phải có test:

    copy DB
    ↓
    open using normal SQLite
    ↓
    must NOT be readable

Không chấp nhận:

    PRAGMA key

làm bằng chứng.

### Batch 3 — Android device

    notification
    lifecycle
    backup/restore
    DST/timezone
    migration
    encrypted DB
    Keystore

### Batch 4 — iOS device

Tương tự:

    notification
    lifecycle
    backup/restore
    DST/timezone
    migration
    encrypted DB
    Keychain

### Batch 5 — Final evidence

Chạy lại:

    flutter analyze
    flutter test
    Android release/debug build
    iOS build

Sau đó cập nhật:

    result_p7_production_verification.md

**chỉ tick PASS những gì thực sự chạy.**

* * *

🏁 Verdict
==========

**Agent đã làm đúng P7.1 và không phá core. 297/297 tests + analyze sạch là rất tốt.**

Nhưng:

> 🔴 **P7 chưa xong.**

Ba blocker lớn nhất hiện tại là:

1.  **SQLCipher thật chưa tồn tại**
    
2.  **Android Keystore / iOS Keychain chưa có production implementation**
    
3.  **Real Android/iOS verification chưa chạy**
    

Và tôi phát hiện thêm:

4.  **CI workflow hiện tại có vẻ vẫn trỏ vào cấu trúc `source/` cũ và `build-debug-apk.yml` thực tế không tồn tại**, nên cần sửa trước khi dựa vào CI để đóng P7.
    

**Không nên chuyển P8.** Tiếp tục P7 cho đến khi 4 nhóm trên được đóng và `result_p7_production_verification.md` có evidence thực tế.