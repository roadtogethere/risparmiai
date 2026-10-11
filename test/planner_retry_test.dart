import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/domain/entities/savings_failure.dart';
import 'package:risparmiai/savings_checker/data/datasources/gemini_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/presentation/models/chat_message.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';

import 'quantity_planner_test.dart' as fixture;

class TrackedClient extends MockClient {
  TrackedClient(super.handler);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.Response reply(String provider, Map<String, dynamic> plan) =>
    http.Response(
      jsonEncode(
        provider == 'gemini'
            ? {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': jsonEncode(plan)},
                      ],
                    },
                  },
                ],
              }
            : {
                'choices': [
                  {
                    'message': {'content': jsonEncode(plan)},
                  },
                ],
              },
      ),
      200,
    );

AiSavingsClient providerClient(
  String provider,
  http.Client Function() factory, {
  Duration timeout = const Duration(seconds: 30),
}) => provider == 'gemini'
    ? GeminiSavingsClient(
        apiKey: 'test-only',
        requestTimeout: timeout,
        automaticRetry: false, // Isolate the M5B.1 manual-retry contract.
        httpClientFactory: factory,
      )
    : OpenAiSavingsClient(
        apiKey: 'test-only',
        requestTimeout: timeout,
        automaticRetry: false,
        httpClientFactory: factory,
      );

SavingsChatNotifier notifier(AiSavingsClient client) => SavingsChatNotifier(
  repository: SavingsRepositoryImpl(),
  planner: QuantityPlannerRepositoryImpl(aiClient: client),
);

Iterable<ChatMessage> userMessages(SavingsChatNotifier n) =>
    n.messages.where((m) => m.sender == ChatMessageSender.user);

