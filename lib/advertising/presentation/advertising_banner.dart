import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../data/admob_ids.dart';
import '../data/admob_service.dart';

class AdvertisingBanner extends StatefulWidget {
  const AdvertisingBanner({super.key});
  @override
  State<AdvertisingBanner> createState() => _AdvertisingBannerState();
}

class _AdvertisingBannerState extends State<AdvertisingBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _privacyRequired = false;
  int _generation = 0;
  int? _width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.floor();
    if (_width == width) return;
    _width = width;
    final generation = ++_generation;
    _ad?.dispose();
    _ad = null;
    _loaded = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(width, generation);
    });
  }

  Future<void> _load(int width, int generation) async {
    final service = context.read<AdmobService?>();
    if (service == null) return;
    try {
      final ready = await service.initialize();
      final privacy =
          AdmobIds.configured && await service.privacyOptionsRequired();
      if (!mounted || generation != _generation) return;
      setState(() => _privacyRequired = privacy);
      if (!ready) return;
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      if (!mounted || generation != _generation || size == null) return;
      final ad = BannerAd(
        adUnitId: AdmobIds.banner,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || generation != _generation) {
              ad.dispose();
              return;
            }
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (mounted && generation == _generation) {
              setState(() {
                _ad = null;
                _loaded = false;
              });
            }
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      /* Leave the application usable without ads. */
    }
  }

  @override
  void dispose() {
    _generation++;
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_loaded && _ad != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: _ad!.size.width.toDouble(),
            height: _ad!.size.height.toDouble(),
            child: AdWidget(ad: _ad!),
          ),
        ),
      if (_privacyRequired)
        TextButton(
          onPressed: () async {
            final service = context.read<AdmobService?>();
            if (service == null) return;
            try {
              await service.showPrivacyOptions();
              if (!mounted) return;
              setState(() {
                _ad?.dispose();
                _ad = null;
                _loaded = false;
              });
              await _load(_width!, ++_generation);
            } catch (_) {
              /* The form can be retried. */
            }
          },
          child: const Text('Preferenze privacy annunci'),
        ),
    ],
  );
}
