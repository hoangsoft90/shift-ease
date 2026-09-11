Tiếp tục hoàn thiện project
Mục tiêu: **HOÀN THÀNH P7 – Production Verification** theo đúng:

`phases/P7_production_verification.md`

Không được đánh dấu P7 DONE nếu các production/device gates chưa thực sự được verify.

## 1. Đọc trước khi sửa

Đọc và đối chiếu:

* `phases/P7_production_verification.md`
* `checklist.md`
* `features.md`
* `next.md`
* `result*.txt` mới nhất
* `handoff*` mới nhất
* `.project/state.md`
* toàn bộ code liên quan DB/security/notification/backup/migration

Sau đó tự lập danh sách P7 còn thiếu trước khi code.

## 2. Các blocker hiện tại cần xử lý

### P7.2 — SQLCipher — P0 BLOCKER

Hiện tại app vẫn đang dùng plain SQLite:

* `sqlite3.open(...)`
* `PRAGMA key`

`PRAGMA key` trên plain SQLite **không tạo encryption**.

Phải triển khai SQLCipher native integration thực sự cho production.

Yêu cầu:

* DB production phải thực sự encrypted.
* `PRAGMA cipher_version` phải trả về version hợp lệ trên production build.
* Wrong key phải không mở được DB.
* Không để fallback âm thầm sang plain SQLite trong production.
* Test encrypted DB create/open/reopen/wrong-key.
* Migration phải hoạt động trên encrypted DB.
* Backup/restore phải hoạt động với encrypted DB.
* Không log encryption key hoặc DB secrets.

Giữ `DatabaseOpener` seam nếu hữu ích, nhưng seam/test double không được coi là production implementation.

### P7.3 — Android Keystore — P0 BLOCKER

Implement production `SecretStore` bằng Android Keystore.

Yêu cầu:

* encryption key không nằm plaintext trong SharedPreferences/file/database.
* Key được bảo vệ bởi Android Keystore.
* restart app vẫn lấy được key.
* uninstall/reinstall behavior phải được xác định rõ.
* migration/recovery behavior phải rõ ràng.
* không dùng `InMemorySecretStore` cho production.

### P7.4 — iOS Keychain — P0 BLOCKER

Implement production `SecretStore` bằng iOS Keychain.

Yêu cầu:

* key không lưu plaintext trong UserDefaults/file/database.
* restart app vẫn lấy được key.
* behavior khi reinstall/restore phải được xác định.
* không dùng test/in-memory implementation cho production.

### P7.5 — Android Notifications

Code hiện tại đã có nhiều phần logic, nhưng cần **verify trên Android physical device**.

Test tối thiểu:

1. Android 13+
2. permission chưa hỏi
3. grant permission
4. deny permission
5. permanently denied nếu OS/device hỗ trợ flow đó
6. create shift → notification
7. edit shift → old notification cancelled + new notification
8. delete shift → notification cancelled
9. recurring shift
10. overnight shift
11. restart app
12. background/resume
13. reboot device
14. timezone/DST change
15. notification không bị duplicate
16. stale notification không còn tồn tại

Không được chỉ dựa vào unit tests.

### P7.6 — iOS Notifications

Verify trên physical iPhone:

* permission flow
* create/edit/delete
* recurring
* overnight
* restart
* background/resume
* timezone/DST
* notification resync
* không duplicate/stale notification

Nếu simulator không đủ để verify một behavior thì phải ghi rõ NOT VERIFIED thay vì PASS.

### P7.7 — Lifecycle

Test real device:

`launch → use app → background → resume → force kill → reopen`

Thực hiện với ít nhất:

* calendar
* quick add
* import/review
* income
* notifications
* backup/restore

Đảm bảo không mất unsaved state và DB không corrupt.

### P7.8 — Migration

Verify:

* fresh install
* v1 → latest
* v2 → latest
* existing DB upgrade
* interrupted migration
* migration failure/rollback
* encrypted DB migration

Đặc biệt phải test trên **SQLCipher DB**, không chỉ plain SQLite.

### P7.9 — Backup / Restore

Code-level hiện khá tốt nhưng cần physical-device verification.

Test:

1. tạo dataset thực tế đủ lớn
2. backup
3. restart app
4. restore
5. verify toàn bộ dữ liệu
6. corrupted backup
7. checksum mismatch
8. wrong/incompatible backup
9. restore cancellation
10. failed restore không được làm thay đổi live DB
11. encrypted DB backup/restore

Đặc biệt chứng minh:

**restore thất bại → dữ liệu hiện tại vẫn nguyên vẹn.**

