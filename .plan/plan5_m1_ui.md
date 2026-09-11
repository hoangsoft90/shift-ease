# ShiftEase — Plan5: Gate M1 (Basic Calendar — UI + Domain Service) — ✅ ĐÃ DUYỆT & IMPLEMENT

Ngày: 2026-09-05 · Trạng thái: **approved (D-UI-1 = A root Flutter · D-UI-3 = không dep · D-UI-4 = scope bảng §1) — code xong, báo cáo result11_gate_m1.txt**
Phạm vi nguồn: plan1_final_v2 §10 (INVARIANT), plan2 §1.1 (5 lớp + dependency rule),
features.md §4 (danh mục màn hình P0), next.md "M1 — Basic Calendar".

---

## 1. Mục tiêu & phạm vi

**Mục tiêu:** 1 luồng người dùng hoàn chỉnh chạy trên UI thật:
tạo job → tạo pattern → xem lịch tuần → sửa 1 ca (override) → render lại đúng
→ thoát/mở lại (persist) → vẫn đúng. (DoD từ next.md)

| Có trong M1 | KHÔNG (gate sau) |
|---|---|
| Chuyển repo thành Flutter app (core giữ nguyên, thuần) | Today screen thu nhập (M3 income) |
| `lib/domain/` service layer cầu repo↔UI | Month view (M1b hoặc M2) |
| Jobs screen: tạo job (tên + timezone) | Add Shift 1-tap template (M1b) |
| Templates screen tối thiểu (name, start, end, color, break) | DST dialog UI (engine đã sẵn; UI = M1b) |
| Pattern Builder: cycle 4-on/4-off, 2-2-3, DuPont + preview + ngày hiệu lực (versioning) | Pay Rules UI + income breakdown (M3) |
| Calendar Week: ca theo local time, chuyển tuần | Import UI (M2) |
| Occurrence Edit: UPDATE giờ / DELETE / REPLACE template (SPLIT/SWAP = P2) | Export/Share (.ics, sharing) (M4) |
| Persist qua SQLite repo hiện có; restart = render lại | CalendarEvent/TimeOff model (backlog) |
| Widget tests + CI job `ui-tests` | Notifications, SQLCipher native, cloud |

SPLIT/SWAP: engine 6/6 ✅ nhưng UI của 2 op này = P2 (features.md B10).
M1 UI chỉ expose UPDATE/DELETE/REPLACE/CREATE (thêm ca lẻ cho ngày OFF) —
đủ để chứng minh override + persistence đúng.

---

## 2. Hiện trạng & khả thi (đã probe — bằng chứng)

| Hạng mục | Kết quả probe |
|---|---|
| Repo hiện tại | Pure Dart package `shiftease`, chỉ `lib/core/*` (time/pattern/money/import/db), 155/155 tests, 6 CI jobs |
| Flutter SDK | `/google/flutter` — Flutter 3.47.1 stable, Dart 3.13.1 (`flutter --version` OK) |
| `flutter test` headless | ✅ widget test chạy được (probe `/tmp/fprobe` → `+1: All tests passed!`) |
| Network pub.dev | ✅ HTTP 200 — có thể thêm dep nếu cần (khuyến nghị M1 KHÔNG thêm dep UI nào) |
| sqlite3 FFI + timezone | Đã là dep của core; timezone picker dùng `tz.getLocation` validate (INVALID_TIMEZONE) |
| CI | GitHub Actions Linux — flutter SDK dep cần thêm setup job `subosito/flutter-action` |

---

## 3. Quyết định nền tảng & cấu trúc (CẦN DUYỆT)

### D-UI-1: Chuyển repo root → Flutter app (khuyến nghị) hay tách `app/` riêng?

**Phương án A (khuyến nghị) — repo root thành Flutter app:**
- `pubspec.yaml`: thêm `flutter: {sdk: flutter}` + dev `flutter_test`; GIỮ NGUYÊN
  sqlite3, timezone, test, lints. Không sinh android/ios/... platform folders ở
  bước này (`flutter test` không cần; chỉ cần khi chạy thiết bị thật).
- `lib/` giữ nguyên `core/`; thêm `main.dart` + `app/` + `domain/` (bên dưới).
- Core tests vẫn chạy `dart test` (không import flutter) — CI jobs core KHÔNG đổi.
- Widget tests chạy `flutter test test/ui/` — job CI mới.
- Rủi ro: package giờ phụ thuộc flutter SDK — mọi lệnh `dart run` cho core vẫn OK
  (chỉ compile thư viện được import).

**Phương án B — `app/` sub-package Flutter, core giữ package pure Dart:**
- Ưu: core repo không đổi pubspec. Nhược: 2 pubspec, CI phải `cd app`, import
  core qua `path:` — churn tooling, file chồng chéo root. Không khuyến nghị.

### D-UI-2: Tổ chức thư mục theo plan2 §1.1 (5 lớp)

`domain/` + `features/` là lớp mới; `data/` hiện đang là `lib/core/db`
(đã được duyệt ở Gate 3 — không move lại, spec ghi nhận = data layer).

