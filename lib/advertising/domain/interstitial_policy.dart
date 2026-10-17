import 'advertising_service.dart';

class InterstitialPolicy {
  const InterstitialPolicy({
    this.savesPerAd = 5,
    this.messagesPerAd = 5,
    this.minimumInterval = const Duration(minutes: 5),
  }) : assert(savesPerAd > 0),
       assert(messagesPerAd > 0);

  final int savesPerAd;
  final int messagesPerAd;
  final Duration minimumInterval;

  bool isEligible(
    int saves,
    DateTime? lastShown,
    DateTime now, {
    InterstitialTrigger trigger = InterstitialTrigger.save,
    int newAnalyses = 0,
    int chatMessages = 0,
  }) =>
      (switch (trigger) {
        InterstitialTrigger.save => saves >= savesPerAd,
        InterstitialTrigger.chat => chatMessages >= messagesPerAd,
        InterstitialTrigger.newAnalysis => newAnalyses > 0,
      }) &&
      (lastShown == null || now.difference(lastShown) >= minimumInterval);
}
