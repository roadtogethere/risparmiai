import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/advertising/data/admob_interstitial.dart';
import 'package:risparmiai/advertising/data/admob_service.dart';
import 'package:risparmiai/advertising/data/advertising_counter_store.dart';
import 'package:risparmiai/advertising/domain/advertising_service.dart';
import 'package:risparmiai/advertising/domain/interstitial_policy.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';
import 'advertising_test.dart' show FakeAdvertising;
import 'quantity_planner_test.dart' as fixture;
import 'conversation_intent_test.dart' show ScriptClient;

class TestInterstitial implements AdmobInterstitial {
  int shows = 0;
  int disposals = 0;
  bool fail = false;
  bool hold = false;
  VoidCallback? close;
  @override
  Future<void> show({
    required VoidCallback onShown,
    required VoidCallback onClosed,
    required VoidCallback onFailed,
  }) async {
    shows++;
    if (fail) {
      onFailed();
      return;
    }
    onShown();
    onShown(); // Duplicate SDK callbacks must not reset counters twice.
    close = onClosed;
    if (!hold) onClosed();
  }

  @override
  void dispose() {
    disposals++;
  }
}

class AdHarness {
  bool consent = true;
  bool available = true;
  bool failShow = false;
  bool hold = false;
  DateTime time = DateTime.utc(2026, 10, 17);
  final ads = <TestInterstitial>[];
  late final AdmobService service = AdmobService(
    initializeAds: () async => consent,
    canRequestAds: () async => consent,
    now: () => time,
    loadInterstitial: () async {
      if (!available) return null;
      final ad = TestInterstitial()
        ..fail = failShow
        ..hold = hold;
      ads.add(ad);
      return ad;
    },
  );
  int get shows => ads.fold(0, (total, ad) => total + ad.shows);
  Future<void> start() async {
    await service.initialize();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> event(InterstitialTrigger trigger, {bool canShow = true}) async {
    if (trigger == InterstitialTrigger.save) {
      await service.recordSuccessfulSave();
    } else {
      await service.recordNewAnalysis();
    }
    await service.showInterstitialIfEligible(
      trigger: trigger,
      canShow: () => canShow,
    );
    await Future<void>.delayed(Duration.zero);
  }
}

class DelayedAdvertising extends FakeAdvertising {
  final recorded = Completer<void>();
  @override
  Future<void> recordNewAnalysis() async {
    newAnalyses++;
    await recorded.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first two analyses exempt even with shared threshold reached', () {
    const policy = InterstitialPolicy();
    final now = DateTime.utc(2026);
    for (final total in [1, 2]) {
      expect(
        policy.isEligible(
          20,
          null,
          now,
          trigger: InterstitialTrigger.newAnalysis,
          newAnalyses: total,
        ),
        isFalse,
      );
    }
    expect(
      policy.isEligible(
        5,
        null,
        now,
        trigger: InterstitialTrigger.newAnalysis,
        newAnalyses: 3,
      ),
      isTrue,
    );
    expect(
      policy.isEligible(5, now.subtract(const Duration(seconds: 299)), now),
      isFalse,
    );
    expect(
      policy.isEligible(5, now.subtract(const Duration(minutes: 5)), now),
      isTrue,
    );
  });

  test('new analyses alone offer every five with a persisted warmup', () async {
    final h = AdHarness();
    addTearDown(h.service.dispose);
    await h.start();
    for (var i = 1; i <= 5; i++) {
      await h.event(InterstitialTrigger.newAnalysis);
      expect(h.shows, i == 5 ? 1 : 0);
    }
    expect((await AdvertisingCounterStore().read()).events, 0);
    h.time = h.time.add(const Duration(minutes: 5));
    for (var i = 6; i <= 10; i++) {
      await h.event(InterstitialTrigger.newAnalysis);
      expect(h.shows, i == 10 ? 2 : 1);
    }
    expect((await AdvertisingCounterStore().read()).newAnalyses, 10);
  });

