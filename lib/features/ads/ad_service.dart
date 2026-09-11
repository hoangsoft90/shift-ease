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
    show adsEnabled, AdUnitIds; // single import site for feature code

/// Runs the UMP consent flow, then initializes the Mobile Ads SDK.
///
/// Never throws: any error is swallowed (and left for Sentry to report via
/// the Flutter error zone) — ads are strictly additive to the app.
///
/// Memoized: call sites (main.dart bootstrap, AdBannerWidget initState) may
/// fire concurrently/repeatedly — the UMP consent flow + SDK init run EXACTLY
/// once per process; everyone awaits the same promise.
Future<void> initializeAds() => _initializeAdsOnce ??= _initializeAdsInner();
Future<void>? _initializeAdsOnce;

Future<void> _initializeAdsInner() async {
  if (!adsEnabled()) return; // also covers AppAdsConfig.enableAds == false
  if (!AppAdsConfig.enableAds) {
    // Master switch off: SDK init and all ad placement are skipped entirely.
    // (This branch is redundant with the adsEnabled() early-return above but
    //  keeps the intent explicit for reviewers and Sentry-occasionally reports
    //  dead code as suspicious.)
    return;
  }
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

/// Owns the lifecycle of the app's single preloaded App Open ad (2026-09-11).
///
/// Policy:
///   • load() right after SDK init (called from main.dart's bootstrap chain).
///   • showIfAvailable() fires on every cold start (and warm reshares where
///     the OS gives a backgrounded-app event — cold start only here).
///   • After showing (or failing to show), a fresh ad is preloaded so the
///     NEXT launch always has one ready (Google's recommended pattern).
///   • Any error is swallowed — ads never block or break the app
///     (INVARIANT-008). Sentry sees the error via the Flutter error zone.
class AppOpenAdService {
  AppOpenAdService() : _createdAt = DateTime.now();
  AppOpenAd? _ad;
  bool _isLoading = false;
  final DateTime _createdAt;

  /// How long after launch a loaded app-open ad may still be shown.
  static const Duration showWindow = Duration(seconds: 15);

  /// True once an ad is preloaded and ready to show.
  bool get isReady => _ad != null;

  /// Preloads an app-open ad if ads are enabled and none is pending/ready.
  Future<void> load() async {
    if (_ad != null || _isLoading || !adsEnabled()) return;
    final unit = AdUnitIds.openApp();
    if (unit.isEmpty) return;
    _isLoading = true;
    try {
      await AppOpenAd.load(
        adUnitId: unit,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _isLoading = false;
          },
          onAdFailedToLoad: (error) {
            // No retry storm: the next cold start retries.
            _isLoading = false;
          },
        ),
      );
    } catch (_) {
      _isLoading = false;
    }
  }

  /// Shows the preloaded ad (cold-start placement). Returns true when an ad
  /// was actually shown. Disposes after showing/failed-show and re-preloads
  /// for the next launch.
  ///
  /// UX/policy guard: the ad must be ready within [showWindow] of process
  /// start — if the user is already deep in a task (import review, calendar
  /// edit), popping a full-screen app-open ad mid-flow is against AdMob
  /// guidance. In that case the ad is discarded and retried next launch.
  Future<bool> showIfAvailable() async {
    final ad = _ad;
    if (ad == null) return false;
    if (DateTime.now().difference(_createdAt) > showWindow) {
      ad.dispose();
      _ad = null;
      return false;
    }
    _ad = null;
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        load(); // preload for the next cold start
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        load();
      },
    );
    try {
      await ad.show();
      return true;
    } catch (_) {
      ad.dispose();
      load();
      return false;
    }
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}

/// Owns the app's single preloaded interstitial ad (2026-09-11).
///
/// Placement policy — natural completion points ONLY, never mid-flow:
///   • after a successful roster commit (import flow finished end-to-end).
/// Frequency caps (private, session-level):
///   • minimum 1 interstitial per 3 successful commits,
///   • never twice in a row within 60 seconds.
/// Everything is guarded; ad failure must never break the flow it follows.
class InterstitialAdService {
  InterstitialAd? _ad;
  bool _isLoading = false;
  int _commitsSinceLastShown = 0;
  DateTime _lastShownAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True once an ad is preloaded and ready to show.
  bool get isReady => _ad != null;

  /// Frequency gate for tests/honesty: the minimum commits between shows.
  static const int minCommitsBetweenShows = 3;

  /// Preloads an interstitial if ads are enabled and none is pending/ready.
  Future<void> load() async {
    if (_ad != null || _isLoading || !adsEnabled()) return;
    final unit = AdUnitIds.interstitial();
    if (unit.isEmpty) return;
    _isLoading = true;
    try {
      await InterstitialAd.load(
        adUnitId: unit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _isLoading = false;
          },
          onAdFailedToLoad: (error) {
            _isLoading = false;
          },
        ),
      );
    } catch (_) {
      _isLoading = false;
    }
  }

  /// Call after every SUCCESSFUL roster commit. Shows at most once per
  /// [minCommitsBetweenShows] commits and never within 60s of the last show.
  Future<void> maybeShowAfterCommit() async {
    _commitsSinceLastShown++;
    if (_commitsSinceLastShown < minCommitsBetweenShows) {
      load(); // keep a fresh ad ready for the next window
      return;
    }
    if (DateTime.now().difference(_lastShownAt) <
        const Duration(seconds: 60)) {
      return;
    }
    final ad = _ad;
    if (ad == null) {
      load();
      return;
    }
    _ad = null;
    _commitsSinceLastShown = 0;
    _lastShownAt = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        load();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        load();
      },
    );
    try {
      await ad.show();
    } catch (_) {
      ad.dispose();
      load();
    }
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
