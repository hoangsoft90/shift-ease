# P8.9 / P8.10 — Internal Testing & Closed Testing Protocols (ShiftEase RC)

> Nguồn: `phases/P8_release_preparation.md` §9–§10 · `plan_p8.md` §P8.9/P8.10.

## Part 1 — Internal testing protocol (P8.9)

### 1.1 Điều kiện bắt đầu

- Signed/debug artifact từ CI (hoặc human build) + `doc/release/smoke_checklist.md` PASS trên ≥1 máy thật
- Upgrade test (`doc/release/upgrade_test_plan.md`) PASS
- Freeze áp dụng (`doc/release_freeze.md`)

### 1.2 Phạm vi test nội bộ

| Khu vực | Ghi cụ thể khi chạy |
|---|---|
| Fresh install | install → launch → smoke flow đầu |
| Upgrade | theo upgrade plan |
| Notification | grant/deny/permanent-deny; schedule → receive; edit shift → reminder cập nhật; delete shift → không stale (E1); restart → resync (E2) |
| Backup/restore | round-trip; corrupt file → từ chối, không hỏng DB |
| DST | spring gap → chặn tường minh; fall-back → pick 2 candidate; reminder sau DST vẫn đúng giờ |
| Import/re-import | CSV map → validate → review → commit; re-import diff + income impact (row lỗi → UNAVAILABLE) |
| Income | overnight, differential, overtime, multi-job total |
| Multiple jobs | switch job, total trên dashboard |
| Offline behavior | airplane mode toàn bộ flow (app vốn không network) |

### 1.3 Severity definitions

| Severity | Định nghĩa | Hành động |
|---|---|---|
| **P0** | Crash/l pérd dữ liệu/silent corruption/bảo mật — app không dùng được | **Stop ship.** Fix + rebuild trước khi tiếp tục. |
| **P1** | Feature chính sai kết quả/không dùng được (import sai giờ, income sai, notification không hiện) — không có workaround | **Stop ship.** Fix + rebuild. |
| **P2** | Sai nhưng có workaround, hoặc ảnh hưởng release (UI vỡ nghiêm trọng) | Chủ RC phê duyệt fix-now hoặc post-release; nếu release-blocking → fix + rebuild |
| **P3** | Cosmetic/wording/nice-to-have | Backlog sau release |

### 1.4 Issue template

```text
[ID-YYMMDD-nn] <tiêu đề ngắn>
Severity: P0 | P1 | P2 | P3
Area: install | upgrade | notification | backup | DST | import | income | multi-job | offline | UI
Build: <version+build, artifact source>
Device/OS: <model, Android/iOS version>
Steps to reproduce: 1) … 2) … 3) …
Expected: …
Actual: …
Evidence: screenshot/recording/log
Regression? (was OK in previous RC): yes/no/unknown
```

### 1.5 Luồng quyết định

```text
Mỗi issue → severity → P0/P1: fix → test → rebuild → CHẠY LẠI smoke/upgrade trên build mới
Tất cả P0/P1 đóng + P2 không blocking → internal PASS
```

### 1.6 Kết quả

| Kết luận | Giá trị |
|---|---|
| Internal testing | **NOT RUN — human/device** |
| Open P0/P1 | — (chưa chạy) |

---

## Part 2 — Closed testing protocol (P8.10)

### 2.1 Điều kiện bắt đầu

- **Internal PASS** (Part 1) — không bắt đầu sớm hơn
- Track đã tạo (Play internal/closed track hoặc TestFlight), privacy URL + store listing draft đã host

### 2.2 Cohort

- Nhóm nhỏ thật (đề xuất 5–20 người, ưu tiên người làm ca thật — đối tượng mục tiêu)
- Kênh feedback cố định (form/group), ghi build number trong tin nhắn mời

### 2.3 Focus feedback (theo spec — không thêm)

1. Onboarding: hiểu app làm gì ngay lần đầu mở?
2. Ease of adding shifts: tạo ca nhanh/chậm, vướng ở đâu?
3. Calendar clarity: week/month đọc hiểu được không?
4. Import workflow: map cột + review diff có đáng tin không?
5. Income clarity: số tiền có rõ nguồn gốc không?
6. Notification reliability: reminder có đúng giờ, có xuất hiện?
7. Backup/restore confidence: user có dám tin backup không?
8. Crashes: bất kỳ lần đóng app bất thường nào
9. Confusing wording: từ ngữ nào khó hiểu/sai ngữ cảnh

### 2.4 Quy tắc

- Feedback → issue theo template severity Part 1.4; **P0/P1 → fix + rebuild + re-test, không ship**
- P2 chỉ fix nếu release-blocking; còn lại backlog
- **Không** dùng closed testing để nhồi feature — mọi feature request → `next.md` backlog (D-P8.4)
- Kết thúc cohort: tổng hợp feedback → quyết định freeze RC (P8.11)

### 2.5 Kết quả

| Kết luận | Giá trị |
|---|---|
| Closed testing | **NOT RUN — human** (cần internal PASS trước) |
| Cohort size / dates | — |
| Open P0/P1 | — |