```
lib/
  main.dart                     ← khởi động: initializeTimezoneDatabase() + mở DB + runApp
  app/                          ← MaterialApp, routing, theme, DI tối thiểu (constructor inject)
  domain/                       ← service layer (chỉ import core/* + core/db)
    schedule_service.dart       ← toàn bộ use case M1 (dưới)
  features/                     ← màn hình, import domain + core (plan2 rule: features → domain/core/data)
    jobs/         jobs_screen.dart, job_edit_screen.dart
    templates/    template_edit_screen.dart
    pattern_builder/ pattern_builder_screen.dart (cycle + preview + effectiveFrom)
    calendar/     week_calendar_screen.dart (chuyển tuần, local-time, tap ca)
    occurrence/   occurrence_sheet.dart (UPDATE/DELETE/REPLACE/CREATE)
  core/                         ← KHÔNG ĐỤNG (155 tests giữ nguyên)
```

Rule dependency plan2 §1.1: `core/` không import `domain/features/app`;
`domain/` chỉ import `core/` + `core/db`; `features/` import `domain`+`core`;
`app/` là ngoài cùng. Đảm bảo bằng analyzer + test import-graph trong CI.

### D-UI-3: State management — KHÔNG thêm dep (khuyến nghị)

- M1: `StatefulWidget` + service inject qua constructor (không global/singleton
  bí ẩn). Repo sync (sqlite3 đồng bộ) → service method gọi thẳng, không cần
  async/stream cho CRUD; render nặng chạy `compute()`? → KHÔNG, render < vài trăm
  occurrence = ms, chạy sync như tests.
- Lý do: repo tối giản dep (chỉ +flutter sdk), correctness-first; riverpod/bloc
  là quyết định riêng khi app lớn (ghi backlog).

---

## 4. Domain service layer — `lib/domain/schedule_service.dart`

Gói 4 repo (Pattern/Schedule/PayRule/Import) thành use case UI cần. API dự kiến
(danh sách method thật sẽ khớp signature repo hiện có — đã đọc: saveTemplate,
savePattern(+sequence), patternsActiveOn, saveOccurrences, occurrencesInRange,
saveOverride({patternId}), replay/renderJobSchedule, setPayEstimateSnapshot):

```dart
class ScheduleService {
  ScheduleService({required PatternRepository patterns,
                   required ScheduleRepository schedule,
                   required PayRuleRepository payRules});

  // Jobs
  String? ensureJob(String name, String timezone);       // upsert + validate tz
  List<JobRecord> jobs();

  // Templates (per job)
  void saveTemplate(String jobId, ShiftTemplate t);
  List<ShiftTemplate> templates(String jobId);

  // Patterns + preview (KHÔNG lưu khi chỉ preview)
  ScheduleRenderResult previewPattern(ShiftPattern p, DateTimeRange range);
  void savePattern(ShiftPattern p, {required List<ShiftTemplate> templates});

  // Render effective schedule của job trong range (baseline active version + overrides)
  ScheduleRenderResult renderJob(String jobId, DateTimeRange range);

  // Override
  void applyOverride(Override o, {required String patternId});  // saveOverride + re-render
  List<ShiftOccurrence> occurrencesInRange(String jobId, from, to);

  // (M3) pay snapshot — KHÔNG expose UI M1, giữ nguyên INVARIANT-006
}
```

Bất biến domain (rà soát lại từng cái ở UI test):
- Mọi thay đổi ca = ghi **Override**, KHÔNG bao giờ mutate pattern (INVARIANT-001).
- Mọi thay đổi pattern quá khứ/roster = `savePattern` bản mới effectiveFrom
  (versioning D9 — anchor bất biến, engine lo phase).
- Render lại sau override dùng **cùng** ScheduleRepository.renderJobSchedule
  (đã fix P1 chain + CREATE convention v2) — UI không tự render bằng tay.
- Occurrence lưu UTC + timezone gốc (INVARIANT-007) — hiển thị local qua
  timezone của chính occurrence, không phải timezone thiết bị.

---

## 5. Màn hình M1 — từ features.md §4 (P0 subset)

| Màn hình | Nội dung | Ghi chú invariant/NEVER |
|---|---|---|
| **Jobs list + edit** | Tên job, timezone (picker danh sách rút gọn + validate `tz.getLocation`; sai → báo INVALID_TIMEZONE, không tự sửa) | INVARIANT-007 |
| **Templates (per job)** | Tên, code, màu, start/end ("22:00"–"06:00" = overnight qua resolver), break | INVARIANT-005: KHÔNG có ô pay rate trong template |
| **Pattern Builder** | Chọn cycle (4/4, 2-2-3, DuPont — cấu hình sequence + template từng slot; null = OFF), anchor, **preview tuần đầu** (gọi previewPattern — KHÔNG lưu), effectiveFrom | versioning D9; bản cũ không mutate |
| **Calendar Week** | 7 cột theo tuần bắt đầu effectiveFrom/anchor; ca hiển thị **local time của occurrence**; issue (MISSING_TEMPLATE, resolve fail) hiện badge + lý do — KHÔNG silent | resolved-only; "Unable to calculate" hiện lý do |
| **Occurrence tap → sheet** | Xem chi tiết (local giờ, UTC, source); Edit giờ (UPDATE), đổi template (REPLACE), Xóa (DELETE), **Thêm ca ngày OFF (CREATE — patternId bắt buộc, convention v2)** | append-only override; CREATE thiếu patternId = lỗi kỹ thuật, không silent |
| **Restart persistence** | Mở app → mở DB file thật (path `getApplicationSupportDirectory`) → render lại | INVARIANT-008 offline |

