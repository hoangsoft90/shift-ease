# ShiftEase — Danh mục tính năng (App + UI) — REV 2026-09-11

> Cập nhật: 2026-09-11 — viết lại theo **trạng thái code thật trên disk** (RC complete: app shell, engines, import, pay, encryption, ads, Sentry, CI).
> Mọi mục ✅ đều có file/thẩm chứng trên disk + test backing (328/328 pass tại thời điểm ghi).
> Ký hiệu: ✅ Đã implement (có test) · 🟡 Implement một phần · ⏳ Chưa implement (backlog)

---

## 1. Tổng quan sản phẩm

| Mục | Giá trị |
|---|---|
| Định vị | **Personal Operating System for Shift Workers** — 3 trụ cột: Work – Life – Money |
| Target persona | Nurse/Healthcare 25–45, Mỹ/Anh/Đức, ca xoay 3 kíp, đa nguồn thu nhập, có gia đình |
| 3 trục differentiation | (1) Nhập liệu nhanh, (2) Correctness Contract (tính đúng), (3) UX đơn giản |
| Monetization | **AdMob banner + interstitial + app open** đã tích hợp (`test_ads=true` — chỉ Google test ads, chưa live) + kế hoạch Free/Pro Lifetime $39.99 (chưa implement) |
| Platform | Android (targetSdk 36, minSdk 24) + iOS; offline-first, local-only |
| Trạng thái build | RC 1.0.0+1 · CI 2 workflows (ShiftEase CI 8 jobs + Build Debug APK) · github.com/hoangsoft90/shift-ease |

### Correctness Contract (áp dụng mọi module)

> Cùng input hợp lệ + cùng timezone DB version + cùng pay rule version → kết quả **deterministic**.
> Thiếu input/rule → KHÔNG đoán: báo **"Unable to calculate accurately"** kèm lý do (`unavailable` trong income, dialog DST, recovery screen).
> Triết lý: *"Không biết" tốt hơn "tính sai"*. Mọi số tiền kèm nhãn **"Ước tính — không phải bảng lương chính thức"**.

---

## 2. Tính năng đã implement

### A. Time Engine — thời gian/DST (`lib/core/time/`, ✅)

| # | Tính năng | Chi tiết |
|---|---|---|
| A1 | Civil Time Architecture | Local Civil Time (recurrence/UI) ↔ UTC instant (sort/reminder) ↔ elapsed duration (pay) — tách bạch 3 khái niệm |
| A2 | Resolve local→UTC | Overnight (`endHour < startHour`) tự hiểu là sang ngày hôm sau; timezone per-job (validate qua `validateTimezone`) |
| A3 | Duration từ UTC (INV-002) | Ca bắc DST spring-forward = 7h, fall-back = 9h — không trừ giờ local |
| A4/A5 | DST non-existent / ambiguous | Không tự quyết: `NONEXISTENT_LOCAL_TIME` / `AMBIGUOUS_LOCAL_TIME` + 2 candidates → UI dialog (`dst_resolution_dialog.dart`, `DstCandidate`/`DstResolutionOutcome`) |
| A6 | Ambiguous end-time | Xử lý y hệt start (không auto-select) |
| A7 | Timezone retention (INV-007) | Đổi timezone thiết bị không đổi giờ ca đã lưu |
| A8 | Recurrence theo local time (INV-003) | Ca 22:00 xuyên đêm DST không lệch giờ hiển thị |
| A9 | Timezone database | `initializeTimezoneDatabase()` chạy trước mọi resolve (tz data đóng gói trong app) |

### B. Pattern → Occurrence → Override (`lib/core/pattern/`, ✅)

| # | Tính năng | Chi tiết |
|---|---|---|
| B1 | Shift Template | Time/UI only: tên/mã/màu/start/end/break — **KHÔNG pay** (INV-005); overnight = end < start |
| B2 | Shift Pattern | `FIXED_CYCLE` (4-on/4-off, 2-2-3, DuPont, sequence tự khai, `null` = OFF); pattern builder có **preview 14 ngày đầu** trước khi lưu |
| B3 | Project occurrences | Sinh baseline theo date range; template thiếu → lỗi `MISSING_TEMPLATE` (không silent skip) |
| B4 | Roster re-versioning (D1) | "Đổi roster từ ngày X" = `changeRosterFrom` **atomic transaction**: đóng pattern cũ (`effectiveUntil`), tạo bản mới (`effectiveFrom`), ca cũ giữ nguyên |
| B5 | Override — 6 operations (D2) | CREATE / UPDATE / DELETE / REPLACE / SPLIT / SWAP — mỗi mutation ghi **1 Override** vào append-only log (`override_actions.dart` → `applyOverride`) |
| B6 | Effective Schedule | Baseline + overrides render runtime; `source: baseline/override/created` |
| B7 | Override isolation (INV-001) | Sửa ca #N không đụng pattern hay ca #N+1 (property test bảo vệ) |
| B8 | Override reason | SWAP / OVERTIME / LEAVE / CUSTOM |

