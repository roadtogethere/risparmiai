import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/advertising/data/admob_service.dart';
import 'package:risparmiai/advertising/data/advertising_counter_store.dart';
import 'package:risparmiai/advertising/domain/advertising_service.dart';
import 'package:risparmiai/advertising/domain/interstitial_policy.dart';
import 'package:risparmiai/advertising/presentation/interstitial_coordinator.dart';

class FakeAdvertising implements AdvertisingService {
  int newAnalyses = 0;
  int chatMessages = 0;
  @override
  Future<void> recordChatMessage() async {
    chatMessages++;
  }

  @override
  Future<void> recordNewAnalysis() async {
    newAnalyses++;
  }

  int saves = 0;
  int opportunities = 0;
  bool fail = false;
  @override
  Future<void> recordSuccessfulSave() async {
    if (fail) throw StateError('Storage unavailable');
    saves++;
  }

  @override
  Future<void> showInterstitialIfEligible({
    InterstitialTrigger trigger = InterstitialTrigger.save,
    required bool Function() canShow,
  }) async {
    if (canShow()) opportunities++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'frequency requires threshold and cooldown, including clock rollback',
    () {
      const policy = InterstitialPolicy();
      final now = DateTime.utc(2026, 10, 17);
      expect(policy.isEligible(4, null, now), isFalse);
      expect(policy.isEligible(5, null, now), isTrue);
      expect(
        policy.isEligible(8, now.subtract(const Duration(seconds: 119)), now),
        isFalse,
      );
      expect(
        policy.isEligible(5, now.subtract(const Duration(minutes: 5)), now),
        isTrue,
      );
      expect(
        policy.isEligible(8, now.add(const Duration(minutes: 1)), now),
        isFalse,
      );
    },
  );

  test(
    'concurrent saves persist independently from economic storage and restart',
    () async {
      SharedPreferences.setMockInitialValues({
        'verified_price_observations_v1': 'unchanged',
      });
      final service = AdmobService();
      await Future.wait(
        List.generate(12, (_) => service.recordSuccessfulSave()),
      );
      service.dispose();
      expect((await AdvertisingCounterStore().read()).saves, 12);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('verified_price_observations_v1'), 'unchanged');
      final restarted = AdmobService();
      await restarted.recordSuccessfulSave();
      expect((await AdvertisingCounterStore().read()).saves, 13);
      restarted.dispose();
    },
  );

  testWidgets('only a new save offers an ad and failures stay isolated', (
    tester,
  ) async {
    final ads = FakeAdvertising();
    final coordinator = InterstitialCoordinator(ads);
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await coordinator.afterSave(pageContext, newlySaved: false);
    expect(ads.saves, 0);
    await coordinator.afterSave(pageContext, newlySaved: true);
    expect(ads.saves, 1);
    expect(ads.opportunities, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await coordinator.afterSave(pageContext, newlySaved: true);
    expect(ads.saves, 2);
    expect(ads.opportunities, 1);
    ads.fail = true;
    await coordinator.afterSave(pageContext, newlySaved: true);
    expect(ads.opportunities, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
