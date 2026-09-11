tiếp tục https://chatgpt.com/c/6a98d55c-163c-83ec-8ec4-da38a1abcbe3
agent đã sửa code mới tại /Users/hoang/htdocs_apps/ShiftEase rà soát kỹ xem đã đúng hết yêu cầu .plan/plan8_m3_income.md chưa.
Đang ở phase nào rồi, app này có tổng mấy phase. Hãy liệt kê toàn bộ phase app cần phải làm để ra production
--------------------
Mình đã rà trực tiếp source hiện tại của `/Users/hoang/htdocs_apps/ShiftEase`, `.plan/plan8_m3_income.md`, `result16_rc.txt`, `result17_review_rc.txt` và `handoff_20260910_rc_complete.md`.

1\. Kết luận nhanh
------------------

**Agent đã hoàn thành Plan8 ở mức code + test, nhưng ShiftEase CHƯA được coi là production/publish-ready.**

Trạng thái hiện tại chính xác nhất là:

> **Release Candidate — RC batch A–J đã hoàn thành, nhưng còn 3 nhóm blocker phải verify trên Android/iOS/CI trước khi Closed Testing / Store Release.**

Evidence mới nhất:

*   `flutter analyze --no-pub` → **No issues found**
    
*   `flutter test test/` → **288/288 PASS**
    
*   Regression: **0**
    
*   Plan8 A–J: **đã implement**
    
*   Nhưng:
    
    *   E3 Android/iOS notification runtime → **BLOCKED**
        
    *   G SQLCipher thật + secure key storage → **BLOCKED**
        
    *   I real-device/CI verification → **BLOCKED**
        

Điểm rất quan trọng: review độc lập `result17_review_rc.txt` đã **đọc source và chạy lại test**, không chỉ tin báo cáo của agent. Nó xác nhận Plan8 đã hoàn thành về mặt source/test.

* * *

2\. Plan8 đã đáp ứng yêu cầu đến đâu?
=====================================

### A — Data Integrity Hardening: ✅

A1–A8 đã được đóng:

*   UI write error boundary
    
*   Imported-only roster CREATE
    
*   materialized occurrence semantics
    
*   Import state machine
    
*   import conflict validation
    
*   immutable override identity
    
*   atomic roster re-version
    
*   PayRule integrity
    

Đặc biệt gap lớn trước đây:

> `imported-only job → CREATE`

đã được xử lý và có test `rc_imported_create`.

### B — M3 Income Engine: ✅

Đây là phần quan trọng nhất của Plan8.

Đã xử lý:

*   estimator parity với Money Engine
    
*   `HOURS_IN_WINDOW`
    
*   overnight
    
*   DST
    
*   DAY/SHIFT/WEEK OT
    
*   nhiều PayRule version
    
*   range/week/month
    
*   Income Breakdown
    
*   templates
    
*   Income Impact
    
*   weekly income strip
    
*   multi-job
    

Và quyết định nguy hiểm trước đây cũng đã được sửa:

> **Không dùng PayRule của ngày đầu tuần cho toàn bộ tuần.**

Hiện semantics là resolve PayRule **theo từng occurrence**.

Nếu weekly OT không xác định được khi có nhiều PayRule version:

> `UNAVAILABLE`

Đây là đúng với Correctness Contract của app.

* * *

### C — CSV + Re-import Diff: ✅

Đã có:

    CSV
     ↓
    Preview
     ↓
    Mapping
     ↓
    Validate
     ↓
    Review
     ↓
    Commit

Và diff:

    Added
    Removed
    Modified
    Unchanged

Có cả:

*   hours delta
    
*   income impact
    
*   old → new
    
*   `persist:false` khi preview
    

* * *

### D — DST UX: ✅

Điểm này cũng đã sửa đúng.

Fall-back:

    01:30 EDT
    01:30 EST

user **thực sự chọn một interpretation**.

Offset được lưu vào override payload và restart vẫn giữ đúng instant.

Spring-forward nonexistent time vẫn block.

* * *

### E — Notification: 🟢 source / 🔴 device

Đã sửa stale reminder:

    DELETE shift
    → cancel old reminder

Đã có lifecycle:

    RESUME
     ↓
    reload schedule
     ↓
    recalculate reminder
     ↓
    cancel stale
     ↓
    schedule current

Nhưng Android 13+ runtime permission **chưa được verify trên device**.

\=> **BLOCKED, không PASS production.**

* * *

### F — Backup / Restore: ✅

Đã có:

*   full backup
    
*   schema/version
    
*   checksum
    
*   validate trước restore
    
*   transactional restore
    