Navigation tối thiểu: Jobs → (Templates) → Pattern Builder → Calendar (job active).
Không làm Today/Month/Import trong M1 (tránh phình scope — xem §1 bảng Out).

---

## 6. Test plan

### Widget/UI tests (`test/ui/`) — chạy `flutter test`
Dùng DB `:memory:` (như core/db tests) — không cần file, không fake engine:
1. **DoD end-to-end**: tạo job → template → pattern (4/4, effectiveFrom hôm nay)
   → render tuần hiện ca local đúng → tap ca → UPDATE giờ → re-render đúng
   → "restart" (đóng DB, mở lại cùng file tạm) → ca vẫn đúng (persist).
2. **Override qua UI = Override trong log**: mỗi thao tác sửa ca phát sinh đúng
   1 row `overrides` (operation, payload) — assert append-only.
3. **INVARIANT-001 qua UI**: sửa ca #N → pattern KHÔNG đổi (so pattern trước/sau).
4. **CREATE ngày OFF**: thêm ca Thứ Ba (pattern Mon/Wed/Fri) → sống qua re-render
   + sub-range (regression P1 §7d trước đây).
5. **Issue surface**: pattern thiếu template → lịch hiện badge "thiếu template"
   + lý do (không hiển thị ca ma).
6. **Jobs isolation**: 2 job 2 timezone → calendar job A không lẫn ca job B.

### Unit (domain layer, pure `dart test`)
`test/domain/schedule_service_test.dart` — service gói repo đúng method, không
đi đường tắt (VD: applyOverride phải đi saveOverride → renderJobSchedule).

### Import-graph guard
CI job mới chạy script kiểm tra: `core/` files không import `domain/|features/|app/`
(grep import) — plan2 §1.1 dependency rule thành automated check.

### CI (`.github/workflows/test.yml`)
- Thêm job `ui-tests`: `subosito/flutter-action` (channel stable, 3.47.x) →
  `flutter test test/ui/ test/domain/` — riêng khỏi core jobs (flutter SDK chỉ
  cần ở job này).
- Các job core hiện tại giữ `dart test` — KHÔNG đổi (đã chứng minh: core không
  import flutter, vẫn chạy `dart test` sau khi pubspec thêm flutter sdk).

---

## 7. Definition of Done (M1)

1. `dart analyze` clean + `dart test test/core/` = **155/155 giữ nguyên** (core KHÔNG đụng).
2. `flutter test` UI + domain tests pass trên CI job `ui-tests`.
3. DoD luồng user (§1) chạy được trong widget test **end-to-end** với DB file thật
   (không fake engine/repo), restart chứng minh persist.
4. Import-graph guard xanh (core không import UI).
5. Báo cáo `result11_gate_m1.txt`: file thật trên đĩa (`ls`), dòng code chính,
   log test đầy đủ — theo nguyên tắc bằng chứng đã cam kết.

---

## 8. Out of scope (ghi backlog — không làm trong M1)

Today/month/income UI · Import UI (M2) · DST dialog UI hoàn chỉnh (engine sẵn) ·
Quick Add 1-tap · Pay Rule editor/template library picker (M3) · SPLIT/SWAP UI (P2) ·
.ics/notifications/cloud (M4+) · CalendarEvent subtypes (backlog Gate 3) ·
SQLCipher native verify · State mgmt framework (riverpod/bloc — chọn khi app lớn).

---

## 9. Quyết định cần duyệt

| # | Quyết định | Khuyến nghị |
|---|---|---|
| **D-UI-1** | Cấu trúc repo: root → Flutter app (A) vs `app/` sub-package (B) | **A** |
| **D-UI-2** | Tổ chức theo plan2 §1.1: thêm `lib/domain` + `lib/features` (data = core/db giữ nguyên) | **Đúng plan2** |
| **D-UI-3** | State mgmt M1: **không thêm dep** (StatefulWidget + inject) | **Không dep** |
| **D-UI-4** | Phạm vi màn hình M1: đúng bảng §1 (bỏ Today/Month/QuickAdd/DST dialog ra M1b) | **Đúng bảng §1** |
| **D-UI-5** | CI: job `ui-tests` dùng flutter-action; core jobs giữ `dart test` | **Đúng** |

Sau khi duyệt: thực thi theo thứ tự task (như plan3_final_v2 cách làm):
T1 pubspec+main+app shell → T2 domain service → T3 Jobs/Templates → T4 Pattern
Builder → T5 Calendar Week → T6 Occurrence edit → T7 UI tests DoD → T8 CI + báo cáo.
Mỗi task PASS chỉ khi có dòng code + test xanh.
