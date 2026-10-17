import 'advertising_service.dart';

class InterstitialPolicy {
  const InterstitialPolicy({
    this.eventsPerAd = 5,
    this.minimumInterval = const Duration(minutes: 5),
  }) : assert(eventsPerAd > 0);

  final int eventsPerAd;
  final Duration minimumInterval;

  bool isEligible(
    int events,
    DateTime? lastShown,
    DateTime now, {
    InterstitialTrigger trigger = InterstitialTrigger.save,
    int newAnalyses = 0,
  }) =>
      (trigger != InterstitialTrigger.newAnalysis || newAnalyses > 2) &&
      events >= eventsPerAd &&
      (lastShown == null || now.difference(lastShown) >= minimumInterval);
}
