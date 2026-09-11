# result_admob_integration.md — AdMob Ads Integration (test_ads=true)

> Date: 2026-09-11 · User request: tích hợp AdMob kiếm tiền trên Play/App Store,
> flag `test_ads=true` để tránh AdMob giới hạn quảng cáo (LIMIT).
> **Cập nhật cùng ngày: production Android IDs đã điền** (app + banner +
> interstitial + open + rewarded do owner cung cấp) — vẫn `test_ads=true`:
> chạy TEST ads trên unit thật của app; flip `test_ads=false` sau này → ads
> thật Android dùng ngay IDs đã điền (iOS chưa có IDs → tự tắt khi flip).

## Kiến trúc

```
pubspec.yaml (admob.test_ads: true)  ← 1 nơi flip
        ↓ mirror
lib/config/ads_config.dart           ← flag + ID resolution
   ├─ test mode  → Google TEST unit IDs (3940256099942544/...)
   └─ production → placeholder ''  ⇒ ads DISABLED (never falls back to test IDs)
        ↓
lib/features/ads/ad_service.dart     ← UMP consent → MobileAds.init → banner load
lib/features/ads/ad_banner_widget.dart ← self-hiding banner, pin bottom app shell
```

- **Banner duy nhất** đặt dưới app shell (`lib/app/app.dart` Column:
  JobsScreen + AdBannerWidget) — mọi màn đều có banner, calendar không bị ảnh
  hưởng layout khi ads tắt/chưa load (`SizedBox.shrink`).
- **Consent trước init** (UMP: `requestConsentInfoUpdate` →
  `loadAndShowConsentFormIfRequired` → `MobileAds.initialize()`): đúng thứ tự
  Google yêu cầu cho EEA/UK; failure của consent không block app.
- **Ads không bao giờ làm app lỗi**: mọi Google API call nằm trong try/catch,
  banner load-fail → dispose + về trạng thái tắt (INVARIANT-008 offline-first
  không đổi).
- minSdk pin **24** (google_mobile_ads 9.1.0 yêu cầu, trước đó
  `flutter.minSdkVersion`); targetSdk 36 giữ nguyên.

## Flag test_ads — đúng yêu cầu "tránh admob giới hạn quảng cáo"

- `admob.test_ads: true` trong pubspec (comment giải thích) + mirror
  `AppAdsConfig.testAds` (mutable chỉ để test flip, tearDown restore).
- Test mode → toàn bộ traffic dùng **Google test unit IDs**: thiết bị được coi
  là test device, không có invalid traffic thật trên account, **không rủi ro
  LIMIT**.
- Native manifests dùng **Google sample APPLICATION_IDs** (`~3347511713` /
  `~1458002511`) — Google chính thức cung cấp cho mục đích test, không thuộc
  account của ai → không thể sinh invalid traffic lên account thật.
- **Production checklist** ghi trong privacy.md §ads: khi đi live BẮT BUỘC
  (1) điền IDs thật vào `ads_config.dart` + manifest + Info.plist,
  (2) khai báo Data safety (Advertising ID) / App Privacy, (3) re-audit
  privacy.md — rồi mới flip `test_ads=false`. Test ID với `test_ads=false`
  sẽ bị **test chống fallback** chặn (ads = disabled, không crash).

## Files thay đổi

| File | Thay đổi |
|---|---|
| `pubspec.yaml` | + `google_mobile_ads: ^9.1.0`, + `admob: test_ads: true` |
| `lib/config/ads_config.dart` | NEW — flag, test/production IDs, `AdUnitIds.banner/interstitial` (return `''` khi production placeholder) |
| `lib/features/ads/ad_service.dart` | NEW — UMP consent + init + `BannerAdService` lifecycle |
| `lib/features/ads/ad_banner_widget.dart` | NEW — self-hiding banner widget + singleton service |
| `lib/app/app.dart` | wrap home: `Expanded(JobsScreen)` + `AdBannerWidget` |
| `android/.../AndroidManifest.xml` | + AdMob APPLICATION_ID (sample) meta-data |
| `ios/Runner/Info.plist` | + `GADApplicationIdentifier` (sample) + 39 SKAdNetworkItems |
| `android/app/build.gradle.kts` | minSdk pin 24 |
| `doc/release/privacy.md` | re-audit lần 3: 2 network consumers, Data safety checklist trước khi live ads |
| `doc/release/monitoring.md` | + AdMob console signal (impressions/clicks/policy alerts) |
| `test/config/ads_config_test.dart` | NEW — 6 tests |

