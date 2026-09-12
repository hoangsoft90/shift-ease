# P8.3 / P8.4 — Release Build Notes (Android signed AAB / iOS archive)

> Nguồn: `phases/P8_release_preparation.md` §3–§4 · `plan_p8.md` §P8.3/P8.4.
> **Trạng thái ký/CI: DONE (2026-09-12)** — keystore release cố định đã tạo, 4 GitHub
> Actions secrets đã set, workflow `build-release-aab.yml` build + **verify chữ ký
> release** trước khi upload artifact. **Trạng thái verify trên máy thật: vẫn NOT RUN**
> (persistently 15 rows ở §1.3 — cần thiết bị thật; agent không tự PASS giả).

## Part 1 — Android (P8.3)

### 1.1 Điều kiện

- [x] Keystore release — **đã tạo 2026-09-12, KHÔNG commit vào repo** (nằm trong
      GitHub Actions secrets). Alias `shiftease`, PKCS12, RSA 2048, hạn dùng
      2054 (Play yêu cầu key còn hạn ít nhất tới 2033-10-22).
      Cert SHA-256 (dùng để đối chiếu Play App Signing):
      `A9:FF:7F:7C:47:A5:A4:9F:FA:A1:48:75:00:2A:D3:F2:13:DE:B0:48:42:4D:3A:E0:EB:ED:1A:0D:EA:DD:ED:18`
- [x] Secrets trong CI: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (đã set trên repo;
      `key.properties` được workflow sinh ra trong runner, local vẫn gitignored)
- [x] CI có Flutter + JDK 17 (2 workflow release: APK + AAB)

> ⚠️ **KHÔNG tạo lại keystore.** Đổi key = đổi upload key → Play từ chối mọi
> version sau đó ("signed in debug mode" / key mismatch). Backup `.jks` + mật khẩu
> ra ngoài máy (password manager / USB) trước khi publish lần đầu.

### 1.2 Lệnh build (thực thi bởi human/CI — không chạy trong sandbox)

> ✅ **Signing đã implement (2026-09-12)** trong `android/app/build.gradle.kts`:
> `signingConfigs.release` được khai báo **chỉ khi** `android/key.properties`
> tồn tại (gitignored — `android/.gitignore` đã có rule `key.properties`,
> `*.keystore`, `*.jks`), đọc `storeFile`/`storePassword`/`keyAlias`/
> `keyPassword`; `storeFile` resolve tương đối `android/`. Không có file này →
> release build rơi về debug signing để QA vẫn cài được (Play sẽ từ chối
> "signed in debug mode" — phải có keystore thật khi build AAB).
>
> **Ads switch (2 nửa phải bật/tắt cùng nhau):**
> - `--android-project-arg=enableAds=false` → Gradle blank
>   `manifestPlaceholders["adsAppId"]`, APK không chứa AdMob APPLICATION_ID.
> - `--dart-define=ENABLE_ADS=false` → `AppAdsConfig.enableAds=false`, Dart
>   không bao giờ gọi `MobileAds.initialize()`.
> Test ads: `--dart-define=TEST_ADS=true` để dùng Google test units;
> `false` (mặc định của workflow release) = ads thật, unit ID production.
>
> ⚠️ **Bug polarity đã sửa (2026-09-12).** Bản đầu của cờ này viết
> `...equals("false")` nên gán `enableAds = true` **đúng lúc** đang tắt ads:
> `-PenableAds=false` vẫn ship APPLICATION_ID production, còn build KHÔNG
> truyền `-P` (debug APK) lại ship app ID **rỗng** — ads không bao giờ load mà
> không crash, rất khó phát hiện. Cờ giờ đọc: ads BẬT trừ khi property là đúng
> chuỗi `false`.
>
> Lý do bug lọt qua được: check cũ dùng `strings | grep` trên AXML — string pool
> của manifest APK là **UTF-16**, nên `strings` không thấy ID và báo "OK" giả.
> Giờ cả 3 workflow verify bằng `tool/check_manifest_ads.py` (đọc entry đúng của
> APK/AAB, dò cả UTF-8/UTF-16LE/BE, assert `--expect=present|absent` theo cờ) →
> property bị đọc sai sẽ fail ngay ở cả hai chiều.
>
> Workflow `build-release-apk.yml` (APK) và `build-release-aab.yml` (AAB) truyền
> cả hai (input `enable_ads`, `test_ads` trên workflow_dispatch).
>
> **AAB cho Play:** workflow `build-release-aab.yml` chạy khi push lên `main`
> (và có thể dispatch tay): decode keystore từ secrets → `flutter build
> appbundle --release` → **verify chữ ký bằng `jarsigner`/`keytool`** và
> **fail CI** nếu AAB là debug-signed hoặc signer không phải `CN=ShiftEase`.
> Artifact: `shiftease-release-aab` → upload trực tiếp lên Play Console
> (Play App Signing nên bật; keystore này là **upload key**).
> Nhớ bump `version:` trong `pubspec.yaml` trước mỗi lần upload — Play từ chối
> versionCode trùng.