Future<void> expectNoWrites() async {
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getString(VerifiedPriceStore.storageKey), isNull);
  expect(prefs.getString('user_custom_categories'), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final provider in ['openai', 'gemini']) {
    test(
      '$provider timeout is recognizable and closes the owned transport',
      () async {
        final pending = Completer<http.Response>();
        final transport = TrackedClient((_) => pending.future);
        final client = providerClient(
          provider,
          () => transport,
          timeout: const Duration(milliseconds: 10),
        );
        await expectLater(
          client.analyzeProductWithCatalog('input', '{}'),
          throwsA(
            isA<SavingsFailure>().having(
              (e) => e.kind,
              'kind',
              SavingsFailureKind.timeout,
            ),
          ),
        );
        expect(transport.closed, isTrue);
        // Even a transport that ignores close cannot deliver this late result.
        pending.complete(reply(provider, fixture.plan()));
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      '$provider timeout releases loading; manual initial retry uses identical input',
      () async {
        final late = Completer<http.Response>();
        final requests = <String>[];
        final n = notifier(
          providerClient(
            provider,
            () => TrackedClient((request) {
              requests.add(request.body);
              return requests.length == 1
                  ? late.future
                  : Future.value(reply(provider, fixture.plan()));
            }),
            timeout: const Duration(milliseconds: 10),
          ),
        );
        await n.analyzeShoppingPrompt('Acqua 1,5 L 0,75 euro');
        expect(n.isLoading, isFalse);
        expect(n.plannerAnalysis, isNull);
        expect(
          n.errorMessage,
          'Il servizio sta impiegando troppo tempo a rispondere. Puoi riprovare.',
        );
        expect(n.canRetryPlannerTurn, isTrue);
        expect(requests, hasLength(1)); // No automatic retry.
        await n.retryLastPlannerTurn();
        expect(requests[1], requests[0]);
        expect(n.plannerAnalysis!.userTurns, ['Acqua 1,5 L 0,75 euro']);
        expect(n.plannerAnalysis!.revision, 1);
        expect(userMessages(n), hasLength(1));
        expect(n.errorMessage, isNull);
        expect(n.hasFailedPlannerTurn, isFalse);
        final accepted = n.plannerAnalysis;
        late.complete(reply(provider, fixture.plan(value: 99)));
        await Future<void>.delayed(Duration.zero);
        expect(n.plannerAnalysis, same(accepted));
        await expectNoWrites();
        n.dispose();
      },
    );
  }

  test(
    '503 on 500: repeated failure and retry retain context, identity and revision',
    () async {
      final requests = <String>[];
      final completed = fixture.paper();
      completed['facts'] = {
        'sheets_per_roll': fixture.fact(500, 'sheet', per: 'roll'),
      };
      final n = notifier(
        providerClient(
          'gemini',
          () => TrackedClient((request) async {
            requests.add(request.body);
            return switch (requests.length) {
              1 => reply('gemini', fixture.paper(complete: false)),
              2 || 3 => http.Response('unavailable', 503),
              _ => reply('gemini', completed),
            };
          }),
        ),
      );
      await n.analyzeShoppingPrompt('Foxy Mega, 12 rotoli, 5 euro');
      final previous = n.plannerAnalysis!;
      await n.analyzeShoppingPrompt('500');
      expect(n.plannerAnalysis, same(previous));
      expect(previous.plan.facts.containsKey('sheets_per_roll'), isFalse);
      await n.retryLastPlannerTurn();
      expect(n.canRetryPlannerTurn, isTrue);
      expect(n.isLoading, isFalse);
      expect(n.plannerAnalysis, same(previous));
      await n.retryLastPlannerTurn();
      expect(requests[2], requests[1]);
      expect(requests[3], requests[1]);
      expect(n.plannerAnalysis!.id, previous.id);
      expect(n.plannerAnalysis!.revision, previous.revision + 1);
      expect(n.plannerAnalysis!.userTurns, [
        'Foxy Mega, 12 rotoli, 5 euro',
        '500',
      ]);
      expect(userMessages(n).map((m) => m.text), [
        'Foxy Mega, 12 rotoli, 5 euro',
        '500',
      ]);
      expect(n.comparablePrice!.quantity, 6000);
      expect(n.comparablePrice!.totalPrice, 5);
      expect(n.errorMessage, isNull);
      await expectNoWrites();
      n.dispose();
    },
  );

  test(
    'reset after timeout discards retry and late response cannot overwrite new category',
    () async {
      final late = Completer<http.Response>();
      var calls = 0;
      final n = notifier(
        providerClient(
          'gemini',
          () => TrackedClient((_) {
            calls++;
            return calls == 1
                ? late.future
                : Future.value(reply('gemini', fixture.plan()));
          }),
          timeout: const Duration(milliseconds: 10),
        ),
      );
      await n.analyzeShoppingPrompt('Carta');
      n.startNewAnalysis();
      expect(n.canRetryPlannerTurn, isFalse);
      expect(n.errorMessage, isNull);
      await n.retryLastPlannerTurn();
      expect(calls, 1);
      await n.analyzeShoppingPrompt('Acqua');
      final accepted = n.plannerAnalysis!;
      late.complete(reply('gemini', fixture.paper()));
      await Future<void>.delayed(Duration.zero);
      expect(n.plannerAnalysis, same(accepted));
      expect(accepted.schema.key, 'water');
      expect(accepted.userTurns, ['Acqua']);
      expect(n.hasFailedPlannerTurn, isFalse);
      await expectNoWrites();
      n.dispose();
    },
  );

  test(
    'failed correction and retry never change a persisted revision',
    () async {
      var calls = 0;
      final n = notifier(
        providerClient(
          'openai',
          () => TrackedClient((_) async {
            calls++;
            if (calls == 2) return http.Response('unavailable', 503);
            return reply('openai', fixture.plan(value: calls == 1 ? 1.5 : 3));
          }),
        ),
      );
      await n.analyzeShoppingPrompt('Acqua');
      await n.saveCurrentPrice();
      final saved = n.plannerAnalysis!;
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString(VerifiedPriceStore.storageKey);
      await n.analyzeShoppingPrompt('Sono tre litri');
      expect(n.plannerAnalysis, same(saved));
      await n.retryLastPlannerTurn();
      expect(n.plannerAnalysis!.id, saved.id);
      expect(n.plannerAnalysis!.revision, saved.revision + 1);
      expect(n.priceSaved, isFalse);
      expect(n.canSavePrice, isTrue);
      expect(prefs.getString(VerifiedPriceStore.storageKey), before);
      expect(await const VerifiedPriceStore().read(), hasLength(1));
      n.dispose();
    },
  );

  test(
    'timeout preserves incomplete context; late failure is ignored after reset',
    () async {
      final late = Completer<http.Response>();
      var calls = 0;
      final n = notifier(
        providerClient(
          'gemini',
          () => TrackedClient((_) {
            calls++;
            return calls == 1
                ? Future.value(reply('gemini', fixture.paper(complete: false)))
                : late.future;
          }),
          timeout: const Duration(milliseconds: 10),
        ),
      );
      await n.analyzeShoppingPrompt('Carta 12 rotoli 5 euro');
      final previous = n.plannerAnalysis!;
      await n.analyzeShoppingPrompt('500');
      expect(n.plannerAnalysis, same(previous));
      expect(n.isLoading, isFalse);
      expect(n.canRetryPlannerTurn, isTrue);
      n.startNewAnalysis();
      late.completeError(StateError('late transport failure'));
      await Future<void>.delayed(Duration.zero);
      expect(n.plannerAnalysis, isNull);
      expect(n.errorMessage, isNull);
      expect(n.canRetryPlannerTurn, isFalse);
      await expectNoWrites();
      n.dispose();
    },
  );

  test(
    'a new user turn supersedes the failed attempt instead of replaying it',
    () async {
      final requests = <String>[];
      final n = notifier(
        providerClient(
          'openai',
          () => TrackedClient((request) async {
            requests.add(request.body);
            return requests.length == 1
                ? http.Response('unavailable', 503)
                : reply('openai', fixture.plan());
          }),
        ),
      );
      await n.analyzeShoppingPrompt('Primo input');
      await n.analyzeShoppingPrompt('Input sostitutivo');
      await n.retryLastPlannerTurn();
      expect(requests, hasLength(2));
      expect(n.plannerAnalysis!.userTurns, ['Input sostitutivo']);
      expect(n.canRetryPlannerTurn, isFalse);
      await expectNoWrites();
      n.dispose();
    },
  );

  testWidgets(
    'Riprova replays the failed turn once, blocks concurrent submits and clears error',
    (tester) async {
      final gate = Completer<http.Response>();
      var calls = 0;
      final n = notifier(
        providerClient(
          'openai',
          () => TrackedClient((_) {
            calls++;
            return calls == 1
                ? Future.value(http.Response('unavailable', 503))
                : gate.future;
          }),
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: n,
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.runAsync(() => n.analyzeShoppingPrompt('Acqua'));
      await tester.pump();
      expect(find.text('Riprova'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Riprova'));
        while (calls < 2) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();
      expect(n.isLoading, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Riprova'))
            .onPressed,
        isNull,
      );
      await n.retryLastPlannerTurn();
      await n.analyzeShoppingPrompt('Altro input');
      n.startNewAnalysis();
      await tester.runAsync(() async {
        gate.complete(reply('openai', fixture.plan()));
        while (n.isLoading) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();
      expect(calls, 2);
      expect(userMessages(n), hasLength(1));
      expect(n.plannerAnalysis!.userTurns, ['Acqua']);
      expect(n.errorMessage, isNull);
      expect(find.text('Riprova'), findsNothing);
      await tester.runAsync(expectNoWrites);
      await tester.pumpWidget(const SizedBox());
      n.dispose();
    },
  );
}