### P7.10 — DST / Timezone

Test physical device:

* spring-forward nonexistent local time
* fall-back ambiguous local time
* explicit offset choice
* overnight
* timezone change A → B sau khi đã tạo shift

Sau timezone change phải verify:

* displayed wall time
* UTC instant
* duration
* income
* notification

Không được mutate historical occurrence timezone chỉ vì device timezone thay đổi.

### P7.11 — Security

Review toàn bộ source lần cuối:

* secrets/API keys
* passwords
* tokens
* logs
* debugPrint/print
* sensitive crash payload
* plaintext DB
* plaintext encryption key
* insecure storage
* release/debug differences

Không chỉ search keyword; kiểm tra actual data flow.

### P7.12 — Regression

Phải chạy:

* `flutter analyze`
* `flutter test`
* integration tests nếu có
* release build
* Android build
* iOS build nếu môi trường cho phép

Hiện tại test đang 297/297 PASS, nhưng phải chạy lại sau toàn bộ thay đổi.

## 3. Sửa CI

`.github/workflows/test.yml` hiện đang target project Dart cũ:

* `working-directory: source`
* `dart-lang/setup-dart`
* `dart pub get`
* `dart test`

Trong khi ShiftEase hiện là Flutter project ở root.

Sửa CI thành workflow đúng cho Flutter project hiện tại.

Ít nhất:

* checkout
* Flutter setup
* `flutter pub get`
* `flutter analyze`
* `flutter test`
* phù hợp với root project

Nếu hợp lý, thêm Android build verification.

Không được báo CI PASS nếu workflow thực tế không test source hiện tại.

## 4. Không được làm

Không:

* nhảy sang P8 khi P7 chưa hoàn thành
* thêm OCR
* thêm AI
* thêm cloud sync
* thêm social/sharing
* thêm B2B
* thêm payroll/tax
* thêm feature không liên quan production readiness
* đổi business logic hiện tại nếu không cần thiết cho P7
* dùng mock/test implementation làm production implementation
* coi unit test là bằng chứng physical-device verification
* tự đánh dấu PASS khi chưa có evidence

Ưu tiên **correctness, data safety, security, reliability** hơn UI polish.

## 5. Definition of Done của P7

Chỉ được đánh dấu:

`P7 = DONE`

khi:

* SQLCipher production thực sự hoạt động
* Android Keystore production hoạt động
* iOS Keychain production hoạt động
* Android notification physical-device verification PASS
* iOS notification physical-device verification PASS
* lifecycle verification PASS
* encrypted migration PASS
* backup/restore physical verification PASS
* corrupted restore không phá live DB
* DST/timezone verification PASS
* security review PASS
* regression PASS
* CI test đúng source hiện tại
* release build không crash

Nếu môi trường hiện tại không có Android/iOS physical device thì **KHÔNG được giả lập PASS**.

Khi đó:

`CODE READY / DEVICE VERIFICATION BLOCKED`

và ghi rõ chính xác cần test gì trên device.

## 6. Sau khi code xong

Chạy toàn bộ test/build phù hợp.

Cập nhật:

* `checklist.md`
* `next.md`
* `.project/state.md`
* tạo `result_p7_production_verification*.md`
* tạo `handoff*` mới nếu project đang dùng handoff

Trong result cuối cùng phải có bảng:

| Gate                      | Status       | Evidence |
| ------------------------- | ------------ | -------- |
| P7.1                      | PASS/BLOCKED | ...      |
| P7.2 SQLCipher            | PASS/BLOCKED | ...      |
| P7.3 Android Keystore     | PASS/BLOCKED | ...      |
| P7.4 iOS Keychain         | PASS/BLOCKED | ...      |
| P7.5 Android notification | PASS/BLOCKED | ...      |
| P7.6 iOS notification     | PASS/BLOCKED | ...      |
| P7.7 Lifecycle            | PASS/BLOCKED | ...      |
| P7.8 Migration            | PASS/BLOCKED | ...      |
| P7.9 Backup/Restore       | PASS/BLOCKED | ...      |
| P7.10 DST/Timezone        | PASS/BLOCKED | ...      |
| P7.11 Security            | PASS/BLOCKED | ...      |
| P7.12 Regression          | PASS/BLOCKED | ...      |

Cuối cùng ghi rõ:

* P7 DONE hay NOT DONE
* blocker còn lại
* evidence cụ thể
* phase tiếp theo có được phép bắt đầu hay chưa

**Không tự chuyển sang P8 nếu P7 còn P0/P1 hoặc device verification chưa hoàn tất.**
