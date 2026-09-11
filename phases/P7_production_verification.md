# ShiftEase --- P7 Production Verification / Security / Real Devices

## 0. Mục tiêu

Đưa ShiftEase từ **Release Candidate** thành bản có thể chứng minh
production-ready về:

-   data integrity
-   database security
-   notification reliability
-   app lifecycle
-   migration safety
-   backup/restore safety
-   timezone/DST correctness
-   Android/iOS real-device compatibility

**Không mở feature lớn mới trong P7.**

Không làm OCR, Cloud Sync, Sharing, AI, B2B, payroll/tax/net-pay trong
phase này.

------------------------------------------------------------------------

# 1. Trạng thái đầu vào

RC hiện đã có:

-   `flutter analyze --no-pub` PASS
-   full test suite **292/292 PASS**
-   P0--P6 đã hoàn thành
-   import/re-import CSV
-   income/pay/multi-job
-   backup/restore
-   settings
-   notification lifecycle code
-   encryption/security seam
-   mobile readiness matrix

Code review RC còn các finding:

### P0/P1 cần xử lý trong P7

**H1 HIGH --- Backup directory** - `SettingsScreen` production wiring
hiện có thể fallback vào `Directory.systemTemp`. - Đây là
cache/purgeable location. - Backup dữ liệu người dùng không được lưu vào
cache. - Phải dùng `getApplicationSupportDirectory()` hoặc một
app-private persistent location phù hợp. - Giữ dependency injection
`backupDir` cho test. - Không làm mất backup hiện có trong test.

**M1 MEDIUM --- Income Impact** - `estimateRosterDiffImpact` đang bỏ qua
prospective row nếu resolve thất bại. - Điều này có thể tạo
`After income` thấp giả tạo. - Nếu bất kỳ row nào không resolve được,
toàn bộ Income Impact phải trả `UNAVAILABLE` với reason cụ thể. - Không
silently skip.

### Các finding còn lại

**M2 MEDIUM** - iOS notification permission status hiện có thể hiển thị
`Unknown`. - Xử lý trong device verification; nếu API/plugin không cung
cấp trạng thái tương đương thì ghi rõ limitation, không đoán.

**L4 LOW** - Reminder sync window hiện khoảng 13 ngày. - Không phải
release blocker nếu hành vi được xác định rõ và resume resync đúng. -
Không tự mở rộng window nếu không cần.

------------------------------------------------------------------------

# 2. P7.1 --- Fix RC code-review blockers

## 2.1 H1 Backup directory

### Implementation

-   Resolve `getApplicationSupportDirectory()` khi `backupDir == null`.
-   Không dùng `Directory.systemTemp` cho production backup.
-   Test injection vẫn được phép dùng temp directory.
-   Backup file naming giữ nguyên.
-   Restore phải đọc cùng persistent directory.
-   Không migrate/xóa backup cũ một cách âm thầm.

### Tests

Bổ sung test chứng minh:

1.  production/default path không phải cache/temp.
2.  backup tạo được.
3.  restore đọc đúng location.
4.  injected test directory vẫn hoạt động.

## 2.2 M1 Income Impact

### Implementation

Thay logic:

``` text
resolve failure -> continue
```

bằng:

``` text
resolve failure -> IncomeImpact.UNAVAILABLE
```

Reason phải chỉ rõ row/date và nguyên nhân nếu có.

### Tests

Ít nhất:

-   valid rows only → AVAILABLE
-   one invalid/DST-gap row → UNAVAILABLE
-   mixed valid + unresolvable rows → UNAVAILABLE
-   no partial/optimistic total
-   existing valid cases unchanged

## Acceptance

-   H1 PASS
-   M1 PASS
-   no regression
-   analyze PASS
-   tests PASS

------------------------------------------------------------------------

# 3. P7.2 --- SQLCipher production integration

## Mục tiêu

Không được claim "encrypted" chỉ vì có security seam/probe.

Phải chứng minh database thực sự được mã hóa trên Android và iOS.

## Required

-   Chọn thư viện/implementation SQLCipher tương thích Flutter/Dart và
    project hiện tại.
-   Android native integration.
-   iOS native integration.
-   Encryption key không hard-code.
-   Existing repository/data layer không bị phá.
-   Migration path được xác định.
-   Fresh install tạo encrypted DB.

## Key lifecycle

``` text
first launch
  ↓
generate cryptographically random key
  ↓
store in secure platform storage
  ↓
open encrypted DB
```

Restart:

``` text
read key
  ↓
open same encrypted DB
```

Wrong key:

``` text
open DB
  ↓
FAIL
```

Không fallback sang plaintext nếu encryption mở thất bại.

## Mandatory negative test

Copy DB file ra ngoài app.

Attempt open with ordinary/plain SQLite tooling.

Expected:

-   application records are not readable as normal SQLite data.

Không dùng test chỉ kiểm tra file extension hoặc flag.

------------------------------------------------------------------------

# 4. P7.3 --- Android secure key storage

## Required

-   Android Keystore-backed mechanism hoặc secure storage backed by
    Keystore.
-   Không plaintext persistent key.
-   Không log key.
-   Không include key trong backup/debug output.
-   Key survives normal restart.
-   Define reinstall behavior explicitly.

## Test

-   first install
-   generate key
-   restart
-   force kill
-   reopen
-   wrong key
-   secure storage unavailable/error path

------------------------------------------------------------------------

# 5. P7.4 --- iOS secure key storage

## Required

-   Keychain-backed storage.
-   No plaintext key.
-   No key in logs.
-   Restart/reopen works.
-   Defined reinstall behavior.
-   Error path is explicit.

------------------------------------------------------------------------

# 6. P7.5 --- Android notification real-device verification