*   rollback khi lỗi
    
*   verify sau restore
    
*   delete all data
    
*   round-trip test
    

Đây là một nâng cấp rất lớn so với trạng thái trước Plan8.

* * *

### G — SQLCipher: ⚠️ CHƯA production

Đây là blocker quan trọng nhất.

Code hiện tại có:

*   encryption key generation
    
*   secure random
    
*   SecretStore seam
    
*   encryption verification
    
*   `PRAGMA cipher_version` probe
    
*   plain SQLite sẽ báo **NOT encrypted**
    

Nhưng:

> **SQLCipher native thật chưa được tích hợp/verify trên Android + iOS.**

Agent **không claim giả là encrypted**, đây là điểm tốt.

Do đó:

**G = BLOCKED.**

* * *

### H — Settings: ✅

Đã có:

*   General
    
*   Notifications
    
*   Data
    
*   Backup
    
*   Restore
    
*   Delete all
    
*   ICS
    
*   Privacy/Security
    
*   encryption status
    
*   About
    

* * *

### I — Mobile production readiness: ⚠️ BLOCKED

Đã có documentation + 15-row verification matrix.

Nhưng chưa chạy được:

*   Android real device
    
*   iOS real device
    
*   CI
    

Do đó toàn bộ mobile matrix vẫn:

> **BLOCKED**

chứ không phải PASS.

* * *

### J — Adversarial regression: ✅

Đã có adversarial tests.

Full:

**288/288 PASS**

* * *

3\. Vậy hiện tại đang ở Phase nào?
==================================

**Đang ở Phase Release Candidate / Production Verification.**

Không còn ở M3 coding nữa.

Có thể biểu diễn:

    M0 Foundation
       ↓
    M1 Basic Calendar
       ↓
    M1b Today / Month / Quick Add / Roster Re-version
       ↓
    M2 Import
       ↓
    M2b CSV / Re-import
       ↓
    M3 Income
       ↓
    RC A–J
       ↓
    👉 HIỆN TẠI: Release Candidate Verification
       ↓
    Android/iOS + SQLCipher + notification verification
       ↓
    Closed Testing
       ↓
    Store Release

**Plan8 A–J đã xong.**

Bây giờ không nên mở thêm feature lớn.

* * *

4\. App này tổng cộng bao nhiêu phase?
======================================

Có một điểm cần phân biệt.

Plan2 ban đầu định nghĩa roadmap:

| Milestone | Nội dung |
| --- | --- |
| **M0** | Foundation — Time + Pattern + Money |
| **M1** | Basic Calendar |
| **M2** | Import |
| **M3** | Multi-job + Pay breakdown |
| **M4** | Export & Share |
| **M4.5** | OCR feasibility spike |
| **M5** | OCR Import |

Nhưng trong quá trình build, roadmap đã được **refactor thực tế** thành nhiều gate nhỏ hơn. Ví dụ M1 được tách M1b, M2 có M2b, rồi Plan8 trở thành RC batch.

Vì vậy nếu hỏi:

> **"Từ code hiện tại đến app production còn bao nhiêu phase?"**

thì mình **không khuyên dùng M0–M5 cũ**, vì nó không còn phản ánh trạng thái thực tế.

### Roadmap production thực tế mình chốt là 9 phase

| Phase | Tên | Trạng thái |
| --- | --- | --- |
| **P0** | Foundation / Core Contract | ✅ Done |
| **P1** | Calendar + Pattern + Override | ✅ Done |
| **P2** | Today / Month / Quick Add / Re-version | ✅ Done |
| **P3** | Smart Import + Review + Commit | ✅ Done |
| **P4** | CSV + Re-import Diff | ✅ Done |
| **P5** | Income / Pay / Multi-job | ✅ Done |
| **P6** | Release Candidate Integrity & Reliability | ✅ Done |
| **P7** | Security + Mobile Device Verification | ⏳ **ĐANG LÀM** |
| **P8** | Closed Testing / Store Release | ⏳ Sau P7 |

Nói ngắn gọn:

> **8 phase đầu đã cơ bản hoàn thành. Hiện đang ở P7. Sau P7 chỉ còn P8 để đưa lên store.**

* * *

5\. P7 hiện còn chính xác những gì?
===================================

Không nên để agent tiếp tục "code thêm feature".

P7 nên chỉ tập trung vào **verification + production wiring**:

### P7.1 — SQLCipher thật

Phải có:

    SQLCipher native
            ↓
    encrypted DB
            ↓
    secure key
            ↓
    Android Keystore
            ↓
    iOS Keychain

Test:

