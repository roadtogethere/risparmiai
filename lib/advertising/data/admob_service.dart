import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../domain/advertising_service.dart';
import '../domain/interstitial_policy.dart';
import 'admob_ids.dart';
import 'advertising_counter_store.dart';

class AdmobService implements AdvertisingService {
  AdmobService({
    AdvertisingCounterStore? store,
    this.policy = const InterstitialPolicy(),
  }) : _store = store ?? AdvertisingCounterStore();
  final AdvertisingCounterStore _store;
  final InterstitialPolicy policy;
  Future<bool>? _initialization;
  Future<void> _queue = Future.value();
  InterstitialAd? _interstitial;
  bool _disposed = false;
  bool _loading = false;
  bool _showing = false;
  bool _ready = false;

  Future<bool> initialize() async {
    await (_initialization ??= _initialize());
    return _ready && !_disposed;
  }

  Future<bool> _initialize() async {
    if (!AdmobIds.supported || _disposed) return false;
    try {
      final consent = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => consent.complete(),
        (_) => consent.complete(),
      );
      await consent.future;
      if (_disposed) return false;
      final form = Completer<void>();
      ConsentForm.loadAndShowConsentFormIfRequired((_) => form.complete());
      await form.future;
      if (_disposed || !await ConsentInformation.instance.canRequestAds()) {
        return false;
      }
      await MobileAds.instance.initialize();
      if (_disposed) return false;
      _ready = true;
      _preload();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    await done.future;
    _ready = await ConsentInformation.instance.canRequestAds();
    _interstitial?.dispose();
    _interstitial = null;
    if (_ready) _preload();
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> recordSuccessfulSave() => _serialize(() async {
    final counter = await _store.read();
    await _store.write(counter.saves + 1, counter.lastShown);
  });

  void _preload() {
    if (!_ready || _disposed || _loading || _interstitial != null) return;
    _loading = true;
    unawaited(
      InterstitialAd.load(
        adUnitId: AdmobIds.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _loading = false;
            if (_disposed || !_ready) {
              ad.dispose();
              return;
            }
            _interstitial = ad;
          },
          onAdFailedToLoad: (_) {
            _loading = false;
          },
        ),
      ).catchError((Object _) {
        _loading = false;
      }),
    );
  }

  @override
  Future<void> showInterstitialIfEligible({required bool Function() canShow}) =>
      _serialize(() async {
        if (!_ready || _disposed || _showing) return;
        final counter = await _store.read();
        final now = DateTime.now().toUtc();
        if (!policy.isEligible(counter.saves, counter.lastShown, now)) return;
        final ad = _interstitial;
        if (ad == null) {
          _preload();
          return;
        }
        if (!canShow()) return;
        _interstitial = null;
        _showing = true;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdShowedFullScreenContent: (_) {
            unawaited(
              _serialize(() => _store.write(0, now)).catchError((Object _) {}),
            );
          },
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            _showing = false;
            _preload();
          },
          onAdFailedToShowFullScreenContent: (ad, _) {
            ad.dispose();
            _showing = false;
            _preload();
          },
        );
        try {
          await ad.show();
        } catch (_) {
          ad.dispose();
          _showing = false;
          _preload();
        }
      });

  void dispose() {
    _disposed = true;
    _interstitial?.dispose();
    _interstitial = null;
  }
}
