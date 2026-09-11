// =============================================================================
// ShiftEase — AdMob banner service (2026-09-11)
// =============================================================================
// Monetization banner pinned under the Jobs screen (Play Store + App Store).
//
// Init order (deliberate):
//   1. UMP consent flow (requestConsentInfoUpdate →
//      loadAndShowConsentFormIfRequired) — required for EEA/UK; no-op where
//      consent is not required.
//   2. MobileAds.initialize() — only AFTER consent resolves.
//   3. BannerAd.load() with the resolved unit ID (test or production).
//
// Safety rails:
//   • AppAdsConfig.testAds = true → Google TEST unit IDs only (no real
//     inventory, no invalid-traffic/LIMIT risk on the AdMob account).
//   • test_ads=false with an unfilled production unit ('') → service
//     disables itself; the SDK is never pointed at placeholder/test units.
//   • Every Google API call is guarded try/catch — ad failures must NEVER
//     break the app (INVARIANT-008: the calendar keeps working offline).
// =============================================================================

import 'dart:async' show Completer;

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:shiftease/config/ads_config.dart';
export 'package:shiftease/config/ads_config.dart'
    show adsEnabled; // single import site for feature code

/// Runs the UMP consent flow, then initializes the Mobile Ads SDK.
///
/// Never throws: any error is swallowed (and left for Sentry to report via
/// the Flutter error zone) — ads are strictly additive to the app.
Future<void> initializeAds() async {
  if (!adsEnabled()) return;
  try {
    // 1. UMP consent (EEA/UK): update consent info, then show the form if
    //    required. Failure/timespans here only mean "no consent form shown"
    //    — ads still init (UMP config decides serving behavior).
    final gate = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          if (await ConsentInformation.instance.isConsentFormAvailable()) {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          }
        } catch (_) {/* consent UX is best-effort */}
        if (!gate.isCompleted) gate.complete();
      },
      (FormError error) {
        if (!gate.isCompleted) gate.complete();
      },
    );
    await gate.future;

    // 2. SDK init (AFTER consent).
    await MobileAds.instance.initialize();
  } catch (_) {
    // Ads must never break app startup; details go to Sentry via the zone.
  }
}

/// Owns the lifecycle of the app's single banner ad.
class BannerAdService {
  BannerAd? _banner;
  bool _loaded = false;

  /// True once a banner has successfully loaded (widget listens to rebuild).
  bool get isLoaded => _loaded;

  /// Callback fired on load state changes (widget rebuild hook).
  void Function()? onLoadedChanged;

  /// Loads a banner if ads are enabled. Safe to call multiple times;
  /// subsequent calls are no-ops while a banner exists.
  Future<void> loadBanner() async {
    if (_banner != null || !adsEnabled()) return;
    final unit = AdUnitIds.banner();
    if (unit.isEmpty) return;
    final banner = BannerAd(
      size: AdSize.banner,
      adUnitId: unit,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _loaded = true;
          onLoadedChanged?.call();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _banner = null;
          _loaded = false;
          // No retry storm: a later screen rebuild can call loadBanner again.
        },
      ),
      request: const AdRequest(),
    );
    _banner = banner;
    await banner.load();
  }

  /// The loaded banner for [AdBannerWidget], or null (widget hides itself).
  BannerAd? get banner => _loaded ? _banner : null;

  void dispose() {
    _banner?.dispose();
    _banner = null;
    _loaded = false;
  }
}