## Tests (mới: 6)

- Test mode: đúng Google test ID từng platform; `adsEnabled = true`.
- Production placeholder: trả `''`, `adsEnabled = false` — **không fallback
  sang test ID** (test chống ship nhầm).
- Production constants không chứa prefix sample Google.
- Shipped default `testAds == true` (bảo vệ account).

## Evidence (session này)

- `flutter pub get` → resolved google_mobile_ads **9.1.0** (UMP API surface
  verified trực tiếp trong pub cache: `requestConsentInfoUpdate`,
  `loadAndShowConsentFormIfRequired(listener)`, `RequestConfiguration.testDeviceIds`).
- `flutter analyze --no-pub --fatal-infos` → **No issues found!**
- `flutter test test/` → **343/343 All tests passed!** (after EN-language pass + App Open/Interstitial wiring)
- (2 vòng fix analyze trong session: unused import/field, và signature
  `loadAndShowConsentFormIfRequired` cần listener ở 9.1.0.)

## Code review của commit EN + ads (2026-09-11) — 2 lỗi thật, đã sửa

| # | Lỗi | Fix |
|---|---|---|
| **M1** | **App Open Google test unit IDs SAI** trên cả 2 platform: Android `/3419835294`, iOS `/5662855259` — không có trong bảng demo ad units chính thức → App Open sẽ KHÔNG BAO GIỜ load, silently. Đối chiếu developers.google.com/admob/android/test-ads + /ios/test-ads | Android → `/9257395921`, iOS → `/5575463023` (đúng bảng). Banner/interstitial IDs đối chiếu lại: đúng sẵn |
| **M2** | `initializeAds()` (UMP consent + SDK init) chạy trong `build()` của `_BootstrapState` — MỖI rebuild re-run consent flow; cộng thêm call trùng từ `AdBannerWidget.initState` | (a) `initializeAds` memoized (`_initializeAdsOnce ??=`) — consent + init chạy đúng 1 lần/process dù call từ đâu, bao nhiêu lần; (b) chuỗi App Open dời từ `build()` sang ngay sau `setState(_service=…)` trong `_openProductionDatabase()` — chạy 1 lần/cold start |
| LOW | App Open ad có thể pop full-screen giữa chừng nếu load chậm hơn 15s hoặc user đã vào task | Guard `showWindow = 15s` từ construction service: ad quá hạn bị discard + preload lại cho lần sau (đúng guidance "cold start only") |
| LOW | ads_config_test mutate `AppAdsConfig.testAds` static mà không restore | Hoạt động đúng nhờ thứ tự khai báo test (default-true test chạy trước) — đáng thêm `tearDown` restore khi chạm file lần tới |

Verify sau fix: analyze sạch · **343/343** · test contract openApp vẫn khoá đúng (test mode → Google unit, flip → production Android ID, iOS rỗng).

## Còn lại (human, khi muốn kiếm tiền thật)

1. ~~Tạo AdMob account → tạo app Android~~ ✅ **Đã tạo (2026-09-11):** App ID `ca-app-pub-6917313063209470~6379119743` + 4 units (banner/interstitial/open/rewarded) đã điền vào `ads_config.dart` + AndroidManifest.
2. ~~App Open + Interstitial chưa có placement~~ ✅ **Đã wire (2026-09-11, sau này):** `AppOpenAdService` hiển thị khi cold start (main.dart, sau MobileAds init + consent); `InterstitialAdService.maybeShowAfterCommit()` gọi sau khi import commit thành công (import_screen.dart) — cả hai dùng test IDs khi `test_ads=true`. **Rewarded vẫn chưa có placement UI** (getter sẵn).
3. **iOS CHƯA có**: tạo app iOS trên AdMob console → điền `kAdMobIosAppIdProduction` + units + thay GADApplicationIdentifier trong Info.plist (hiện sample).
4. Khai báo Play Data safety (Advertising ID collected/shared) + App Store App Privacy; re-audit privacy.md.
5. Flip `admob.test_ads: false` (pubspec + mirror `AppAdsConfig.testAds` trong `ads_config.dart`) → push → CI build → test trên device thật: banner/interstitial/app-open thật của app, không LIMIT.
6. (Tuỳ chọn) Gắn device test ID từ logcat vào RequestConfiguration để preview ads thật trên máy dev.