### C. Pay / Money (`lib/core/money/` + `lib/features/pay/` + `lib/features/income/`, ✅)

| # | Tính năng | Chi tiết |
|---|---|---|
| C1 | PayRule versioned (D6) | Base rate + differentials + OT rules theo job, effectiveFrom/Until |
| C2 | PayBreakdown — Cách B | Regular + Differentials + Overtime tách bạch, không double-count |
| C3 | Differentials pluggable | NIGHT/WEEKEND/HOLIDAY/HAZARD/CALLBACK/CUSTOM; PERCENT/FLAT; window hoặc all-shift |
| C4 | OT multi-rule | SHIFT/DAY/WEEK threshold + multiplier; nhiều rule → **max()**, không cộng dồn |
| C5 | Weekly OT LIFO | Tuần vượt ngưỡng → OT gán ca cuối theo thời gian, tràn ngược nếu thiếu |
| C6 | Snapshot (INV-006) | Earnings lịch sử là snapshot bất biến; rule mới không rewrite cũ |
| C7 | PayRule template library | US-CA/US-NY/US-TX/UK NHS/DE (`payrule_templates.dart`) + **presets UI** (preset = điểm bắt đầu, prefill editor; save tường minh) |
| C8 | Income estimate + breakdown UI | `estimateIncome` theo This week/This month/custom; thiếu rule → trạng thái **`unavailable`** rõ ràng (C10); màn breakdown full-screen (`income_breakdown_screen.dart`) + thu nhập trên Today |
| C9 | Disclaimer bắt buộc | Mọi số tiền: "Ước tính — không phải bảng lương chính thức" (test bảo vệ) |

### D. Calendar & màn hình chính (`lib/features/calendar|today|occurrence/`, ✅)

| # | Tính năng | Chi tiết |
|---|---|---|
| D1 | Today screen | Ca đang diễn ra/ca tiếp theo + countdown, **khoảng nghỉ trước ca sau**, tổng giờ làm tuần (Mon–Sun từ UTC), thu nhập hôm nay/tuần; auto-refresh khi app resume (`WidgetsBindingObserver`) |
| D2 | Month calendar | Lưới 6×7 cố định; mỗi cell: số ca + tối đa 2 giờ bắt đầu (local); tap ngày → quick add / occurrence sheet |
| D3 | Week calendar | Tuần Mon–Sun, default tuần chứa ngày tap; hiển thị ca theo local time |
| D4 | Quick Add 1-tap | Bottom sheet theo ngày: mỗi template 1 tile = tạo ca với giờ mặc định; "Custom time…" mở form đầy đủ |
| D5 | Occurrence sheet | View/edit ca; CREATE trên ngày OFF; delete với confirm; DST dialog khi chạm giờ lạ; mọi thay đổi = 1 Override |
| D6 | Multi-job | Mỗi job: templates + patterns + PayRule + **timezone riêng**; tạo/xoá job từ Jobs screen |
| D7 | Offline-first (INV-008) | Toàn bộ core chạy local 100%, không cloud/account/network bắt buộc (Sentry + AdMob là 2 ngoại lệ opt-in, xem G) |

### E. Import pipeline (`lib/core/import/` + `lib/features/import/`, ✅)

| # | Tính năng | Chi tiết |
|---|---|---|
| E1 | Smart Paste | Paste text tự do → parse + heuristics → candidates |
| E2 | CSV import (RC §C1) | Paste CSV → preview cột (header + auto-detect) → map cột → parse |
| E3 | Confidence scoring | HIGH/MEDIUM/LOW theo date format/time format/template match |
| E4 | Review UI bắt buộc (INV-004) | Mỗi candidate Accept/Edit/Reject; bulk "Accept All High"; **không auto-commit** |
| E5 | State machine | `IDLE → EXTRACTED → REVIEWING → COMMITTED`; commit tường minh qua dialog "Commit now?"; `commitImport` từ chối EXTRACTED→COMMITTED thiếu review; commit session+occurrences **1 transaction** |
| E6 | Re-import diff (RC §C2) | Preview what-changes vs committed roster hiện tại: Added/Removed/Modified + impact giờ/thu nhập trước khi commit |
| E7 | ImportSession audit | Raw text + candidates + committed IDs lưu DB → truy vết nguồn gốc ca |

