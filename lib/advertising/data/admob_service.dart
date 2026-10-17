import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../domain/advertising_service.dart';
import '../domain/interstitial_policy.dart';
import 'admob_ids.dart';
import 'advertising_counter_store.dart';
import 'admob_interstitial.dart';
import 'advertising_debug_log.dart';

class AdmobService implements AdvertisingService {
  AdmobService({
    AdvertisingCounterStore? store,
    this.policy = const InterstitialPolicy(),
    Future<bool> Function()? initializeAds,
    Future<bool> Function()? canRequestAds,
    Future<AdmobInterstitial?> Function()? loadInterstitial,
    DateTime Function()? now,
  }) : _store = store ?? AdvertisingCounterStore(),
       _initializeAds = initializeAds,
       _canRequestAds =
           canRequestAds ?? ConsentInformation.instance.canRequestAds,
       _loadInterstitial = loadInterstitial ?? GoogleAdmobInterstitial.load,
       _now = now ?? DateTime.now;
  final AdvertisingCounterStore _store;
  final InterstitialPolicy policy;
  Future<bool>? _initialization;
  Future<void> _queue = Future.value();
  AdmobInterstitial? _interstitial;
  final Future<bool> Function()? _initializeAds;
  final Future<bool> Function() _canRequestAds;
  final Future<AdmobInterstitial?> Function() _loadInterstitial;
  final DateTime Function() _now;
  DateTime? _lastShown;
  int _privacyGeneration = 0;
  bool _disposed = false;
  bool _loading = false;
  bool _showing = false;
  bool _ready = false;

  Future<bool> initialize() async {
    await (_initialization ??= _initialize());
    return _ready && !_disposed;
  }

  Future<bool> _initialize() async {
    if (!AdmobIds.configured || _disposed) return false;
    final allowed = await (_initializeAds?.call() ?? _initializeGoogle());
    if (!allowed || _disposed) return false;
    _ready = true;
    _preload();
    return true;
  }

  Future<bool> _initializeGoogle() async {
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
      if (_disposed || !await _canRequestAds()) {
        return false;
      }
      await MobileAds.instance.initialize();
      if (_disposed) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  Future<void> showPrivacyOptions() async {
    _privacyGeneration++;
    _ready = false;
    _interstitial?.dispose();
    _interstitial = null;
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    await done.future;
    _ready = !_disposed && await _canRequestAds();
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
    await _store.write(
      counter.saves + 1,
      counter.lastShown,
      events: counter.events + 1,
      newAnalyses: counter.newAnalyses,
    );
  });

  @override
  Future<void> recordNewAnalysis() => _serialize(() async {
    final counter = await _store.read();
    await _store.write(
      counter.saves,
      counter.lastShown,
      events: counter.events + 1,
      newAnalyses: counter.newAnalyses + 1,
    );
  });

  void _preload() {
    if (!_ready || _disposed || _loading || _interstitial != null) return;
    _loading = true;
    logAdvertisingEvent('interstitial', 'preload_requested');
    final generation = _privacyGeneration;
    unawaited(
      _loadInterstitial()
          .then((ad) {
            _loading = false;
            if (_disposed || !_ready || generation != _privacyGeneration) {
              ad?.dispose();
              return;
            }
            _interstitial = ad;
            logAdvertisingEvent(
              'interstitial',
              ad == null ? 'preload_unavailable' : 'preload_ready',
            );
          })
          .catchError((Object _) {
            _loading = false;
            logAdvertisingEvent('interstitial', 'preload_exception');
          }),
    );
  }

  @override
  Future<void> showInterstitialIfEligible({
    InterstitialTrigger trigger = InterstitialTrigger.save,
    required bool Function() canShow,
  }) {
    final offeredAd = _interstitial;
    return _serialize(() async {
      if (!_ready || _disposed || _showing) {
        logAdvertisingEvent(
          'interstitial',
          'skipped_not_ready_or_showing',
          trigger: trigger.name,
        );
        return;
      }
      final generation = _privacyGeneration;
      if (!await _canRequestAds()) {
        logAdvertisingEvent(
          'interstitial',
          'skipped_consent',
          trigger: trigger.name,
        );
        return;
      }
      final counter = await _store.read();
      final now = _now().toUtc();
      final lastShown = _lastShown ?? counter.lastShown;
      final remaining = lastShown == null
          ? 0
          : (policy.minimumInterval - now.difference(lastShown)).inMilliseconds;
      logAdvertisingEvent(
        'interstitial',
        'frequency_check',
        trigger: trigger.name,
        events: counter.events,
        newAnalyses: counter.newAnalyses,
        cooldownSeconds: remaining <= 0 ? 0 : (remaining / 1000).ceil(),
      );
      if (!policy.isEligible(
        counter.events,
        _lastShown ?? counter.lastShown,
        now,
        trigger: trigger,
        newAnalyses: counter.newAnalyses,
      )) {
        logAdvertisingEvent(
          'interstitial',
          'skipped_frequency',
          trigger: trigger.name,
        );
        return;
      }
      final ad = offeredAd;
      if (ad == null || !identical(ad, _interstitial)) {
        logAdvertisingEvent(
          'interstitial',
          'skipped_unavailable',
          trigger: trigger.name,
        );
        _preload();
        return;
      }
      if (_disposed ||
          !_ready ||
          generation != _privacyGeneration ||
          !canShow()) {
        logAdvertisingEvent(
          'interstitial',
          'skipped_ui_state',
          trigger: trigger.name,
        );
        return;
      }
      _interstitial = null;
      _showing = true;
      var shown = false;
      var finished = false;
      void finish() {
        if (finished) return;
        finished = true;
        ad.dispose();
        _showing = false;
        _preload();
      }

      try {
        logAdvertisingEvent(
          'interstitial',
          'show_requested',
          trigger: trigger.name,
        );
        await ad.show(
          onShown: () {
            if (shown) return;
            shown = true;
            logAdvertisingEvent('interstitial', 'shown', trigger: trigger.name);
            _lastShown = _now().toUtc();
            unawaited(
              _serialize(() async {
                final latest = await _store.read();
                await _store.write(
                  latest.saves >= counter.saves
                      ? latest.saves - counter.saves
                      : 0,
                  _lastShown,
                  events: latest.events >= counter.events
                      ? latest.events - counter.events
                      : 0,
                  newAnalyses: latest.newAnalyses,
                );
              }).catchError((Object _) {}),
            );
          },
          onClosed: () {
            if (!finished) {
              logAdvertisingEvent(
                'interstitial',
                'closed',
                trigger: trigger.name,
              );
            }
            finish();
          },
          onFailed: () {
            if (!finished) {
              logAdvertisingEvent(
                'interstitial',
                'show_failed',
                trigger: trigger.name,
              );
            }
            finish();
          },
        );
      } catch (_) {
        logAdvertisingEvent(
          'interstitial',
          'show_failed',
          trigger: trigger.name,
        );
        finish();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _interstitial?.dispose();
    _interstitial = null;
  }
}
