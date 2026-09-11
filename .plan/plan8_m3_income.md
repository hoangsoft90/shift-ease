# ShiftEase — Plan8: Release Candidate Batch — M3 Income + Integrity + Production Readiness

Ngày: 2026-09-07 · Trạng thái: **ĐÃ DUYỆT SCOPE — CHỜ AGENT CODE**

> Đây là batch cuối trước vòng review release-candidate. Không mở thêm OCR/Cloud/AI trong batch này.
> Kỷ luật gate: **spec → user duyệt → code → test → evidence → review**.
>
> Mục tiêu không chỉ là làm M3 Income, mà đóng các lỗ hổng correctness/data-integrity đã phát hiện trong review Gate C, hoàn thiện các luồng người dùng quan trọng và đưa app tới trạng thái **Release Candidate**.

---

## 1. Mục tiêu Release Candidate

Sau batch này ShiftEase phải đạt:

1. Không có write-path UI quan trọng nào có exception rơi thẳng thành unhandled crash.
2. Import/override/pattern/pay-rule giữ đúng append-only/versioning/integrity contract.
3. Imported roster có thể được chỉnh thủ công kể cả khi job không có active pattern.
4. Income estimator dùng đúng Money Engine semantics, đặc biệt differential theo `HOURS_IN_WINDOW`.
5. Income dashboard có breakdown đáng tin theo ngày/tuần/tháng và nhiều PayRule version.
6. Income Impact cho thay đổi roster/override.
7. CSV mapping + re-import diff đủ dùng cho import workflow thực tế.
8. Notification không để lại reminder stale và xử lý permission/lifecycle đúng.
9. Backup/restore an toàn.
10. SQLCipher thật được tích hợp và verify trên platform target.
11. Android/iOS production flow được chuẩn bị và device-tested ngoài sandbox.
12. Documentation/evidence phản ánh đúng source hiện tại.

**Không được đánh đổi correctness để lấy UX tiện hơn. Khi không đủ dữ liệu để tính chính xác → `UNAVAILABLE` + lý do.**

---

# 2. PHẦN A — Data Integrity Hardening (P1 — bắt buộc)

## A1 — UI write error boundary

Audit toàn bộ write action:

- CREATE
- UPDATE
- DELETE
- REPLACE
- SPLIT
- SWAP
- roster re-version
- import commit
- PayRule save
- template save
- backup/restore

Exception từ repository/domain phải được chuyển thành trạng thái lỗi có thể hiển thị cho user; không để exception rơi thẳng khỏi event handler.

Yêu cầu:

- Không nuốt lỗi.
- Có message thân thiện.
- Giữ nguyên data nếu transaction thất bại.
- Có retry/reopen action khi phù hợp.

**Tests:** DB exception / immutable-history exception / validation exception từ UI write path.

---

## A2 — Imported-only roster phải hỗ trợ CREATE

`createShiftOnDate()` hiện yêu cầu active pattern. Điều này không phù hợp với job có schedule chỉ đến từ imported roster.

Thiết kế bắt buộc:

- CREATE phải attach được vào effective schedule dù job không có active pattern.
- Nếu cần `patternId`, phải có convention rõ ràng cho imported-origin CREATE hoặc một origin type phù hợp.
- Không tạo pattern giả chỉ để vượt validation.
- Render/restart phải giữ ca CREATE đúng.

**Tests:**

- imported-only job → CREATE
- restart → CREATE vẫn tồn tại
- DELETE imported occurrence → đúng
- CREATE cùng ngày OFF → conflict policy rõ ràng.

---

## A3 — Materialized occurrence semantics

Chốt rõ `occurrences` là **materialized effective-schedule cache**, không phải historical source of truth.

Historical truth gồm:

- patterns/version
- overrides
- import sessions
- pay-rule versions/snapshots khi có

Khi persist render projection trong một scope:

- rows không còn trong effective projection phải được remove trong scope đó;
- update + delete phải transactionally consistent;
- không để stale occurrence bị API/UI khác đọc như ca hiện tại.

Nếu source hiện tại chọn semantics khác, phải document và chứng minh invariant tương ứng.

**Tests:** pattern shift → DELETE → projection empty; import suppression → projection empty; re-render/restart không resurrect stale row.

---

## A4 — Import state machine hardening

Invariant:

```text
IDLE → PARSING → EXTRACTED/ERROR → REVIEWING → COMMITTED
```

Chỉ `REVIEWING` mới được COMMIT.

Reject:

- EXTRACTED → COMMIT
- ERROR → COMMIT
- COMMITTED → COMMIT
- zero approved candidates → COMMIT

Committed session immutable:

- cùng payload → idempotent
- khác payload → `ImmutableHistoryError`

**Tests:** toàn bộ invalid transition matrix.

---

## A5 — Import conflict validation