### F. Data, bảo mật & khôi phục (`lib/core/db/`, `lib/features/security/`, ✅)

| # | Tính năng | Chi tiết |
|---|---|---|
| F1 | SQLCipher encryption (P7.2) | DB mã hoá thật (SQLCipher 4.18.0 qua build hook `source: sqlcipher`); opener **fail-closed** — không key không mở, không plain fallback; `tool/cipher_proof.dart` chứng minh trong CI |
| F2 | Master key | Sinh lần đầu, lưu Android Keystore (EncryptedSharedPreferences) / iOS Keychain (`SecureSecretStore`); key không vào log/backup |
| F3 | Recovery screen phân loại | Lỗi được phân đúng loại: filesystem (storage problem — KHÔNG bảo mất key) / secure storage / cipher (wrong key) / unexpected — mỗi loại có hướng dẫn riêng (`lib/main.dart` `_LockedApp`) |
| F4 | DB path đúng mobile (P0 fix) | Mobile = `getApplicationSupportDirectory()` qua path_provider (KHÔNG BAO GIỜ `HOME ?? '.'` — bug errno 30 đã sửa, 7 test bảo vệ); desktop = `$HOME/.shiftease`; `SHIFTEASE_DB` override |
| F5 | Schema v3 + migration | Version boundary có test (6-op replay); schema version hiển thị trong Settings |
| F6 | Backup | Full-data JSON (schema + checksum) vào app-support dir; Settings → Backup |
| F7 | Restore | Validate → preview → confirm → restore; corrupt/checksum sai bị từ chối; restore trên DB mã hoá (encrypted round-trip test) |
| F8 | Delete all data | Xoá DB + local data, confirm 2 lần ("Are you absolutely sure?"); gỡ app = Keystore entry xoá theo → DB không đọc lại được |
| F9 | Write error boundary | Mọi write path (override/import/pay/backup/ICS) qua `runWrite` — exception thành message user, không crash, data rollback (INV-008 an toàn) |
| F10 | Append-only integrity | Override log append-only; audit adversarial test (rc_adversarial_test.dart) |

### G. Platform & dịch vụ (`lib/features/notifications|export|ads/`, ✅)

| # | Tính năng | Chi tiết |
|---|---|---|
| G1 | Shift reminder | Local notification trước ca (default lead 60 phút, cấu hình được); skip ca đã trong lead window; 1 notification id fixed → reschedule thay thế; auto-reschedule khi app resume; Android 13+ xin `POST_NOTIFICATIONS` runtime; inexact allow-while-idle (không cần quyền special) |
| G2 | ICS export | Per-job từ job screen; VEVENT chuẩn (UID + SUMMARY), file JSON/ICS nằm app-support dir (không UI share — ghi rõ trong privacy) |
| G3 | Sentry crash reporting | `sentry_flutter ^9.28`, DSN config, **error-only: PII off, traces off**; wrap toàn app (cả lỗi async trong bootstrap) |
| G4 | AdMob (banner + interstitial + app open) | `google_mobile_ads ^9.1.0`; banner pin đáy app shell (mọi màn), self-hiding khi disable/chưa load; **App Open** hiện khi cold start (sau MobileAds init + consent); **Interstitial** hiện sau import commit thành công; Rewarded chưa có placement; **UMP consent trước init** (EEA/UK); mọi ad call guard — ads không bao giờ làm app lỗi; **`admob.test_ads: true`** = chỉ Google test unit IDs (tránh LIMIT); production placeholder ⇒ format đó tự tắt (không fallback test ID) |
| G5 | App icon | Custom icon (tool/make_icon.py): Android mọi density + adaptive (bg `#1E3A5F`) + full iOS AppIcon set |
| G6 | Cleartext HTTP | `usesCleartextTraffic=true` + `INTERNET` (yêu cầu tường minh của owner; consumer: Sentry + AdMob) |

### H. Chất lượng & CI (✅)

| # | Mục | Chi tiết |
|---|---|---|
| H1 | Test suite | **328/328 pass** (time/pattern/money/import/db/domain/ui/features/ads + property + integration + golden JSON time/money/import) |
| H2 | CI | `ShiftEase CI` 8 jobs (analysis + dependency rule + per-engine + golden cross-check Node + persistence SQLCipher proof + full suite gate) · `Build Debug APK` (artifact `shiftease-debug-apk`, debug-signed, gradle trực tiếp) |
| H3 | Static rule | `lib/core` không import domain/features/app; `lib/domain` không import features/app (CI enforce) |
| H4 | Build | compileSdk/targetSdk **36** (Play 31/8/2026), minSdk 24, JDK 17 + Gradle 9.3.1 + AGP 9.1.0 + Kotlin 2.4.0, desugaring 2.1.4 |
| H5 | Honesty docs | `doc/release/privacy.md` (audit basis: Sentry + AdMob, checklist trước khi live ads), `monitoring.md`, `final_release_gate.md` — device/store legs ghi NOT RUN trung thực |