> ℹ️ **Mặc định (2026-09-12): `enable_ads=true` + `test_ads=false`** cho cả APK
> lẫn AAB release — tức bản release phục vụ **ads thật** (đúng cấu hình sẽ lên
> store). Muốn bản không quảng cáo: dispatch `enable_ads=false`; muốn ads test:
> dispatch `test_ads=true`. Debug APK (`build-debug-apk.yml`) giữ
> `test_ads=true` (Dart default) — chỉ xem ads test, không tốn inventory thật.
> Debug APK verify riêng rằng manifest **có** APPLICATION_ID production.

```bash
# AAB — artifact nộp Play (cần android/key.properties + keystore thật)
flutter build appbundle --release

# Release APK cho QA, ads TẮT (chỉ Dart). Manifest VẪN giữ APPLICATION_ID hợp lệ.
# KHÔNG bao giờ blank app ID: đó không phải "tắt ads" mà là crash mọi lần mở app
# (MobileAdsInitProvider: "Invalid application ID", verify trên pixel thật 2026-09-12).
flutter build apk --release --dart-define=ENABLE_ADS=false

# Release APK có ads thật (chỉ khi unit ID production đã điền trong ads_config.dart)
flutter build apk --release --dart-define=TEST_ADS=false
```

- Version tự lấy từ `pubspec.yaml` (`1.0.0+1` → versionName 1.0.0, versionCode 1) — không hard-code khác trong gradle.
- Build type `release` phải không có debug flag (đã audit: `lib/` không có kDebugMode/mock/endpoint).
- Manifest **luôn** mang `APPLICATION_ID` hợp lệ — `adsAppId` là hằng số trong
  `build.gradle.kts`, không còn nhánh `enableAds`. Cờ `enable_ads` chỉ còn ở Dart
  (`--dart-define=ENABLE_ADS`).
- R8 **bật** cho release (Flutter plugin set `minifyEnabled = true`; debug không
  minify). Keep rule release nằm ở `android/app/proguard-rules.pro` và được CI
  assert bằng `tool/check_r8_keep.py` — xem §1.6.
- **Build bằng `flutter build apk`, KHÔNG chạy `./gradlew` trực tiếp**: repo không
  commit Gradle wrapper (`android/.gitignore`) — flutter_tools inject wrapper đã pin
  (Gradle 9.3.1) từ cache của nó.

### 1.3 Verify sau build (mỗi dòng PASS/FAIL/NOT RUN — human)

| # | Hạng mục | Trạng thái |
|---|---|---|
| 1 | Install AAB (bundletool) / APK lên máy thật | NOT RUN |
| 2 | Launch, không crash | NOT RUN |
| 3 | Fresh install — DB mới tạo, mã hoá (SQLCipher mở bằng key mới) | NOT RUN |
| 4 | Upgrade from previous RC — theo `doc/release/upgrade_test_plan.md` | NOT RUN |
| 5 | Database opens; encrypted path opens (`verifyEncryption` = encrypted trong Settings) | NOT RUN |
| 6 | Notification permission flow (Android 13+ prompt) | NOT RUN |
| 7 | Backup/restore round-trip | NOT RUN |
| 8 | No debug UI / no debug logging (build release) | NOT RUN |
| 9 | Signature verify: `apksigner verify --print-certs` (hoặc Play Console chấp nhận — không bị từ chối "debug-signed") | NOT RUN |
| 10 | Cold start bản release (R8 minify ON): install → mở app → không crash trong `androidx.startup`; `tool/check_r8_keep.py` PASS (§1.6) | NOT RUN |
| 11 | Ads disabled (`ENABLE_ADS=false`): không request ad nào, app vẫn mở được, manifest vẫn có APPLICATION_ID hợp lệ | NOT RUN |

### 1.4 Status

**BLOCKED — needs signing keys.** Không có keystore trong repo/sandbox; debug-APK pipeline (`build-debug-apk.yml`) là artifact QA, không thay thế signed release.

## Part 2 — iOS (P8.4)

### 2.1 Điều kiện

- [ ] Apple Developer account + distribution certificate + provisioning profile (App Store)
- [ ] macOS với Xcode (sandbox không có — cả build lẫn code signing)
- [ ] Bundle ID `com.shiftease.shiftease` đã đăng ký

### 2.2 Lệnh build (human)

