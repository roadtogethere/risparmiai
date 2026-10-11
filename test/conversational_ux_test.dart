import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/main.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_store.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/presentation/models/analysis_display.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';
import 'quantity_planner_test.dart' as fixture;

Map<String, dynamic> paper(int sheets, {bool complete = true}) {
  final result = fixture.paper(complete: complete);
  result['facts']['plies_count'] = fixture.fact(3, 'ply');
  if (complete) {
    result['facts']['sheets_per_roll'] = fixture.fact(
      sheets,
      'sheet',
      per: 'roll',
    );
  }
  return result;
}

SavingsChatNotifier notifierFor(List<Map<String, dynamic>> responses) =>
    SavingsChatNotifier(
      repository: SavingsRepositoryImpl(),
      planner: QuantityPlannerRepositoryImpl(
        aiClient: fixture.Client(responses),
        categoryStore: CategoryReferenceStore(
          defaultDataSource: fixture.Defaults([fixture.paperSchema]),
        ),
      ),
    );

Future<void> mount(
  WidgetTester tester,
  SavingsChatNotifier notifier, {
  bool large = false,
}) => tester.pumpWidget(
  ChangeNotifierProvider.value(
    value: notifier,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(large ? 2 : 1),
          viewInsets: EdgeInsets.only(bottom: large ? 230 : 0),
        ),
        child: child!,
      ),
      home: const SavingsCheckerPage(),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final tablets = fixture.plan(
    key: 'dishwasher_tabs',
    metric: 'tablet',
    value: 85,
  );
  tablets['category'] = {'key': 'dishwasher_tabs'};
  tablets['facts']['price'] = fixture.fact(12, 'EUR');
  final water = fixture.plan(
    type: 'convert',
    value: 500,
    observed: 'milliliter',
  );
  water['facts']['price'] = fixture.fact(0.4, 'EUR');
  water['category']['proposal']['primary_unit'] = 'L';

  for (final scenario in [
    (
      input: '85 pastiglie, 12 euro',
      payload: tablets,
      quantity: 85.0,
      metric: 'tablet',
      cost: 12 / 85,
      display: '0,1412 €/pastiglia',
    ),
    (
      input: '12 rotoli, 200 strappi per rotolo, 5 euro',
      payload: fixture.paper(),
      quantity: 2400.0,
      metric: 'sheet',
      cost: 5 / 2400,
      display: '0,002083 €/strappo',
    ),
    (
      input: '500 ml, 40 centesimi',
      payload: water,
      quantity: 0.5,
      metric: 'liter',
      cost: 0.8,
      display: '0,8 €/L',
    ),
  ]) {
    testWidgets('M5C.1 input to economic card: ${scenario.input}', (
      tester,
    ) async {
      final client = fixture.Client([scenario.payload]);
      await tester.pumpWidget(MainApp(useMockData: false, aiClient: client));
      final notifier = tester
          .element(find.byType(SavingsCheckerPage))
          .read<SavingsChatNotifier>();
      await tester.enterText(find.byType(TextField), scenario.input);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Invia'));
        while (notifier.isLoading) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      expect(client.requests.single['user_turns'], [scenario.input]);
      expect(notifier.errorMessage, isNull);
      final price = notifier.comparablePrice!;
      expect(price.quantity, scenario.quantity);
      expect(price.canonicalMetric, scenario.metric);
      expect(price.unitCost, scenario.cost);
      final costText = find.text(scenario.display);
      await tester.ensureVisible(costText);
      expect(costText.hitTestable(), findsOneWidget);
      expect(find.textContaining('convenienza non valutabile'), findsOneWidget);
      expect(notifier.priceComparison!.count, 0);
      expect(notifier.priceComparison!.isPotentialNewMinimum, isFalse);
      expect(
        await tester.runAsync(() => const VerifiedPriceStore().read()),
        isEmpty,
      );
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getString(VerifiedPriceStore.storageKey), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('incomplete facts use schema labels and preserve descriptors', (
    tester,
  ) async {
    final notifier = notifierFor([paper(500, complete: false)]);
    addTearDown(notifier.dispose);
    await tester.runAsync(
      () => notifier.analyzeShoppingPrompt('12 rotoli 5 euro 3 veli'),
    );
    await mount(tester, notifier);
    expect(find.text('Prezzo totale: 5 €'), findsOneWidget);
    expect(find.textContaining('Rotoli: 12 rotoli'), findsOneWidget);
    expect(find.text('Plies count: 3 veli'), findsOneWidget);
    expect(find.textContaining('rolls_count'), findsNothing);
    expect(
      find.textContaining('Puoi correggere i dati in chat'),
      findsOneWidget,
    );
    expect(find.text('Salva questo prezzo'), findsNothing);
  });

  testWidgets(
    'correction updates same product; next same-category product resets only current state',
    (tester) async {
      final notifier = notifierFor([paper(500), paper(450), fixture.paper()]);
      addTearDown(notifier.dispose);
      await mount(tester, notifier);
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt('12 rotoli 500 strappi 5 euro'),
      );
      await tester.pump();
      final id = notifier.plannerAnalysis!.id;
      expect(find.text('Circa 0,83 € ogni 1.000 strappi'), findsOneWidget);
      expect(find.textContaining('convenienza non valutabile'), findsOneWidget);
      expect(find.text('Migliore convenienza'), findsNothing);
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt('Scusa, sono 450 strappi'),
      );
      await tester.pump();
      expect(notifier.plannerAnalysis!.id, id);
      expect(find.text('Dati aggiornati'), findsOneWidget);
      expect(find.text('Quantità comparabile: 5.400 strappo'), findsOneWidget);
      expect(
        await tester.runAsync(() => const VerifiedPriceStore().read()),
        isEmpty,
      );
      await tester.ensureVisible(find.text('Salva questo prezzo'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Salva questo prezzo'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(notifier.priceSaved, isTrue);
      final saved = await tester.runAsync(
        () => const VerifiedPriceStore().read(),
      );
      expect(saved, hasLength(1));
      expect(saved!.single.price.unitCost, 5 / 5400);
      expect(notifier.comparablePrice!.unitCost, 5 / 5400);
      await tester.enterText(find.byType(TextField), 'bozza');
      await tester.tap(find.text('Nuova analisi'));
      await tester.pumpAndSettle();
      expect(notifier.plannerAnalysis, isNull);
      expect(notifier.priceSaved, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Nuovo prodotto · analisi 2'), findsOneWidget);
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt(
          'Altro prodotto 12 rotoli 200 strappi 5 euro',
        ),
      );
      await tester.pump();
      expect(notifier.plannerAnalysis!.id, isNot(id));
      expect(
        notifier.plannerAnalysis!.plan.facts.containsKey('plies_count'),
        isFalse,
      );
      expect(notifier.priceSaved, isFalse);
      expect(notifier.priceComparison!.count, 1);
      expect(
        await tester.runAsync(() => const VerifiedPriceStore().read()),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'small mobile, keyboard, large text and many facts remain scrollable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final response = paper(500);
      for (var i = 0; i < 20; i++) {
        response['facts']['descrizione_lunga_$i'] = fixture.fact(i, 'count');
      }
      final notifier = notifierFor([response]);
      addTearDown(notifier.dispose);
      await tester.runAsync(
        () => notifier.analyzeShoppingPrompt(
          List.filled(60, 'prodotto').join(' '),
        ),
      );
      await mount(tester, notifier, large: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Nuova analisi').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Invia').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Salva questo prezzo'));
      await tester.pumpAndSettle();
      expect(find.text('Salva questo prezzo').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('conversation')),
        const Offset(0, 250),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mock mode has a persistent explicit simulation banner', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp(useMockData: true));
    expect(find.text('Modalità demo — dati simulati'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Carta');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.text('Modalità demo — dati simulati').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Salva questo prezzo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'Italian display preserves tiny costs without scaling physical or unknown units',
    () {
      expect(AnalysisDisplay.amount(5 / 6000), '0,000833');
      expect(AnalysisDisplay.amount(6000), '6.000');
      expect(AnalysisDisplay.amount(1e-9), isNot('0'));
      expect(
        AnalysisDisplay.scaledCost(.000833, 'sheet'),
        'Circa 0,83 € ogni 1.000 strappi',
      );
      expect(AnalysisDisplay.scaledCost(.000833, 'liter'), isNull);
      expect(AnalysisDisplay.scaledCost(.000833, 'custom_unit'), isNull);
      expect(
        AnalysisDisplay.label('customAttribute_name'),
        'Custom Attribute name',
      );
    },
  );
}
