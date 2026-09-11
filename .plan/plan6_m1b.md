# ShiftEase — Plan6: Gate M1b (Today · Month · Quick Add · Roster re-version) — ✅ ĐÃ DUYỆT

Ngày: 2026-09-05 · Trạng thái: **approved (thứ tự M1b → M2 · scope gồm re-version UI) — code xong, result12_m1b.txt**
Nguồn: features.md D1/D2/D3/B4 + result11 §6 điểm 3. Kế thừa toàn bộ M1 (plan5).

## 1. Phạm vi

| Có | KHÔNG (gate sau) |
|---|---|
| **Today screen** — ca hôm nay (mọi job), ca kế tiếp + đếm ngược giờ nghỉ trước ca sau, tổng giờ làm tuần này (từ UTC — INVARIANT-002) | Thu nhập hôm nay/tuần → **M3** (chưa có PayRule UI; engine sẵn) |
| **Month view** (per job) — lưới tháng, badge/count ca theo ngày, điều hướng tháng; tap ngày → nhảy WeekCalendar đúng tuần | Multi-job overlay trên 1 lịch (P2) |
| **Quick Add 1-tap** — tap ngày → sheet liệt kê template của job; tap template = CREATE ngay (giờ mặc định, không form); mục "Custom time…" mở form đầy đủ | 1-tap ở Today cho mọi job (nhiều job → chọn job trước, P2) |
| **Roster re-version UI** — Pattern detail → "New version from date X" → PatternBuilder prefill → `service.changeRosterFrom` (D9 anchor bất biến); bản cũ tự đóng effectiveUntil = X−1 | Chỉnh anchor/phase (tạo pattern mới = hành vi có sẵn) |

## 2. Ràng buộc (giữ nguyên M1)

- Mọi thay đổi ca = Override append-only; mọi render qua `renderJobSchedule` (service).
- Màn hình đọc dùng `persist:false` (Today/Month) — render thuần không ghi DB khi build.
- Hiển thị local time qua `localWallTime` (INVARIANT-007) — không dùng timezone thiết bị.
- Giờ làm từ `calculateDuration(UtcInstant.parse(...))` — INVARIANT-002, không trừ local.
- Income KHÔNG hiển thị trong M1b; không "đoán" pay khi chưa có rule (Correctness Contract).
- Re-version: `createNewVersion` engine giữ nguyên anchorDate (D9) — phase không reset.

## 3. API bổ sung (domain)

```dart
// schedule_service.dart
double workedHoursOf(ShiftOccurrence o);          // tính từ UTC
double sumHours(Iterable<ShiftOccurrence> o);     // fold
renderJob(..., persist: false)                    // đã có — dùng cho Today/Month
changeRosterFrom(...)                             // đã có — UI gọi sau khi builder
```

## 4. Màn hình & navigation

- JobsScreen AppBar → action **Today** → `features/today/today_screen.dart` (mọi job).
- JobDetail → 3 nút: **View week** · **View month** (mới) · **New pattern**; tap 1 pattern → sheet pattern (info + "New version from date…") → date picker → `PatternBuilderScreen(existing, newEffectiveFrom)`.
- WeekCalendarScreen: thêm `initialDate` (Month jump); tap header ngày → QuickAddSheet (template list + Custom) thay vì form trực tiếp.
- MonthCalendarScreen (mới): grid 7×6, render `first..last` persist:false, badge; tap ngày → WeekCalendar(initialDate: ngày đó).

## 5. Test (widget, DB thật)

1. Today: job ca hôm nay render + tổng giờ tuần đúng (12h×4 = 48).
2. Month: badge đúng số ca trong tháng; tap 1 ngày → WeekCalendar tuần đúng.
3. Quick Add: tap ngày OFF → tap template tile → card hiện + log đúng 1 CREATE (patternId != null); "Custom time…" mở form.
4. Re-version: pattern v1 → new version từ X → 2 rows (v1 đóng X−1, v2 mở X), render range chứa seam: v1 ngày cũ byte-identical, v2 từ X, không gap/dup; anchor bằng nhau (D9).
5. Core 155/155 giữ nguyên · M1 5 tests giữ nguyên.

## 6. DoD M1b

Today hiển thị đúng ca + giờ tuần · Month điều hướng vào tuần đúng · Quick Add 1-tap ghi đúng 1 CREATE · đổi roster từ ngày X qua UI → lịch trước X không đổi, sau X theo bản mới, anchor giữ nguyên.
