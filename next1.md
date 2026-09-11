Đúng. Tôi đã đối chiếu trực tiếp `production_roadmap.md` và trạng thái mới nhất của project.

### Kết luận hiện tại

**ShiftEase đang ở P7 — Production Verification / Security / Real Devices.**

Roadmap có **10 phase: P0 → P9**. P0–P6 đã hoàn thành; còn **P7, P8, P9** trước khi có thể tuyên bố Production.

Đặc biệt, review mới nhất `result18_code_review_rc.txt` cho thấy RC khá tốt: **292/292 tests PASS**, `flutter analyze` sạch. Tuy nhiên vẫn còn:

* 🔴 **H1 HIGH:** backup production có khả năng rơi vào `systemTemp`/cache → **phải sửa trước release**.
* 🟠 **M1 MEDIUM:** Income Impact đang có thể bỏ qua row không resolve được → có thể tạo tổng income sai → **nên sửa ngay P7**.
* 🟡 M2: iOS notification permission status.
* 🟢 L4: notification window 13 ngày.

Tôi đã đưa H1/M1 vào P7, không để chúng bị bỏ sót.

### Tôi đã tạo 4 file

1. **P7_production_verification.md**
   Toàn bộ công việc còn lại quan trọng nhất: H1/M1 → SQLCipher thật → secure key storage → Android/iOS notification → lifecycle → migration → backup/restore thực tế → DST/timezone → security → final regression.

2. **P8_release_preparation.md**
   Release build Android/iOS → signing → versioning → store assets → privacy/policy → internal testing → closed testing → freeze RC.

3. **P9_production_launch.md**
   Production submission → staged launch → monitoring → crash/data/migration/notification monitoring → P0/P1 hotfix procedure → post-production review.

4. **PRODUCTION_REVIEW.md**
   File handoff tổng hợp cho agent: trạng thái hiện tại, các blocker, execution order và các nguyên tắc agent tuyệt đối không được phá.

[**Download toàn bộ 4 file + ZIP**](sandbox:/mnt/data/ShiftEase_remaining_production_phases.zip)

Các file này được viết theo kiểu **agent có thể đọc rồi triển khai**, không chỉ là roadmap chung chung.

---

## Thứ tự tôi khuyến nghị agent chạy

```text
P7.1  Fix H1 + M1
  ↓
P7.2  SQLCipher thật
  ↓
P7.3  Android secure key storage
P7.4  iOS Keychain
  ↓
P7.5  Android notification device test
P7.6  iOS notification device test
  ↓
P7.7  Lifecycle
  ↓
P7.8  Database migration
  ↓
P7.9  Real-device backup/restore
  ↓
P7.10 DST + timezone
  ↓
P7.11 Security review
  ↓
P7.12 Final regression + evidence
  ↓
P8 Release Preparation
  ↓
P8 Internal Testing
  ↓
P8 Closed Testing
  ↓
P9 Production Launch
```

### Một điểm rất quan trọng

Tôi **không khuyến nghị agent mở thêm feature lúc này**.

`production_roadmap.md` đã xác định đúng hướng: sau khi core đã có **calendar + import + CSV re-import + income + multi-job + backup + notification**, rủi ro lớn nhất hiện tại không còn là “thiếu feature”, mà là **database security, data loss, migration, notification và hành vi thực tế trên Android/iOS**.

Các thứ như OCR, Cloud Sync, AI, family sharing, B2B, payroll/tax... nên để **sau production**, đúng với roadmap hiện tại. `next.md` cũng đang ghi nhận RC A–J hoàn tất và device/security verification là phần còn lại. 

**Nếu đưa cho agent ngay, hãy đưa `PRODUCTION_REVIEW.md` + `P7_production_verification.md` trước.** Agent chỉ nên chuyển sang P8 sau khi P7 có evidence PASS thật, không phải chỉ tick checkbox.