*   fresh encrypted DB
    
*   reopen encrypted DB
    
*   wrong key
    
*   migration encrypted DB
    
*   backup encrypted
    
*   restore encrypted
    
*   corrupted encrypted backup
    

* * *

### P7.2 — Android notification

Real Android device:

*   Android 13+
    
*   permission unknown
    
*   request
    
*   granted
    
*   denied
    
*   permanently denied
    
*   Settings fallback
    
*   schedule
    
*   cancel
    
*   update
    
*   app restart
    
*   reboot
    

* * *

### P7.3 — iOS

Test:

*   notification permission
    
*   schedule
    
*   cancel
    
*   update
    
*   restart
    
*   background/resume
    
*   timezone
    
*   DST
    

* * *

### P7.4 — Mobile lifecycle

Phải test thực tế:

    foreground
     ↓
    background
     ↓
    resume
     ↓
    force kill
     ↓
    reopen
     ↓
    timezone change

và sau:

    import
    edit
    delete
    replace
    roster re-version

reminder vẫn đúng.

* * *

### P7.5 — Migration

Ít nhất:

    old DB
     ↓
    upgrade app
     ↓
    migration
     ↓
    encrypted DB
     ↓
    data intact

Không chỉ test DB mới.

* * *

### P7.6 — Final regression

Sau device/security fixes:

    flutter analyze
    flutter test
    Android
    iOS

rồi tạo **evidence mới**.

Không dùng lại `result16_rc.txt` làm bằng chứng cuối cùng nếu source đã thay đổi.

* * *

6\. Sau P7 là gì?
=================

P8 — Closed Testing / Store Release
-----------------------------------

Chỉ khi:

*   SQLCipher PASS
    
*   Android PASS
    
*   iOS PASS
    
*   notification PASS
    
*   backup/restore PASS trên device
    
*   migration PASS
    
*   full regression PASS
    
*   privacy policy
    
*   terms
    
*   support
    
*   app icon
    
*   screenshots
    
*   store metadata
    
*   release signing
    
*   version/build number
    
*   crash reporting nếu chọn
    
*   final smoke test
    

thì mới:

    Internal testing
           ↓
    Closed testing
           ↓
    Fix production bugs
           ↓
    Production release

* * *

7\. Có cần làm M4/M4.5/M5 không?
================================

**Không nên làm trước khi publish MVP.**

Plan8 đã explicitly defer:

*   OCR/PDF OCR
    
*   Cloud sync
    
*   Sharing
    
*   Webcal dynamic
    
*   Partner/family
    
*   Availability Finder
    
*   Health AI
    
*   B2B
    
*   Tax/net-pay
    
*   payroll/legal engine
    

Và mình đồng ý với quyết định này.

Đặc biệt **OCR không nên chen vào bây giờ**.

App hiện đã có một core rất rõ:

> **Shift calendar → import → edit → correct time/DST → pay estimate → backup → offline.**

Đưa app ra thị trường trước sẽ hợp lý hơn là tiếp tục biến nó thành một hệ thống khổng lồ.

* * *

8\. Một vấn đề nhỏ cần lưu ý
============================

`result17_review_rc.txt` đã phát hiện `result16_rc.txt` có bảng breakdown test cũ bị sai:

*   core cũ ghi 213 → thực tế 226
    
*   UI 33 → 34
    
*   features 12 → 10
    
*   DB 39 → 42
    

Nhưng:

> **288/288 headline là đúng.**

Đây là documentation/evidence issue, **không phải code correctness issue**. Agent đã ghi addendum để sửa.

* * *

9\. Verdict cuối cùng của mình
==============================

### Code/core

**🟢 Rất tốt**

### Plan8

**🟢 Đã hoàn thành đúng scope**

### Test

**🟢 288/288 PASS**

### Analyze

**🟢 Clean**

### Production

**🟠 Chưa được phép gọi publish-ready**

Chỉ còn blocker thực sự:

                    ShiftEase
                        │
              ┌─────────┴─────────┐
              │                   │
         SQLCipher thật      Real device/CI
              │                   │
              └─────────┬─────────┘
                        ↓
                 Notification
                        ↓
                 Mobile matrix
                        ↓
                  Final smoke
                        ↓
                CLOSED TESTING
                        ↓
                    STORE

**Vì vậy mình sẽ coi project hiện tại là: `P7 — Production Verification`, không phải M3 nữa.**

Và quan trọng: **đừng cho agent mở thêm OCR/AI/Cloud/Sharing lúc này.** Hãy khóa scope và xử lý đúng P7 cho tới khi có bằng chứng Android/iOS thật.