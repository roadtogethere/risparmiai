import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'package:risparmiai/savings_checker/data/models/quantity_plan_parser.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';
import 'package:risparmiai/savings_checker/domain/entities/savings_failure.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';

import 'quantity_planner_test.dart' as fixture;

// All intentions and plans are simulated; no remote classification is performed.
Map<String, dynamic> product(String key, double grams, double price) {
  final plan = fixture.plan(
    key: key,
    metric: 'kilogram',
    type: 'convert',
    observed: 'gram',
    value: grams,
  );
  plan['intent'] = 'new_product';
  plan['facts']['price'] = fixture.fact(price, 'EUR');
  return plan;
}

class ScriptClient implements AiSavingsClient {
  ScriptClient(this.replies);
  final List<Object> replies;
  final List<String> requests = [];
  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String prompt,
    String catalog,
  ) async {
    requests.add(prompt);
    final reply = replies.removeAt(0);
    if (reply is Future<Map<String, dynamic>>) return await reply;
    if (reply is Map<String, dynamic>) return reply;
    throw reply;
  }
}

SavingsChatNotifier notifier(AiSavingsClient client) => SavingsChatNotifier(
  repository: SavingsRepositoryImpl(useMockData: true),
  planner: QuantityPlannerRepositoryImpl(aiClient: client),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final sameCategory in [false, true]) {
    test(
      'new product resets identity and facts, same category=$sameCategory',
      () async {
        final firstPlan = product(sameCategory ? 'biscuits' : 'crisps', 150, 2);
        firstPlan['facts']['old_descriptor'] = fixture.fact(4, 'layer');
        final client = ScriptClient([firstPlan, product('biscuits', 500, 3)]);
        final chat = notifier(client);
        addTearDown(chat.dispose);
        await chat.analyzeShoppingPrompt(
          sameCategory ? 'Biscotti 150 g, 2 €' : 'Patatine 150 g, 2 €',
        );
        final old = chat.plannerAnalysis!;
        await chat.analyzeShoppingPrompt('Biscotti 500 g, 3 €');
        final next = chat.plannerAnalysis!;
        expect(next.id, isNot(old.id));
        expect(next.revision, 1);
        expect(next.schema.key, 'biscuits');
        expect(next.plan.facts.containsKey('old_descriptor'), isFalse);
        expect(next.userTurns, ['Biscotti 500 g, 3 €']);
        expect(chat.comparablePrice!.quantity, 0.5);
        expect(chat.comparablePrice!.totalPrice, 3);
        expect(chat.analysisNumber, 2);
        expect(chat.messages.last.analysisId, next.id);
        expect(chat.messages[2].analysisNumber, 2);
        expect(chat.messages[2].contextRevision, isNull);
        expect(await const VerifiedPriceStore().read(), isEmpty);
      },
    );
  }

  test(
    'continue 500 sheets and correct 450 preserve identity and price',
    () async {
      final complete = fixture.paper();
      complete['intent'] = 'continue';
      complete['facts']['sheets_per_roll']['value'] = 500;
      final correction = fixture.paper();
      correction['intent'] = 'correct';
      correction['facts'] = {
        'sheets_per_roll': fixture.fact(450, 'sheet', per: 'roll'),
      };
      final chat = notifier(
        ScriptClient([fixture.paper(complete: false), complete, correction]),
      );
      addTearDown(chat.dispose);
      await chat.analyzeShoppingPrompt('Carta igienica 12 rotoli 5 euro');
      final id = chat.plannerAnalysis!.id;
      await chat.analyzeShoppingPrompt('500 strappi');
      expect(chat.plannerAnalysis!.id, id);
      expect(chat.comparablePrice!.quantity, 6000);
      await chat.analyzeShoppingPrompt('No, sono 450');
      expect(chat.plannerAnalysis!.id, id);
      expect(chat.plannerAnalysis!.revision, 3);
      expect(chat.plannerAnalysis!.intent, ConversationIntent.correct);
      expect(chat.comparablePrice!.quantity, 5400);
      expect(chat.comparablePrice!.totalPrice, 5);
      expect(chat.analysisNumber, 1);
    },
  );

  test(
    'clarify preserves saved analysis and carries question into next request',
    () async {
      final client = ScriptClient([
        product('biscuits', 150, 2),
        {'intent': 'clarify', 'question': 'È una nuova confezione?'},
        product('biscuits', 500, 3),
      ]);
      final chat = notifier(client);
      addTearDown(chat.dispose);
      await chat.analyzeShoppingPrompt('Biscotti 150 g, 2 €');
      await chat.saveCurrentPrice();
      final old = chat.plannerAnalysis;
      final price = chat.comparablePrice;
      final snapshot = (await SharedPreferences.getInstance()).getString(
        'verified_price_observations_v1',
      );
      await chat.analyzeShoppingPrompt('Quelli da 500');
      expect(identical(chat.plannerAnalysis, old), isTrue);
      expect(identical(chat.comparablePrice, price), isTrue);
      expect(chat.priceSaved, isTrue);
      expect(chat.failure, isNull);
      expect(chat.hasFailedPlannerTurn, isFalse);
      expect(chat.messages.last.text, 'È una nuova confezione?');
      await chat.analyzeShoppingPrompt(
        'Sì, una nuova confezione da 500 g a 3 euro',
      );
      expect(jsonDecode(client.requests.last)['clarification_turns'], [
        {'role': 'user', 'text': 'Quelli da 500'},
        {'role': 'assistant', 'text': 'È una nuova confezione?'},
      ]);
      expect(chat.plannerAnalysis!.id, isNot(old!.id));
      expect(chat.priceSaved, isFalse);
      expect(chat.saveMessage, isNull);
      expect(chat.canSavePrice, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'verified_price_observations_v1',
        ),
        snapshot,
      );
    },
  );

  test(
    'new product cannot inherit missing price or old canonical metric',
    () async {
      final next = product('drink', 500, 3);
      next['category']['proposal']['canonical_metric'] = 'liter';
      next['facts']['quantity']['unit'] = 'milliliter';
      next['facts'].remove('price');
      final chat = notifier(ScriptClient([product('crisps', 150, 2), next]));
      addTearDown(chat.dispose);
      await chat.analyzeShoppingPrompt('Patatine 150 g 2 euro');
      await chat.analyzeShoppingPrompt('Una bevanda da 500 ml');
      expect(chat.plannerAnalysis!.schema.canonicalMetric, 'liter');
      expect(chat.plannerAnalysis!.result.missing, ['price']);
      expect(chat.plannerAnalysis!.plan.facts.containsKey('price'), isFalse);
      expect(chat.comparablePrice, isNull);
    },
  );

  test(
    'provider failure and retry replay transition once without saving',
    () async {
      final client = ScriptClient([
        product('crisps', 150, 2),
        const SavingsFailure(SavingsFailureKind.networkError),
        product('biscuits', 500, 3),
      ]);
      final chat = notifier(client);
      addTearDown(chat.dispose);
      await chat.analyzeShoppingPrompt('Patatine 150 g 2 euro');
      final old = chat.plannerAnalysis!;
      await chat.analyzeShoppingPrompt('Biscotti 500 g 3 euro');
      expect(chat.plannerAnalysis!.id, old.id);
      expect(chat.canRetryPlannerTurn, isTrue);
      await chat.retryLastPlannerTurn();
      expect(client.requests[1], client.requests[2]);
      expect(chat.plannerAnalysis!.id, isNot(old.id));
      expect(chat.plannerAnalysis!.revision, 1);
      expect(chat.analysisNumber, 2);
      expect(chat.hasFailedPlannerTurn, isFalse);
      expect(await const VerifiedPriceStore().read(), isEmpty);
      final count = chat.messages.length;
      await chat.retryLastPlannerTurn();
      expect(chat.messages.length, count);
    },
  );

  test(
    'explicit reset after failed transition clears retry and old context',
    () async {
      final client = ScriptClient([
        product('crisps', 150, 2),
        const SavingsFailure(SavingsFailureKind.networkError),
        product('biscuits', 500, 3),
      ]);
      final chat = notifier(client);
      addTearDown(chat.dispose);
      await chat.analyzeShoppingPrompt('Patatine');
      await chat.analyzeShoppingPrompt('Biscotti');
      chat.startNewAnalysis();
      expect(chat.plannerAnalysis, isNull);
      expect(chat.hasFailedPlannerTurn, isFalse);
      await chat.retryLastPlannerTurn();
      expect(client.requests.length, 2);
      await chat.analyzeShoppingPrompt('Biscotti 500 g 3 euro');
      expect(
        jsonDecode(client.requests.last).containsKey('current_analysis'),
        isFalse,
      );
    },
  );

  test('late reply after disposal cannot activate a transition', () async {
    final pending = Completer<Map<String, dynamic>>();
    final chat = notifier(
      ScriptClient([product('crisps', 150, 2), pending.future]),
    );
    await chat.analyzeShoppingPrompt('Patatine');
    final old = chat.plannerAnalysis;
    final work = chat.analyzeShoppingPrompt('Biscotti');
    await Future<void>.delayed(Duration.zero);
    chat.dispose();
    pending.complete(product('biscuits', 500, 3));
    await work;
    expect(identical(chat.plannerAnalysis, old), isTrue);
  });

  test('strict intent parsing and minimal clarification envelope', () {
    expect(
      QuantityPlanParser.decode(
        '{"intent":"clarify","question":"Nuovo prodotto?"}',
      )['intent'],
      'clarify',
    );
    expect(
      () => QuantityPlanParser.decode(
        '{"intent":"clarify","question":"?","facts":{}}',
      ),
      throwsFormatException,
    );
    expect(
      () => QuantityPlanParser.parse(
        product('biscuits', 500, 3)..['intent'] = 'guess',
      ),
      throwsFormatException,
    );
  });

  test(
    'initial ambiguity creates no analysis and explicit reset drops clarification',
    () async {
      final client = ScriptClient([
        {'intent': 'clarify', 'question': 'Quale prodotto vuoi analizzare?'},
        product('biscuits', 500, 3),
      ]);
      final chat = notifier(client);
      addTearDown(chat.dispose);
      await chat.analyzeShoppingPrompt('Quelli grandi');
      expect(chat.plannerAnalysis, isNull);
      expect(chat.comparablePrice, isNull);
      expect(chat.failure, isNull);
      expect(chat.messages.last.text, 'Quale prodotto vuoi analizzare?');
      chat.startNewAnalysis();
      await chat.analyzeShoppingPrompt('Biscotti 500 g 3 euro');
      expect(
        jsonDecode(client.requests.last).containsKey('clarification_turns'),
        isFalse,
      );
      expect(chat.plannerAnalysis!.revision, 1);
    },
  );
}