Test on a physical Android device, preferably Android 13+.

## Matrix

  Case                     Expected
  ------------------------ --------------------------------------
  permission not granted   app explains/request path
  grant permission         reminders work
  deny                     no false "enabled" claim
  permanently denied       Settings fallback
  create shift             reminder scheduled
  edit shift               old reminder replaced
  delete shift             reminder cancelled
  app restart              reminders remain correct
  background               reminder works
  resume                   stale schedules reconciled
  reboot                   behavior matches platform capability

## Critical invariant

Deleting a shift must not leave its notification alive.

Changing time must not leave the old notification alive.

No duplicate notification IDs.

------------------------------------------------------------------------

# 7. P7.6 --- iOS notification real-device verification

Physical iPhone/iPad where supported.

Test:

-   permission granted
-   permission denied
-   schedule
-   update
-   cancel
-   delete shift
-   restart
-   background
-   resume
-   timezone change
-   DST transition

Also verify notification Settings status.

If exact permission state is not available through the selected
plugin/API:

-   show `Unknown`
-   document it
-   never infer permission from a scheduled notification.

------------------------------------------------------------------------

# 8. P7.7 --- Lifecycle verification

For each flow test:

``` text
Launch
→ foreground
→ background
→ resume
→ force kill
→ reopen
```

Flows:

-   create shift
-   edit shift
-   delete shift
-   create pattern
-   edit occurrence
-   import
-   commit import
-   CSV re-import
-   override
-   roster replacement
-   backup
-   restore

Verify:

-   no crash
-   no duplicate records
-   no lost records
-   no stale reminders
-   no changed historical occurrences
-   income remains deterministic

------------------------------------------------------------------------

# 9. P7.8 --- Database migration verification

Identify every supported schema version.

For each:

``` text
old database
→ install/upgrade new build
→ migration
→ reopen
→ verify
```

Verify:

-   jobs
-   templates
-   patterns
-   occurrences
-   overrides
-   imported roster
-   ImportSession
-   PayRules
-   settings
-   notification-related data

Failure tests:

-   migration exception
-   interrupted migration where realistically testable
-   reopen after failure

For encrypted DB:

-   migrate encrypted DB
-   reopen encrypted DB
-   verify data
-   verify key still works

**No destructive migration.**

------------------------------------------------------------------------

# 10. P7.9 --- Backup/restore real-device verification

Create realistic dataset containing:

-   multiple jobs
-   recurring pattern
-   one-off shift
-   overnight shift
-   occurrence override
-   imported roster
-   CSV re-import result
-   multiple PayRules
-   income history
-   settings
-   notification configuration

Then:

``` text
Create data
→ backup
→ modify/delete data
→ restore
→ restart
→ verify
```

Verify exact data integrity.

## Corrupted backup test

Use:

-   modified checksum
-   malformed JSON
-   missing required field
-   incompatible schema version

Expected:

-   restore rejected
-   existing live DB remains unchanged
-   no partial deletion

------------------------------------------------------------------------

# 11. P7.10 --- DST / timezone real-device verification

## Spring forward

Test nonexistent local time.

Expected:

-   blocked
-   clear error
-   no silent normalization

## Fall back

Test ambiguous local time.

Expected:

-   two candidates
-   explicit user choice
-   selected offset persists
-   restart preserves interpretation

## Device timezone change

``` text
create shift in timezone A
→ change device timezone to B
→ reopen
```

Existing occurrence must retain its original timezone semantics.

Verify:

-   displayed local wall time
-   UTC instant
-   duration
-   income
-   notification

------------------------------------------------------------------------

# 12. P7.11 --- Security review

Search final source for:

-   hard-coded secrets
-   API keys
-   encryption keys
-   debug prints
-   sensitive logs
-   backup paths
-   temp files
-   clipboard data
-   crash-report sensitive payloads

Production must not log:

-   encryption key
-   full backup contents
-   sensitive user data unnecessarily

------------------------------------------------------------------------

# 13. P7.12 --- Full regression

After all fixes:

``` bash
flutter analyze --no-pub
flutter test test/
```

Then build/test Android and iOS release candidates.

All evidence must be generated against the final source tree.

Do not reuse stale test counts from old result files.

------------------------------------------------------------------------

# 14. Required evidence file

Create:

`result_p7_production_verification.md`

Must contain:

-   commit/source revision
-   Flutter/Dart version
-   analyze result
-   test count
-   Android device/model/version
-   iOS device/model/version
-   SQLCipher evidence
-   secure storage evidence
-   notification matrix
-   lifecycle matrix
-   migration matrix
-   backup/restore matrix
-   DST/timezone matrix
-   known limitations
-   unresolved P0/P1/P2/P3 issues
-   final PASS/FAIL

Never write "PASS" for a device test that was not actually executed.

------------------------------------------------------------------------

# 15. P7 Definition of Done

P7 is PASS only if:

-   [ ] H1 fixed and tested
-   [ ] M1 fixed and tested
-   [ ] SQLCipher is real and verified
-   [ ] Android secure key storage verified
-   [ ] iOS Keychain verified
-   [ ] Android notification physical-device tests PASS
-   [ ] iOS notification physical-device tests PASS
-   [ ] lifecycle tests PASS
-   [ ] migration tests PASS
-   [ ] encrypted DB migration PASS
-   [ ] real-device backup/restore PASS
-   [ ] corrupted backup is safely rejected
-   [ ] DST spring/fall tests PASS
-   [ ] timezone-change tests PASS
-   [ ] security review PASS
-   [ ] final analyze PASS
-   [ ] final full test suite PASS
-   [ ] no P0/P1 issues
-   [ ] evidence matches final source tree

Only after all items are PASS may the agent proceed to P8.