Trước commit phải phát hiện và chặn các trạng thái mâu thuẫn, tối thiểu:

- cùng ngày vừa `OFF` vừa `SHIFT` nếu semantics không cho phép;
- duplicate candidate identity;
- candidate thiếu date/time bắt buộc;
- invalid overnight/timezone;
- DST ambiguous/nonexistent chưa được resolve.

Không tự chọn candidate để "cho chạy được".

**Tests:** conflict matrix + zero mutation khi commit bị reject.

---

## A6 — Override immutable identity

Giữ contract hiện tại:

- cùng ID + canonical payload giống nhau → idempotent no-op;
- cùng ID + payload khác → `ImmutableHistoryError`;
- không silent ignore conflict.

Bổ sung canonical comparison nếu cần để thứ tự field/list không tạo false difference.

**Tests:** same payload / reordered equivalent payload / different payload.

---

## A7 — Atomic roster re-version

`changeRosterFrom()` phải:

```text
BEGIN
  close old version
  create new version
COMMIT
```

Failure ở bất kỳ bước nào → rollback toàn bộ.

**Tests:** fail-before / fail-between / success / restart.

---

## A8 — PayRule integrity

- Unknown `jobId` phải reject, không tự tạo fake Job.
- Save PayRule không được silently biến malformed input thành rule khác.
- `night/weekend/OT` input invalid hoặc âm → validation error.
- Logical child lists phải compare order-independently nếu semantics là unordered.
- Version immutable sau khi đã commit/use.

**Tests:** unknown job, malformed number, negative multiplier/rate, reordered differential/OT rules.

---

# 3. PHẦN B — M3 Income Engine (P1 — bắt buộc)

## B1 — Estimator parity với Money Engine

`estimateJobIncome` / estimator phải sử dụng đúng semantics của `calculatePayBreakdown`.

Bắt buộc hỗ trợ:

- regular pay
- DAY OT
- SHIFT OT
- WEEK OT
- multiple OT rules → đúng max-rule semantics
- differential PERCENT/FLAT
- `ALL_HOURS_IN_SHIFT`
- `HOURS_IN_WINDOW`
- overnight
- DST spring-forward
- DST fall-back
- weekend
- multiple weeks
- multiple PayRule versions

**Không được dùng band cứng kiểu 19:00–06:00 để thay thế `HOURS_IN_WINDOW`.**

Window overlap phải dựa trên resolved UTC instants theo PAY-013 semantics.

### Golden requirement

Estimator result phải khớp Money Engine trên các case tương ứng.

Đặc biệt phải có golden:

- PAY-013 window differential
- PAY-014 weekly LIFO `$1505`
- overnight window
- DST week

---

## B2 — PayRule version semantics: KHÔNG dùng rule của ngày đầu tuần cho cả tuần

**Quyết định đã chốt:** PayRule được resolve **theo từng occurrence**.

Không triển khai quy tắc:

> "trong tuần dùng PayRule active ngày đầu tuần".

Ví dụ:

```text
Mon–Wed → Rule A
Thu–Sun → Rule B
```

phải được tính:

```text
Mon–Wed → A
Thu–Sun → B
```

### Weekly OT

Nếu một payroll week chứa nhiều PayRule versions và semantics phân bổ weekly OT chưa được chứng minh:

```text
UNAVAILABLE
reason = weekly overtime cannot be determined across multiple pay-rule versions
```

**Không đoán và không dùng rule đầu tuần cho toàn bộ tuần.**

Nếu agent muốn implement prorating/segmentation chính xác hơn, phải có test chứng minh đầy đủ trước khi merge.

---

## B3 — Income breakdown screen

Route từ income card tới full screen.

Phải có:

```text
Date / Range
Hours
Regular Pay
Differentials
  - Night
  - Weekend
  - Holiday (nếu rule/data có)
Overtime
  - Day
  - Shift
  - Week
----------------
Estimated Total
```

Mỗi khối tiền phải có:

> **Ước tính — không phải bảng lương chính thức**

Nếu không đủ config:

> **Unable to calculate accurately**

kèm lý do cụ thể.

Không hiển thị `$0` để che missing config.

---

## B4 — Range/date/week/month calculation

Hỗ trợ:

- Today
- current week
- arbitrary week
- month
- custom date range

Không được assume range luôn cùng PayRule version.

Nếu range chứa nhiều versions:

- per-occurrence resolve;
- total deterministic;
- weekly OT theo B2.

---

## B5 — Template library

Picker trong PayRule editor:

- US-CA Nurse
- US-NY
- US-TX
- UK NHS
- DE

Flow:

```text
Choose template
↓
prefill editor
↓
user review/edit
↓
explicit Save
```

Không save ngầm.

Template phải được coi là **preset khởi đầu**, không phải legal/payroll guarantee.