---

## 3. Danh mục màn hình UI (đã implement)

| Màn hình | File | Nội dung thật trên màn hình |
|---|---|---|
| **Jobs (home)** | `features/jobs/jobs_screen.dart` | AppBar "ShiftEase — Jobs" + icon Settings; danh sách job (tên, timezone); FAB "+ New job" (dialog tên job); tap job → Job Detail |
| **Job Detail** | `features/jobs/job_detail_screen.dart` | Sections: Shift Templates (thêm/sửa qua `TemplateEditDialog`: tên, mã, màu, start/end, break — không có field pay), Shift Patterns (danh sách + FAB "New pattern"), Pay rule (nếu pay engine bật), action **ICS export**; nút mở Week Calendar + Pattern Builder |
| **Today** | `features/today/today_screen.dart` | AppBar "Today"; card ca hiện tại/tiếp theo + mô tả (countdown tới giờ bắt đầu); card nghỉ giữa ca; tổng giờ làm tuần; thu nhập hôm nay/tuần (tap → Income breakdown); empty states "No jobs yet — create one first." / "No shifts coming up in the next 7 days." |
| **Month Calendar** | `features/calendar/month_calendar_screen.dart` | Lưới tháng 6×7; cell = số ca + ≤2 giờ bắt đầu local; tap ngày → Quick Add (ngày trống) / Occurrence sheet (có ca) |
| **Week Calendar** | `features/calendar/week_calendar_screen.dart` | Tuần Mon–Sun, mở mặc định ở tuần chứa ngày được tap từ Job Detail |
| **Quick Add sheet** | `features/calendar/quick_add_sheet.dart` | Bottom sheet theo ngày: "One tap = shift with the template's default times." — 1 tile/template + "Custom time…" |
| **Occurrence sheet** | `features/occurrence/occurrence_sheet.dart` | Xem/sửa ca: giờ, template (REPLACE), delete (confirm); CREATE trên ngày OFF; DST dialog khi cần; mọi action = 1 Override qua write guard |
| **Pattern Builder** | `features/pattern_builder/pattern_builder_screen.dart` | Chọn preset cycle + khai báo sequence (OFF = ô trống); nút **Preview** (dialog "Preview — first 14 days"); Save (disable nếu job chưa có template) |
| **Import** | `features/import/import_screen.dart` | "Import roster · <job>" — 2 mode: Paste text / CSV (preview cột + map); parse → danh sách candidate (confidence) Accept/Edit/Reject + bulk; **diff card** Added/Removed/Modified trước commit; dialog "Commit now?"; lỗi parse hiện rõ |
| **Income Breakdown** | `features/income/income_breakdown_screen.dart` | "Income · <job>" — chip This week / This month / Custom range; breakdown base + differential + OT + tổng; trạng thái unavailable kèm lý do; disclaimer "Ước tính — không phải bảng lương chính thức" |
| **Pay rule dialog** | `features/pay/pay_rule_edit_dialog.dart` + `pay_presets.dart` | "Pay rule (estimate)" — chọn preset làm điểm bắt đầu (prefill), sửa base rate/differentials/OT, save tường minh |
| **Template dialog** | `features/templates/template_edit_dialog.dart` | "New shift template" / sửa: name, code, color, start "HH:mm", end, break phút; overnight = end < start |
| **DST dialog** | `features/common/dst_resolution_dialog.dart` | Giờ không tồn tại/bị lặp: giải thích + chọn candidate (không auto-guess) |
| **Settings** | `features/settings/settings_screen.dart` | Rows: Schema version · Timezone · Permission status (notifications) · Backup (Full-data JSON) · Restore (Choose file → "Restore this backup?") · ICS export (ghi chú per job) · Delete all data (2 confirm) · Encryption status ("Encrypted (key verified)." hoặc lý do) · Data collection · About "ShiftEase — Offline shift calendar — release candidate" · Privacy Policy · Terms |
| **Recovery screen** | `lib/main.dart` `_LockedApp` | Khi mở DB thất bại — tiêu đề theo loại lỗi ("storage problem"/"locked"/"unexpected error"), summary + guidance riêng từng loại, technical detail; KHÔNG claim mất data |
| **Ad banner** | `features/ads/ad_banner_widget.dart` | Banner 50dp pin đáy app shell (mọi màn); ẩn khi test-off/chưa load/fail; đồng thời export singletons `appOpenAds`/`interstitialAds` |
| **App Open / Interstitial** | `features/ads/ad_service.dart` | App Open: cold start; Interstitial: sau import commit; cả 2 không chặn luồng chính khi fail |

