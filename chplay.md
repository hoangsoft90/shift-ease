# ShiftEase — Google Play Console Submission Pack

> Chuẩn bị ngày 2026-09-11 · Package: `com.shiftease.shiftease` · Target API 36.
> Thông tin điền mẫu: **Tên app = ShiftEase**, **Chức năng = lịch làm việc theo ca + ước tính thu nhập offline**, **Đối tượng = người làm ca/tự do**.

---

## 1. Main Store Listing

### App Name (≤ 30 ký tự)

```
ShiftEase: Work Shift Calendar
```
(28 ký tự — có từ khóa tìm kiếm chính: *shift, work, calendar*)

### Short Description (≤ 80 ký tự)

```
Offline shift calendar for workers. Track shifts & estimate your pay.
```
(76 ký tự)

### Full Description (≤ 4000 ký tự, ASO)

```
📋 ShiftEase — Work Shift Calendar & Income Estimator

Tired of messy shift schedules on paper or in your head? ShiftEase is a clean, offline-first shift calendar built for shift workers — nurses, security staff, retail teams, factory workers, and freelancers with rotating schedules.

⸻

🗓️ ALL YOUR SHIFTS IN ONE PLACE
• Today view: what's happening now, your next shift, and a live countdown
• Month & week calendars with a clear color-coded shift grid
• Quick Add: log a shift in seconds, even on your day off
• Works fully OFFLINE — no account, no sign-up, no internet needed

🔁 ROTATING PATTERNS, ZERO EFFORT
• Build any repeating pattern (e.g. 4-on / 4-off, day–night–off cycles)
• Changes apply from a chosen date — your history is never rewritten
• Edit a single day (swap, replace, split) without touching the pattern

💰 KNOW WHAT YOUR WORK IS WORTH
• Enter your hourly rate once — see estimated income for any week or month
• Night & weekend differentials and weekly overtime supported
• Before/after preview shows how a schedule change affects your pay
• Honest estimates: if a rule is missing, ShiftEase tells you instead of guessing

📥 IMPORT YOUR ROSTER IN MINUTES
• Paste a roster or import a CSV — ShiftEase reads shifts and days off
• Review everything before it enters your calendar (you stay in control)
• Re-import later and see exactly what changed

⏰ NEVER MISS A SHIFT
• Reminder notification before each shift starts
• Automatic rescheduling when your roster changes

🔐 YOUR DATA STAYS YOURS
• Encrypted local database (SQLCipher) — your schedule never leaves your device
• Encrypted with a key stored in your device's secure hardware
• Full backup & restore to a file you keep yourself
• Export any week to a calendar (.ics) file

✨ DESIGNED FOR REAL SHIFT LIFE
• Overnight shifts handled correctly across midnight
• Daylight-saving time edge cases resolved — never a silently wrong hour
• Each job can have its own time zone

⸻

👥 WHO IS IT FOR?
Shift workers in healthcare, hospitality, retail, manufacturing, logistics, security — anyone whose week looks different every week. Also great for freelancers tracking multiple clients.

⸻

📌 HONEST NOTES
• Income figures are ESTIMATES from the rules you enter — not payroll advice
• The app shows ads (banner between screens). Nothing else leaves your device except crash reports (no personal data) and ad requests
• No sign-up, no tracking of your schedule, no cloud

⸻

Download ShiftEase free and take control of your shift schedule today!
```
(≈ 2.6k ký tự — dưới giới hạn 4000)

---

## 2. Store Settings

| Mục | Giá trị chọn |
|---|---|
| **App category** | **Productivity** (lựa chọn thay thế: *Lifestyle*) |
| **Tags (5)** | 1. `Work schedule` · 2. `Calendar` · 3. `Time management` · 4. `Shift planner` · 5. `Personal organizer` |
| Contains ads | **Yes** (AdMob banner) |
| In-app purchases | No |
| Free / Paid | Free |

---

## 3. Graphics & Assets

### Screenshots — 4 ảnh (điện thoại, khuyến nghị 1080×1920 hoặc 1080×2400)

| # | Màn hình chụp | Text overlay (ngắn, to, 1 dòng) |
|---|---|---|
| 1 | **Today view** — hero card "Next shift" + countdown | `Your next shift at a glance` |
| 2 | **Month calendar** — grid màu các ca | `See the whole month in one grid` |
| 3 | **Income card** — week income + disclaimer + breakdown | `Estimate your income from your shifts` |
| 4 | **Import review** — roster paste + diff preview | `Import your roster in minutes` |

*Mẹo: chụp từ build debug thật (đúng font/màu), thêm viền gradient xanh đậm `#1E3A5F` + chữ trắng phía trên mỗi khung.*

### Feature Graphic — 1024×500

- **Bố cục:** nền gradient xanh đậm (#1E3A5F → #2C5282), icon app (lịch + mũi tên S) đặt lớn bên trái, tên app **ShiftEase** chữ trắng đậm bên phải, tagline nhỏ: *"Work Shift Calendar & Income Estimator"*. Họa tiết: 3 ô lịch nhỏ mờ (grid pattern) góc phải dưới.
- **Không chứa:** chữ quá nhỏ (<24px khi thu nhỏ), khung của store, lời kêu gọi "Install now" (bị cấm).

### App Icon — 512×512

- Sinh trực tiếp từ icon app hiện có (lịch trắng + mũi tên "shift turn" trên nền xanh tròn vuông #1E3A5F) → `icon.png` 512×512 (đã làm, xem repo `store_assets/icon.png`).
- Yêu cầu Play: PNG 32-bit + alpha, ≤ 1 MB, không bo góc sẵn (store tự bo).

---

## 4. App Content Checklist (Play Console)

- [x] **Privacy Policy** — URL bắt buộc vì có Ads → đã host tại: `https://hoangsoft90.github.io/shift-ease/privacy.html`
- [ ] **Data Safety form** — khai báo: *Data shared = Advertising ID (AdMob), App interactions (Sentry crash reports, no personal data)*; *Data collected = none beyond the above*; *Data encrypted in transit = Yes*; *Users can request deletion = N/A (no account)* — **cần điền tay trên Console**
- [ ] **Ads declaration** — Yes → chọn "Ads" trong App Content
- [ ] **Content rating questionnaire** — trả lời: không violence/gambling/user-generated → kết quả dự kiến **Everyone**
- [ ] **Target audience** — 18+ (không chọn nhóm dưới 13 → tránh politics của Families policy)
- [ ] **App access** — "All functionality available without restrictions" (không login, không gate)
- [ ] **News app declaration** — No
- [ ] **COVID-19 app declaration** — No
- [ ] **Government app declaration** — No
- [ ] **Financial features declaration** — No (estimates are not banking)
- [ ] **Health apps declaration** — No (dù có user y tế, app không xử lý dữ liệu sức khỏe)
- [ ] **Release** — Internal testing ≥ 14 ngày khuyến nghị trước production; sau đó Staged rollout 20% → 50% → 100% (runbook `doc/release/staged_launch.md`)

> ⚠️ Trước khi submit: build **release-signed AAB** (không phải debug APK) bằng keystore thật — xem skill `android-release-signing`.