UI disclaimer ngắn gọn:

> Verify this preset against your employer/payroll policy.

---

## B6 — Income Impact

### Roster re-version

Preview:

```text
Estimated this week
Before   $X
After    $Y
Impact   +/-$Z
```

### UPDATE / REPLACE / DELETE / CREATE

Occurrence sheet hiển thị impact nếu có thể tính chính xác.

Calculation:

```text
old effective schedule → estimate
new effective schedule → estimate
```

**persist = false** trong preview.

Không được mutate database chỉ để tính preview.

Nếu missing rule → `UNAVAILABLE`, không fake `$0`.

---

## B7 — Weekly income strip + multi-job

Calendar week có income strip theo ngày.

Multi-job:

```text
Job A  $X
Job B  $Y
Job C  Unable to calculate
----------------
Available total $Z
```

Tổng chỉ cộng job có result AVAILABLE.

Phải ghi rõ:

> Total excludes jobs that could not be calculated.

Không biến missing-job thành `$0`.

---

# 4. PHẦN C — CSV + Re-import Diff (M2b)

## C1 — CSV mapping UI

Flow:

```text
Choose CSV
↓
Preview rows
↓
Map columns
  date
  start
  end
  shift type/template
  optional job
↓
Validate
↓
Review candidates
↓
Commit
```

Không commit trước Review.

Validation phải báo:

- unmapped required column
- invalid date/time
- duplicate row
- timezone ambiguity
- malformed row count.

---

## C2 — Re-import diff

So sánh roster mới với committed roster hiện tại:

```text
Added
Removed
Modified
Unchanged
```

Mỗi modified item phải có old → new.

Summary:

```text
+3 shifts
-1 shift
~2 changed
Hours: +8h
Income impact: +$280 (estimate)
```

Nếu income unavailable → ghi rõ reason.

Commit vẫn phải qua Review.

---

# 5. PHẦN D — DST UX

DST engine hiện đã đúng; UI phải phản ánh đúng semantics.

### NONEXISTENT

Block save và giải thích.

### AMBIGUOUS

**Khuyến nghị production:** cho user chọn một trong hai interpretation:

```text
01:30 EDT
01:30 EST
```

Nếu architecture hiện tại chưa thể lưu selected offset/interpretation an toàn thì giữ block-save, nhưng phải sửa wording thành:

> This local time occurs twice. Choose another time.

Không được hiển thị như thể user đã "resolve" trong khi payload vẫn chưa lưu interpretation.

Bắt buộc test start và end time.

---

# 6. PHẦN E — Notification Production Hardening

## E1 — Stale reminder cancellation

Nếu shift kế tiếp thay đổi hoặc không còn:

```text
cancel old reminder
```

Không để notification cũ tồn tại.

Cases:

- DELETE shift
- UPDATE time
- REPLACE
- import commit
- roster re-version
- no upcoming shift

Fixed notification ID vẫn được dùng để tránh duplicate.

## E2 — App lifecycle

Khi app resume:

```text
reload effective schedule
↓
recalculate next reminder
↓
cancel stale
↓
schedule current
```

## E3 — Android/iOS permission

Production flow:

- permission unknown → request
- denied → explain
- permanently denied → Settings fallback
- enabled → schedule

Android 13+ notification permission phải được xử lý thật.

Device test bắt buộc ngoài sandbox.

---

# 7. PHẦN F — Backup / Restore

Local-first app phải có full backup trước release.

## F1 — Backup

Backup tối thiểu:

- jobs
- templates
- patterns + versions
- overrides
- import sessions
- pay rules
- pay snapshots/history nếu có
- settings

Backup phải có schema/version.

## F2 — Restore

Flow:

```text
Select backup
↓
Validate format/schema/checksum
↓
Preview
↓
Explicit confirmation
↓
Transactional restore
↓
Verify
```

Không overwrite DB bằng file backup chưa validate.

Nếu restore fail → database cũ nguyên vẹn.

## F3 — Data export

ICS không được coi là full backup.

---

# 8. PHẦN G — SQLCipher + Local Security

**Đây là production blocker nếu app lưu dữ liệu nhạy cảm.**

Không được coi:

```text
sqlite3.open()
PRAGMA key
```

là SQLCipher integration.

Cần:

- SQLCipher native dependency đúng platform
- secure random DB key
- key storage bằng platform secure storage
- open/verify encrypted DB
- migration trên encrypted DB
- wrong-key failure test
- backup encryption

Không hardcode key.

Phải có Android + iOS verification.

---

# 9. PHẦN H — Production Settings / App UX

Tối thiểu:

### General

- default timezone
- week starts on
- time format

### Notifications

- enable/disable
- lead time
- permission status

### Data

- Backup
- Restore
- Export ICS
- Delete all data (double confirmation)

