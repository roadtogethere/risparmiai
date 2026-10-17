import 'package:flutter/widgets.dart';
import '../domain/advertising_service.dart';
import '../data/advertising_debug_log.dart';

class InterstitialCoordinator {
  const InterstitialCoordinator(this.service);
  final AdvertisingService service;

  Future<bool> recordChatMessage() async {
    try {
      await service.recordChatMessage();
      return true;
    } catch (_) {
      logAdvertisingEvent('interstitial', 'event_failed', trigger: 'chat');
      return false;
    }
  }

  Future<void> afterChatAnalysis(
    BuildContext context, {
    required Future<bool> registration,
    required bool Function() canShow,
  }) async {
    try {
      if (!await registration || !context.mounted || !canShow()) return;
      await service.showInterstitialIfEligible(
        trigger: InterstitialTrigger.chat,
        canShow: () =>
            context.mounted &&
            canShow() &&
            ModalRoute.of(context)?.isCurrent == true &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
    } catch (_) {
      logAdvertisingEvent('interstitial', 'event_failed', trigger: 'chat');
    }
  }

  Future<void> afterSave(
    BuildContext context, {
    required bool newlySaved,
    bool Function()? canShow,
  }) async {
    if (!newlySaved) return;
    try {
      await service.recordSuccessfulSave();
      if (!context.mounted) return;
      // Never show a late-loaded ad: only a ready ad at this UI transition.
      await service.showInterstitialIfEligible(
        canShow: () =>
            (canShow?.call() ?? true) &&
            context.mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
    } catch (_) {
      // Advertising failure must never change the successful save outcome.
    }
  }

  Future<void> afterNewAnalysis(
    BuildContext context, {
    required bool Function() canShow,
  }) async {
    try {
      await service.recordNewAnalysis();
      if (!context.mounted) return;
      await service.showInterstitialIfEligible(
        trigger: InterstitialTrigger.newAnalysis,
        canShow: () =>
            context.mounted &&
            canShow() &&
            ModalRoute.of(context)?.isCurrent == true &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
    } catch (_) {
      // The conversation has already reset; ads must never block it.
      logAdvertisingEvent(
        'interstitial',
        'event_failed',
        trigger: 'newAnalysis',
      );
    }
  }
}