  test(
    'save and analysis share frequency and cooldown in both directions',
    () async {
      final h = AdHarness();
      addTearDown(h.service.dispose);
      await h.start();
      await h.event(InterstitialTrigger.save);
      await h.event(InterstitialTrigger.save);
      for (var i = 0; i < 3; i++) {
        await h.event(InterstitialTrigger.newAnalysis);
      }
      expect(h.shows, 1);
      for (var i = 0; i < 5; i++) {
        await h.event(InterstitialTrigger.save);
      }
      expect(h.shows, 1);
      h.time = h.time.add(const Duration(minutes: 5));
      await h.event(InterstitialTrigger.save);
      expect(h.shows, 2);
      for (var i = 0; i < 5; i++) {
        await h.event(InterstitialTrigger.newAnalysis);
      }
      expect(h.shows, 2);
    },
  );

  test(
    'legacy counters retain saves and last shown on upgrade and restart',
    () async {
      final lastShown = DateTime.utc(2026, 10, 17);
      SharedPreferences.setMockInitialValues({
        AdvertisingCounterStore.key: jsonEncode({
          'saves': 5,
          'lastShown': lastShown.toIso8601String(),
        }),
      });
      final h = AdHarness();
      addTearDown(h.service.dispose);
      await h.start();
      await h.event(InterstitialTrigger.save);
      expect(h.shows, 0);
      expect((await AdvertisingCounterStore().read()).events, 6);
      h.time = h.time.add(const Duration(minutes: 5));
      await h.event(InterstitialTrigger.save);
      expect(h.shows, 1);
      final restarted = AdHarness()..time = h.time;
      addTearDown(restarted.service.dispose);
      await restarted.start();
      for (var i = 0; i < 5; i++) {
        await restarted.event(InterstitialTrigger.save);
      }
      expect(restarted.shows, 0);
    },
  );

  test('denied or revoked consent never shows an interstitial', () async {
    final denied = AdHarness()..consent = false;
    addTearDown(denied.service.dispose);
    await denied.start();
    for (var i = 0; i < 5; i++) {
      await denied.event(InterstitialTrigger.newAnalysis);
    }
    expect(denied.ads, isEmpty);
    final h = AdHarness();
    addTearDown(h.service.dispose);
    await h.start();
    h.consent = false;
    await h.event(InterstitialTrigger.save);
    expect(h.shows, 0);
    h.consent = true;
    await h.event(InterstitialTrigger.save);
    expect(h.shows, 1);
  });

  test(
    'unavailable ads skip transition; loading never shows later on its own',
    () async {
      final h = AdHarness()..available = false;
      addTearDown(h.service.dispose);
      await h.start();
      for (var i = 0; i < 5; i++) {
        await h.event(InterstitialTrigger.newAnalysis);
      }
      expect(h.shows, 0);
      h.available = true;
      await h.event(InterstitialTrigger.newAnalysis);
      expect(h.shows, 0); // This event starts loading, it does not wait for it.
      await h.event(InterstitialTrigger.newAnalysis);
      expect(h.shows, 1);
    },
  );

  test(
    'concurrent events and duplicate callbacks show one ad and reset once',
    () async {
      final h = AdHarness()..hold = true;
      addTearDown(h.service.dispose);
      await h.start();
      for (var i = 0; i < 5; i++) {
        await h.service.recordSuccessfulSave();
      }
      await Future.wait(
        List.generate(
          5,
          (_) => h.service.showInterstitialIfEligible(canShow: () => true),
        ),
      );
      expect(h.shows, 1);
      await Future<void>.delayed(Duration.zero);
      expect((await AdvertisingCounterStore().read()).events, 0);
      h.ads.first.close!();
      expect(h.ads.first.disposals, 1);
    },
  );

  test(
    'UI eligibility and display failures preserve counters and availability',
    () async {
      final h = AdHarness()..failShow = true;
      addTearDown(h.service.dispose);
      await h.start();
      for (var i = 0; i < 5; i++) {
        await h.event(InterstitialTrigger.save, canShow: false);
      }
      expect(h.shows, 0);
      await h.event(InterstitialTrigger.save);
      expect((await AdvertisingCounterStore().read()).lastShown, isNull);
      expect((await AdvertisingCounterStore().read()).events, 6);
    },
  );

