class InterstitialPolicy {
  const InterstitialPolicy({
    this.savesPerAd = 5,
    this.minimumInterval = const Duration(minutes: 2),
  }) : assert(savesPerAd > 0);

  final int savesPerAd;
  final Duration minimumInterval;

  bool isEligible(int saves, DateTime? lastShown, DateTime now) =>
      saves >= savesPerAd &&
      (lastShown == null || now.difference(lastShown) >= minimumInterval);
}
