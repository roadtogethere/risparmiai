import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/main.dart';
import 'package:risparmiai/savings_checker/data/datasources/gemini_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';

import 'conversation_intent_test.dart' as intents;
import 'planner_retry_test.dart' as transport;

// Real Gemini client/envelope/parser; HTTP replies are simulated, never remote.
Future<SavingsChatNotifier> mount(
  WidgetTester tester,
  List<Map<String, dynamic>> replies,
) async {
  await tester.pumpWidget(
    MainApp(
      useMockData: false,
      aiClient: GeminiSavingsClient(
        apiKey: 'test-only',
        httpClientFactory: () => MockClient(
          (_) async => transport.reply('gemini', replies.removeAt(0)),
        ),
      ),
    ),
  );
  return tester
      .element(find.byType(SavingsCheckerPage))
      .read<SavingsChatNotifier>();
}

Map<String, dynamic> product(String key, double grams, double price) {
  final plan = intents.product(key, grams, price);
  plan['category']['proposal']['display_name'] = key == 'biscuits'
      ? 'Biscotti'
      : 'Patatine';
  return plan;
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Salva questo prezzo');
  await tester.ensureVisible(button);
  await tester.runAsync(() async {
    await tester.tap(button);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'missing live intent cannot update biscuits with crisps price or save it',
    (tester) async {
      // A sufficient response with correct numbers but old category and no intent
      // previously became revision 2 of biscuits and could be saved at 2.50 EUR/kg.
      final stale = product('biscuits', 400, 1)..remove('intent');
      stale['category'] = {'key': 'biscuits'};
      final chat = await mount(tester, [product('biscuits', 600, 3), stale]);
      await tester.runAsync(
        () => chat.analyzeShoppingPrompt('biscotti 3 euro 600 g'),
      );
      final old = chat.plannerAnalysis!;
      await tester.runAsync(
        () => chat.analyzeShoppingPrompt('patatine 400 g 1 euro'),
      );
      await tester.pumpAndSettle();
      expect(chat.canSavePrice, isFalse);
      expect(chat.comparablePrice, isNull);
      expect(chat.plannerAnalysis!.id, old.id);
      expect(chat.plannerAnalysis!.revision, old.revision);
      await tester.runAsync(chat.saveCurrentPrice);
      expect(
        await tester.runAsync(() => const VerifiedPriceStore().read()),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final reverse in [false, true]) {
    for (final alreadySaved in [false, true]) {
      testWidgets(
        'Gemini to card to saved category, reverse=$reverse saved=$alreadySaved',
        (tester) async {
          final firstKey = reverse ? 'crisps' : 'biscuits';
          final nextKey = reverse ? 'biscuits' : 'crisps';
          final first = product(firstKey, 600, 3);
          first['facts']['old_descriptor'] = {
            'value': 9,
            'unit': 'layer',
            'source': 'user_input',
          };
          final chat = await mount(tester, [first, product(nextKey, 400, 1)]);
          await tester.runAsync(
            () => chat.analyzeShoppingPrompt(
              reverse ? 'patatine 3 euro 600 g' : 'biscotti 3 euro 600 g',
            ),
          );
          await tester.pumpAndSettle();
          final oldId = chat.plannerAnalysis!.id;
          if (alreadySaved) await save(tester);
          await tester.runAsync(
            () => chat.analyzeShoppingPrompt(
              reverse ? 'biscotti 400 g 1 euro' : 'patatine 400 g 1 euro',
            ),
          );
          await tester.pumpAndSettle();
          expect(chat.plannerAnalysis!.id, isNot(oldId));
          expect(chat.plannerAnalysis!.revision, 1);
          expect(chat.plannerAnalysis!.schema.key, nextKey);
          expect(
            chat.plannerAnalysis!.plan.facts.containsKey('old_descriptor'),
            isFalse,
          );
          expect(chat.priceSaved, isFalse);
          expect(chat.comparablePrice!.unitCost, 2.5);
          expect(
            find.text('Categoria: ${reverse ? 'Biscotti' : 'Patatine'}'),
            findsOneWidget,
          );
          expect(find.text('2,5 €/kilogram'), findsOneWidget);
          var stored = await tester.runAsync(
            () => const VerifiedPriceStore().read(),
          );
          expect(stored!.length, alreadySaved ? 1 : 0);
          await save(tester);
          stored = await tester.runAsync(
            () => const VerifiedPriceStore().read(),
          );
          expect(stored!.length, alreadySaved ? 2 : 1);
          final saved = stored.last.price;
          expect(saved.categoryKey, nextKey);
          expect(saved.analysis.id, chat.plannerAnalysis!.id);
          expect(saved.quantity, 0.4);
          expect(saved.totalPrice, 1);
          expect(saved.unitCost, 2.5);
          final raw = (await SharedPreferences.getInstance()).getString(
            'verified_price_observations_v1',
          )!;
          expect(
            jsonDecode(raw)['observations'].last['plan']['category']['key'],
            nextKey,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'two biscuit products get distinct identities and saved observations',
    (tester) async {
      final chat = await mount(tester, [
        product('biscuits', 600, 3),
        product('biscuits', 400, 1),
      ]);
      await tester.runAsync(
        () => chat.analyzeShoppingPrompt('biscotti 3 euro 600 g'),
      );
      await tester.pumpAndSettle();
      final oldId = chat.plannerAnalysis!.id;
      await save(tester);
      await tester.runAsync(
        () => chat.analyzeShoppingPrompt(
          'Altri biscotti, confezione da 400 g a 1 euro',
        ),
      );
      await tester.pumpAndSettle();
      expect(chat.plannerAnalysis!.id, isNot(oldId));
      expect(chat.priceSaved, isFalse);
      expect(find.text('Categoria: Biscotti'), findsOneWidget);
      await save(tester);
      final stored = await tester.runAsync(
        () => const VerifiedPriceStore().read(),
      );
      expect(stored!.length, 2);
      expect(stored.map((s) => s.price.categoryKey), everyElement('biscuits'));
      expect(stored.map((s) => s.price.analysis.id).toSet().length, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ambiguous switch disables saving until the planner resolves it',
    (tester) async {
      final chat = await mount(tester, [
        product('biscuits', 600, 3),
        {
          'intent': 'clarify',
          'question': 'Un nuovo prodotto o una correzione?',
        },
        product('crisps', 400, 1),
      ]);
      await tester.runAsync(
        () => chat.analyzeShoppingPrompt('biscotti 3 euro 600 g'),
      );
      final old = chat.plannerAnalysis;
      await tester.runAsync(() => chat.analyzeShoppingPrompt('Quelli da 400'));
      await tester.pumpAndSettle();
      expect(identical(chat.plannerAnalysis, old), isTrue);
      expect(chat.canSavePrice, isFalse);
      await tester.runAsync(chat.saveCurrentPrice);
      expect(
        await tester.runAsync(() => const VerifiedPriceStore().read()),
        isEmpty,
      );
      await tester.runAsync(
        () => chat.analyzeShoppingPrompt(
          'Un altro prodotto: patatine 400 g a 1 euro',
        ),
      );
      await tester.pumpAndSettle();
      expect(chat.canSavePrice, isTrue);
      expect(find.text('Categoria: Patatine'), findsOneWidget);
      await save(tester);
      final stored = await tester.runAsync(
        () => const VerifiedPriceStore().read(),
      );
      expect(stored!.single.price.categoryKey, 'crisps');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