```bash
flutter build ipa --release
# hoặc: open ios/Runner.xcworkspace → Product → Archive → Distribute
```

### 2.3 Verify sau build (human)

| # | Hạng mục | Trạng thái |
|---|---|---|
| 1 | Archive signed thành công | NOT RUN |
| 2 | Install (TestFlight/dev device) — launch, không crash | NOT RUN |
| 3 | Fresh install — DB encrypted, key trong Keychain | NOT RUN |
| 4 | Upgrade from previous build | NOT RUN |
| 5 | Keychain: key đọc lại được sau kill/reboot | NOT RUN |
| 6 | Notification permission + local reminder | NOT RUN |
| 7 | Backup/restore | NOT RUN |
| 8 | No debug UI / no development configuration | NOT RUN |

### 2.4 Status

**BLOCKED — needs certs/profiles + macOS.** Không PASS giả.

## Never (cả hai nền tảng)

- NEVER commit keystore/cert/password vào git
- NEVER PASS "signed release" chỉ vì debug build chạy được
- NEVER đổi signing config để "cho qua" — sai signing là lỗi phải sửa đúng cách

## 1.5 Ads-off build (`enable_ads=false`) — Dart-side switch ONLY

> Không phải UI option. Dùng cho bản release tạm không quảng cáo (QA/reviewer)
> mà không sửa code Dart.

Chuỗi hoạt động:
1. Workflow truyền `--dart-define=ENABLE_ADS=false` (hoặc dispatch input
   `enable_ads=false`).
2. `lib/config/ads_config.dart` → `AppAdsConfig.enableAds=false` → `main.dart`
   **không** gọi `initializeAds()` → không request ad nào.
3. Manifest **vẫn** chứa `com.google.android.gms.ads.APPLICATION_ID` hợp lệ
   (`adsAppId` là hằng số trong `android/app/build.gradle.kts`).

**CẤM blank app ID.** Bản trước đây set `adsAppId=""` khi tắt ads với giả định
"SDK tự tắt" — SAI. SDK validate app ID trong ContentProvider của chính nó,
**trước** Dart, và giết process:

```
java.lang.RuntimeException: Unable to get provider
  com.google.android.gms.ads.MobileAdsInitProvider:
java.lang.IllegalStateException: * Invalid application ID. *
```

(verify trên Pixel 3a / Android 12 thật, 2026-09-12). CI chặn hẳn loại này bằng
`tool/check_manifest_ads.py` — script parse **giá trị attribute thật** của AXML
(`strings | grep` không thấy chuỗi UTF-16 và không phân biệt được `value=""`).

Lưu ý: `test_ads` độc lập với `enable_ads`. `enable_ads=false` = không init SDK.
`test_ads=false` = dùng production unit IDs (ads thật nếu unit đã điền).

## 1.6 R8 / ProGuard (lớp crash CHỈ có ở release)

Release bật **R8 minify** — Flutter Gradle plugin set
`releaseBuildType.isMinifyEnabled = true` (`FlutterPlugin.kt`), debug thì không.
Vì vậy bug loại này **vô hình trong quá trình dev**. Ca thật đã gặp (2026-09-12):
app cài được nhưng chết ở **mọi lần cold start**.

```
java.lang.RuntimeException: Failed to create an instance of
  androidx.work.impl.WorkDatabase
  at androidx.work.WorkManagerInitializer.b(...)
```

- `androidx.work` + `room` vào app như **transitive dependency của ads SDK**
  (`play-services-ads`). App không hề dùng WorkManager, nhưng WorkManager tự init
  qua `androidx.startup` trong một ContentProvider → chết **trước
  `Application.onCreate()`**, Dart không kịp bắt (kể cả force-update dialog).
- Room không gọi impl trực tiếp mà tạo bằng reflection
  (`Class.forName("..._Impl").newInstance()`). R8 không thấy call graph này → xoá
  `<init>()` dù consumer rule của Room vẫn giữ class + tên → `InstantiationException`.
- Fix: `android/app/proguard-rules.pro`
  (`-keep class * extends androidx.room.RoomDatabase { <init>(); }`) nối vào build
  type release bằng `proguardFiles(...)` trong `android/app/build.gradle.kts`.
- Guard: `tool/check_r8_keep.py` đọc `usage.txt` (R8 removed-code report) và **fail
  build** nếu constructor bị xoá; chạy trong cả `build-release-apk.yml` và
  `build-release-aab.yml`.

**Nguyên tắc:** KHÔNG tắt minify để "cho qua" — giữ minify + keep rule đúng. Mọi
thay đổi dependency phải verify bằng **cold start trên máy thật với release APK**,
không phải bằng "build xanh".