  testWidgets(
    'reset is immediate, empty repeat is ignored and saved prices survive',
    (tester) async {
      final ads = FakeAdvertising();
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(
          aiClient: fixture.Client([fixture.plan()]),
        ),
      );
      addTearDown(notifier.dispose);
      await tester.runAsync(() async {
        await notifier.analyzeShoppingPrompt('Acqua 1,5 litri a 0,75 euro');
        await notifier.saveCurrentPrice();
      });
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString('verified_price_observations_v1');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AdvertisingService>.value(value: ads),
            ChangeNotifierProvider.value(value: notifier),
          ],
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuova analisi'));
      expect(notifier.plannerAnalysis, isNull);
      expect(notifier.comparablePrice, isNull);
      await tester.pumpAndSettle();
      expect(ads.newAnalyses, 1);
      await tester.tap(find.text('Nuova analisi'));
      await tester.pumpAndSettle();
      expect(ads.newAnalyses, 1);
      expect(prefs.getString('verified_price_observations_v1'), before);
    },
  );

  testWidgets(
    'completions, corrections, pending questions and AI requests offer no ads',
    (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      final completion = fixture.paper()..['intent'] = 'continue';
      final correction = fixture.paper()..['intent'] = 'correct';
      final client = ScriptClient([
        fixture.paper(complete: false),
        completion,
        correction,
        {'intent': 'clarify', 'question': 'Prodotto corrente o nuovo?'},
        gate.future,
      ]);
      final ads = FakeAdvertising();
      final notifier = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(aiClient: client),
      );
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AdvertisingService>.value(value: ads),
            ChangeNotifierProvider.value(value: notifier),
          ],
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt('12 rotoli 5 euro'),
      );
      await tester.pumpAndSettle();
      expect(notifier.hasPendingClarification, isTrue);
      await tester.tap(find.text('Nuova analisi'));
      await tester.pumpAndSettle();
      expect(ads.newAnalyses, 0);
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt('200 strappi'),
      );
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt('correggo il prezzo'),
      );
      expect(ads.newAnalyses, 0);
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt('quello di prima'),
      );
      expect(notifier.hasPendingClarification, isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuova analisi'));
      await tester.pumpAndSettle();
      expect(ads.newAnalyses, 0);
      late Future<void> request;
      await tester.runAsync(() async {
        request = notifier.analyzeShoppingPrompt('altro prodotto');
        while (client.requests.length < 5) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();
      await tester.tap(find.text('Nuova analisi'));
      expect(notifier.isLoading, isTrue);
      expect(ads.newAnalyses, 0);
      gate.complete(fixture.paper());
      await tester.runAsync(() => request);
      await tester.pumpAndSettle();
      expect(ads.opportunities, 0);
    },
  );

  testWidgets('a new AI request cancels an outstanding reset ad opportunity', (
    tester,
  ) async {
    final reply = Completer<Map<String, dynamic>>();
    final client = ScriptClient([fixture.plan(), reply.future]);
    final ads = DelayedAdvertising();
    final notifier = SavingsChatNotifier(
      repository: SavingsRepositoryImpl(),
      planner: QuantityPlannerRepositoryImpl(aiClient: client),
    );
    addTearDown(notifier.dispose);
    await tester.runAsync(() => notifier.analyzeShoppingPrompt('Acqua'));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AdvertisingService>.value(value: ads),
          ChangeNotifierProvider.value(value: notifier),
        ],
        child: const MaterialApp(home: SavingsCheckerPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuova analisi'));
    expect(notifier.plannerAnalysis, isNull);
    expect(ads.newAnalyses, 1);
    late Future<void> request;
    await tester.runAsync(() async {
      request = notifier.analyzeShoppingPrompt('Altro prodotto');
      while (client.requests.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    ads.recorded.complete();
    await tester.pump();
    expect(ads.opportunities, 0);
    reply.complete(fixture.plan());
    await tester.runAsync(() => request);
    await tester.pumpAndSettle();
    expect(ads.opportunities, 0);
  });
}
