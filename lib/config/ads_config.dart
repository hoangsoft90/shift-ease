// =============================================================================
// ShiftEase — AdMob configuration (2026-09-11)
// =============================================================================
// Monetization: banner ads under the Jobs screen (Play Store + App Store).
//
// test_ads flag (pubspec `admob.test_ads`, mirrored in AppAdsConfig.testAds):
//   • true  → the app ALWAYS uses Google's official test ad unit IDs and the
//     manifests ship the sample APPLICATION_IDs. No real ad traffic, no
//     invalid-traffic risk, no AdMob account LIMIT. CI/dev/test builds stay
//     here.
//   • false → production AdMob unit IDs below are used. Android units are
//     FILLED (2026-09-11) so flipping the flag serves REAL ads on Android;
//     iOS units are still empty → iOS ads stay disabled (no crash, no
//     test-ID fallback).
//
// Production placeholders (owner fills from the AdMob console, then flips
// test_ads to false):
//   kAdMob*AppIdProduction        → the App IDs (manifest/plist), NOT units
//   kAdMob*UnitProduction         → ad unit IDs per platform/format
// =============================================================================

import 'dart:io' show Platform;

/// Dart-side mirror of the pubspec `admob:` block (pubspec parsing of custom
/// maps would need a hook; one constant keeps a single place to flip).
/// Mutable (not `const`) ONLY so tests can exercise both branches — they must
/// restore `true` in tearDown. Production flips this to false once the real
/// AdMob IDs are filled in.
class AppAdsConfig {
  /// true = test mode (Google test IDs, sample app IDs). See file header.
  static bool testAds = true;
}

/// Whether a real banner can be requested on this platform/build: false in
/// test-disabled production builds whose unit IDs are still placeholders.
bool adsEnabled({bool? android}) => AdUnitIds.banner(android: android) != '';

/// Google's official PUBLISHER-wide sample APPLICATION_IDs (safe to ship —
/// they only activate test infrastructure; Google's own docs use them).
const String kAdMobAndroidSampleAppId =
    'ca-app-pub-3940256099942544~3347511713';
const String kAdMobIosSampleAppId = 'ca-app-pub-3940256099942544~1458002511';

/// Google's official test AD UNIT IDs (banner/interstitial). Real inventory
/// never serves on these; clicks/impressions are explicitly allowed.
const String kAdMobTestBannerAndroid =
    'ca-app-pub-3940256099942544/6300978111';
const String kAdMobTestBannerIos = 'ca-app-pub-3940256099942544/2934735716';
const String kAdMobTestInterstitialAndroid =
    'ca-app-pub-3940256099942544/1033173712';
const String kAdMobTestInterstitialIos =
    'ca-app-pub-3940256099942544/4411468910';
const String kAdMobTestOpenAppAndroid =
    'ca-app-pub-3940256099942544/9257395921';
const String kAdMobTestOpenAppIos = 'ca-app-pub-3940256099942544/5575463023';

/// Production AdMob IDs — **Android FILLED 2026-09-11** (app + banner +
/// interstitial + open + rewarded). iOS app chưa tạo trên AdMob console →
/// iOS production IDs để rỗng ('') cho tới khi có: với test_ads=false, iOS
/// ads sẽ tự TẮT (không crash, không fallback sang test IDs).
const String kAdMobAndroidAppIdProduction =
    'ca-app-pub-6917313063209470~6379119743';
const String kAdMobIosAppIdProduction = '';
const String kAdMobAndroidBannerUnitProduction =
    'ca-app-pub-6917313063209470/7669818989';
const String kAdMobIosBannerUnitProduction = '';
const String kAdMobAndroidInterstitialUnitProduction =
    'ca-app-pub-6917313063209470/5811153858';
const String kAdMobIosInterstitialUnitProduction = '';
const String kAdMobAndroidOpenAppUnitProduction =
    'ca-app-pub-6917313063209470/8158115597';
const String kAdMobAndroidRewardedUnitProduction =
    'ca-app-pub-6917313063209470/3866305343';

/// Resolved per-platform ad unit IDs honoring [AppAdsConfig.testAds].
///
/// [android] overrides the platform probe in tests (production callers omit
/// it). Returns '' (ads disabled) for production placeholders — NEVER falls
/// back to a Google test ID when test mode is off.
class AdUnitIds {
  static String banner({bool? android}) =>
      _pick(android: android, testA: kAdMobTestBannerAndroid,
          testI: kAdMobTestBannerIos, prodA: kAdMobAndroidBannerUnitProduction,
          prodI: kAdMobIosBannerUnitProduction);

  static String interstitial({bool? android}) =>
      _pick(android: android, testA: kAdMobTestInterstitialAndroid,
          testI: kAdMobTestInterstitialIos,
          prodA: kAdMobAndroidInterstitialUnitProduction,
          prodI: kAdMobIosInterstitialUnitProduction);

  /// App Open ad unit — SHOWN on every cold start (AppOpenAdService in
  /// main.dart) once the SDK is initialized. iOS: no production app yet →
  /// '' (self-disabling) in production; test mode uses Google's test unit.
  static String openApp({bool? android}) =>
      _pick(android: android, testA: kAdMobTestOpenAppAndroid,
          testI: kAdMobTestOpenAppIos,
          prodA: kAdMobAndroidOpenAppUnitProduction, prodI: '');

  /// Rewarded ad unit — production Android ID đã điền, format CHƯA hiển thị
  /// (no placement yet → test mode returns '' so nothing requests it).
  static String rewarded({bool? android}) =>
      _pick(android: android, testA: '', testI: '',
          prodA: kAdMobAndroidRewardedUnitProduction, prodI: '');

  static String _pick({
    required bool? android,
    required String testA,
    required String testI,
    required String prodA,
    required String prodI,
  }) {
    final isAndroid = android ?? Platform.isAndroid;
    if (AppAdsConfig.testAds) return isAndroid ? testA : testI;
    return isAndroid ? prodA : prodI;
  }
}