Điều hướng: plain `Navigator.push` (không lib điều hướng); injection qua constructor (không service locator). Danh sách này khớp "Danh mục màn hình" spec plan1 — khác duy nhất: **Availability Finder / Sharing screens** chưa implement (backlog §5).

---

## 4. Luồng quan trọng (đã implement)

1. **Khởi động fail-closed** — Sentry init → key từ Keystore/Keychain → `resolveDbPath` (app-support trên mobile) → open DB bằng key (defaultOpener chứng minh SQLCipher) → composeService; failure bất kỳ bước → recovery screen phân loại. Không bao giờ mở DB không key.
2. **Thêm ca qua DST** — giờ lạ → dialog chọn diễn giải → resolve UTC → Override CREATE.
3. **Sửa ca (Override)** — edit → 1 Override append-only → render lại; pattern không mutate (INV-001); mọi exception qua write guard thành message.
4. **Đổi roster từ ngày X** — `changeRosterFrom` 1 transaction: đóng pattern cũ + tạo bản mới; ca trước X nguyên vẹn.
5. **Import roster** — paste/CSV → parse → review bắt buộc → diff preview → "Commit now?" → commit atomic; audit session lưu DB.
6. **Tính thu nhập** — active PayRule theo ngày → duration từ UTC → regular + differentials + OT (max/LIFO) → `estimateIncome`; thiếu rule → unavailable + lý do.
7. **Backup/Restore** — export JSON checksum → validate → preview → confirm → restore (reject corrupt; encrypted round-trip).
8. **Reminder lifecycle** — schedule cho ca tiếp theo (lead 60') → reschedule + cancel-stale mỗi lần app resume; permission runtime Android 13+.

---

## 5. Invariants được bảo vệ (có test)

| # | Invariant | Nơi bảo vệ |
|---|---|---|
| INV-001 | Sửa occurrence không mutate pattern | pattern property test |
| INV-002 | Duration chỉ từ resolved UTC instants | time tests |
| INV-003 | Recurrence theo local civil time | time tests |
| INV-004 | Import không commit khi chưa user review | import engine + UI tests |
| INV-005 | Template không chứa pay semantics | pattern/money tests |
| INV-006 | Earnings lịch sử = snapshot bất biến | money tests |
| INV-007 | Occurrence giữ timezone gốc | time tests |
| INV-008 | Core calendar offline hoàn toàn | thiết kế + ads/sentry guard test |

---

## 6. CHƯA implement (backlog — trung thực, không claim)

| Nhóm | Mục | Ghi chú |
|---|---|---|
| Import mở rộng | OCR/PDF import (M4.5 → M5) | **Gate**: cần spike 20–30 roster thật, threshold ≥70% dates / ≥60% shift types (plan11); spec sẵn |
| Import mở rộng | Pattern auto-detection | P1/P2 spec |
| Sự kiện ngoài ca | TimeOff / PersonalEvent / AvailabilityBlock / Availability Finder | Spec F1–F5; chưa code |
| Sharing | Granular sharing (FULL/BUSY_ONLY/RECOVERY), share link, partner overlay, webcal | Spec G1–G7; chưa code (offline-first hiện tại) |
| Monetization | Live AdMob (production IDs, cả 3 format) — đang `test_ads=true` | Checklist trong `doc/release/privacy.md` §ads; IAP/Pro Lifetime $39.99 chưa code |
| Cloud | Cloud backup E2E / account | Chưa code (local-only) |
| Platform | Home-screen widgets; UI share/file-picker cho backup & ICS; localization (hiện UI tiếng Anh) | Chưa code |
| Release ops | Signed AAB/App Store submission, closed testing | Human legs — BLOCKED theo `result_p9_launch.md` |

---

## 7. Trạng thái verify tại thời điểm ghi (2026-09-11)

- `flutter analyze --no-pub --fatal-infos` → **No issues found**
- `flutter test test/` → **328/328 pass**
- `dart run tool/cipher_proof.dart` → **SQLCipher 4.18.0 community**
- CI: ShiftEase CI (8 jobs) + Build Debug APK — đã green-run trên github.com/hoangsoft90/shift-ease
- App label `ShiftEase` (Android + iOS), version `1.0.0+1`, ids `com.shiftease.shiftease`