### Privacy/Security

- encryption status

### About

- version
- Privacy Policy
- Terms
- Support

Không cần làm account/cloud trong batch này.

---

# 10. PHẦN I — Mobile Release Readiness

Không build APK trong sandbox nếu toolchain không có.

Nhưng agent phải đảm bảo source/config/platform structure đúng.

CI hoặc máy thật phải verify:

### Android

- fresh install
- existing DB migration
- encrypted DB
- notification permission
- notification after app restart
- notification after reboot nếu semantics yêu cầu
- timezone change
- DST
- backup/restore
- import
- override
- PayRule

### iOS

Tương tự, phù hợp platform APIs.

### App lifecycle

- background
- resume
- force kill/reopen
- process restart

---

# 11. PHẦN J — Adversarial / Regression Test Suite

Bổ sung test matrix tối thiểu:

## Data

- transaction failure
- migration failure
- stale occurrence removal
- duplicate IDs
- restart persistence

## Import

- EXTRACTED → COMMIT reject
- ERROR → COMMIT reject
- zero approved reject
- OFF + SHIFT conflict
- duplicate candidate
- malformed reference date
- DST ambiguous/nonexistent
- import-only job

## Override

- same ID same payload
- same ID equivalent reordered payload
- same ID different payload
- CREATE → UPDATE
- CREATE → DELETE
- imported → UPDATE
- imported → DELETE

## Pay

- missing rule
- malformed rule
- negative rate/multiplier
- DAY OT
- SHIFT OT
- WEEK OT
- overnight
- window differential
- multiple windows
- DST spring/fall
- multiple PayRule versions
- multiple weeks

## Notification

- delete upcoming shift
- change upcoming shift
- no upcoming shift
- permission denied
- resume

## Backup

- corrupted backup
- incompatible schema
- wrong encryption key
- restore failure rollback
- successful round-trip.

---

# 12. Documentation / Evidence

Agent phải cập nhật sau khi code/test xong:

- `checklist.md`
- `features.md`
- `next.md`
- `.plan/features.md` nếu là canonical source
- `result16_rc.txt`
- `handoff_YYYYMMDD_HHMMSS.md`

### Evidence order bắt buộc

1. code
2. targeted tests
3. full test
4. analyze
5. `ls` xác nhận result file
6. docs update
7. handoff

Không được ghi checklist là "done" trước khi result file thực sự tồn tại.

Nếu task không thực hiện được do sandbox/device limitation → ghi **BLOCKED**, không ghi PASS.

---

# 13. Definition of Done — Release Candidate

Batch chỉ được coi là DONE khi:

### Correctness

- [ ] tất cả P1 integrity items A1–A8 pass
- [ ] estimator parity pass
- [ ] no silent fallback
- [ ] no stale projection

### Product

- [ ] Income dashboard
- [ ] template library
- [ ] Income Impact
- [ ] weekly strip
- [ ] multi-job
- [ ] CSV mapping
- [ ] re-import diff

### Reliability

- [ ] notification stale cancellation
- [ ] lifecycle resync
- [ ] permission flow
- [ ] backup/restore

### Security

- [ ] SQLCipher real integration
- [ ] secure key storage
- [ ] encrypted backup

### Mobile

- [ ] Android device/CI verification
- [ ] iOS device/CI verification

### Quality

- [ ] targeted adversarial tests pass
- [ ] full suite pass
- [ ] `flutter analyze` clean
- [ ] evidence files exist on disk
- [ ] docs consistent with source

**Không được gọi app "publish-ready" nếu còn blocker trong các mục trên.**

---

# 14. Explicitly deferred — KHÔNG làm trong batch này

- OCR / PDF OCR
- M4.5 OCR spike
- Cloud sync
- Dynamic Webcal
- Sharing/FULL/BUSY_ONLY/RECOVERY
- Partner/family overlay
- Availability Finder
- Health AI
- B2B/team management
- Tax/net-pay calculation
- payroll/legal compliance engine

Các mục trên chỉ mở sau khi Release Candidate batch này pass review.

---

# 15. Agent execution order

Để giảm regression, code theo thứ tự:

```text
A — Integrity
 ↓
B — Income engine + dashboard
 ↓
C — CSV + re-import diff
 ↓
D — DST final UX
 ↓
E — Notifications/lifecycle
 ↓
F — Backup/restore
 ↓
G — SQLCipher/security
 ↓
H — Settings
 ↓
I — mobile readiness
 ↓
J — adversarial + full regression
 ↓
Evidence/docs/handoff
```

Mỗi section phải chạy targeted tests ngay sau khi sửa; full suite chỉ chạy khi toàn batch hoàn tất.

**Sau batch này mới tiến hành một vòng review độc lập cuối cùng để quyết định Closed Testing / Store Release.**
