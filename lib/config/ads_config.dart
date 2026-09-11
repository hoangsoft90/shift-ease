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
//   • false → production AdMob unit IDs below are used. If any of them is
//     still a placeholder (empty string), ads are DISABLED (unit == '') —
//     the app must never ship real-traffic placeholders like the Google
//     sample IDs (ca-app-pub-3940256099942544/...) with test_ads=false.
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

/// Production AdMob IDs — PLACEHOLDERS until the owner creates the AdMob
/// apps/units. Empty strings by design: with test_ads=false and an empty
/// unit, [AdUnitIds.banner]/[AdUnitIds.interstitial] return '' and the ad
/// service disables itself (never ships Google test IDs as real inventory).
const String kAdMobAndroidAppIdProduction = '';
const String kAdMobIosAppIdProduction = '';
const String kAdMobAndroidBannerUnitProduction = '';
const String kAdMobIosBannerUnitProduction = '';
const String kAdMobAndroidInterstitialUnitProduction = '';
const String kAdMobIosInterstitialUnitProduction = '';

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
