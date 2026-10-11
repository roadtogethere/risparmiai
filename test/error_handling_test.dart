import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_http_request.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/gemini_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/verified_price_store.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/data/repositories/savings_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';
import 'package:risparmiai/savings_checker/domain/entities/savings_failure.dart';
import 'package:risparmiai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'package:risparmiai/savings_checker/presentation/pages/savings_checker_page.dart';
import 'quantity_planner_test.dart' as fixture;
import 'planner_retry_test.dart' as retry;
import 'price_history_test.dart' as history;

Matcher failure(SavingsFailureKind kind) =>
    isA<SavingsFailure>().having((e) => e.kind, 'kind', kind);

AiSavingsClient client(
  String provider,
  http.Client Function() factory, {
  Duration budget = const Duration(seconds: 30),
}) => provider == 'gemini'
    ? GeminiSavingsClient(
        apiKey: 'test-only',
        httpClientFactory: factory,
        totalRequestTimeout: budget,
        retryDelay: Duration.zero,
      )
    : OpenAiSavingsClient(
        apiKey: 'test-only',
        httpClientFactory: factory,
        totalRequestTimeout: budget,
        retryDelay: Duration.zero,
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final provider in ['openai', 'gemini']) {
    for (final code in [429, 500, 502, 503, 504, 401, 403, 400]) {
      test(
        '$provider HTTP $code classification, retry cap and sanitized error',
        () async {
          var calls = 0;
          final transports = <retry.TrackedClient>[];
          final ai = client(provider, () {
            final transport = retry.TrackedClient((_) async {
              calls++;
              return http.Response('secret-provider-body', code);
            });
            transports.add(transport);
            return transport;
          });
          final expected = switch (code) {
            429 => SavingsFailureKind.rateLimited,
            500 || 502 || 503 || 504 => SavingsFailureKind.serviceUnavailable,
            401 || 403 => SavingsFailureKind.authenticationError,
            _ => SavingsFailureKind.configurationError,
          };
          try {
            await ai.analyzeProductWithCatalog('input', '{}');
            fail('Expected typed failure');
          } on SavingsFailure catch (error) {
            expect(error, failure(expected));
            expect(error.toString(), isNot(contains('secret-provider-body')));
            expect(error.message, isNot(contains('test-only')));
          }
          expect(calls, [429, 500, 502, 503, 504].contains(code) ? 2 : 1);
          expect(transports.every((t) => t.closed), isTrue);
          await retry.expectNoWrites();
        },
      );
    }

    test(
      '$provider invalid JSON is parseError with no automatic retry',
      () async {
        var calls = 0;
        final ai = client(
          provider,
          () => retry.TrackedClient((_) async {
            calls++;
            return http.Response('{broken secret-provider-body', 200);
          }),
        );
        await expectLater(
          ai.analyzeProductWithCatalog('input', '{}'),
          throwsA(failure(SavingsFailureKind.parseError)),
        );
        expect(calls, 1);
      },
    );

    test(
      '$provider network errors stay manual; no assumption of transience',
      () async {
        var calls = 0;
        final n = retry.notifier(
          client(
            provider,
            () => retry.TrackedClient((_) async {
              calls++;
              throw http.ClientException('secret URL and body');
            }),
          ),
        );
        await n.analyzeShoppingPrompt('Acqua');
        expect(n.failure, failure(SavingsFailureKind.networkError));
        expect(n.errorMessage, 'Controlla la connessione e riprova.');
        expect(n.canRetryPlannerTurn, isTrue);
        expect(calls, 1);
        await n.retryLastPlannerTurn();
        expect(calls, 2);
        expect(retry.userMessages(n), hasLength(1));
        await retry.expectNoWrites();
        n.dispose();
      },
    );

    test(
      '$provider overall budget bounds second attempt; late response ignored',
      () async {
        final late = Completer<http.Response>();
        var calls = 0;
        final n = retry.notifier(
          client(
            provider,
            () => retry.TrackedClient((_) {
              calls++;
              return calls == 1
                  ? Future.value(http.Response('busy', 503))
                  : late.future;
            }),
            budget: const Duration(milliseconds: 40),
          ),
        );
        await n.analyzeShoppingPrompt('Acqua');
        expect(calls, 2);
        expect(n.failure, failure(SavingsFailureKind.timeout));
        expect(n.isLoading, isFalse);
        n.startNewAnalysis();
        late.complete(retry.reply(provider, fixture.plan()));
        await Future<void>.delayed(Duration.zero);
        expect(n.plannerAnalysis, isNull);
        expect(n.failure, isNull);
        await retry.expectNoWrites();
        n.dispose();
      },
    );

    test('$provider missing credentials are authentication errors', () async {
      final AiSavingsClient ai = provider == 'gemini'
          ? GeminiSavingsClient()
          : OpenAiSavingsClient();
      await expectLater(
        ai.analyzeProductWithCatalog('input', '{}'),
        throwsA(failure(SavingsFailureKind.authenticationError)),
      );
    });
  }

  test('Retry-After parses seconds and HTTP dates', () {
    final now = DateTime.utc(2026, 10, 11, 12);
    expect(parseRetryAfter('2', now), const Duration(seconds: 2));
    expect(
      parseRetryAfter('Sun, 11 Oct 2026 12:00:05 GMT', now),
      const Duration(seconds: 5),
    );
    expect(
      parseRetryAfter('Sun, 11 Oct 2026 11:59:00 GMT', now),
      Duration.zero,
    );
    expect(parseRetryAfter('invalid', now), isNull);
  });

  testWidgets(
    'positive Retry-After is honored before the only automatic retry',
    (tester) async {
      var calls = 0;
      final ai = client(
        'openai',
        () => retry.TrackedClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('busy', 429, headers: {'retry-after': '1'})
              : retry.reply('openai', fixture.plan());
        }),
      );
      final result = ai.analyzeProductWithCatalog('input', '{}');
      await tester.pump();
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 999));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
      expect((await result)['status'], 'sufficient');
    },
  );

  test('Retry-After beyond budget stops safely with manual recovery', () async {
    var calls = 0;
    final n = retry.notifier(
      client(
        'openai',
        () => retry.TrackedClient((_) async {
          calls++;
          return http.Response('busy', 429, headers: {'retry-after': '120'});
        }),
        budget: const Duration(milliseconds: 50),
      ),
    );
    await n.analyzeShoppingPrompt('Acqua');
    expect(calls, 1);
    expect(n.failure, failure(SavingsFailureKind.rateLimited));
    expect(n.canRetryPlannerTurn, isTrue);
    expect(n.isLoading, isFalse);
    await retry.expectNoWrites();
    n.dispose();
  });

  test(
    'automatic retry reuses same payload, then manual retry completes 500 once',
    () async {
      final bodies = <String>[];
      final completed = fixture.paper();
      completed['facts'] = {
        'sheets_per_roll': fixture.fact(500, 'sheet', per: 'roll'),
      };
      final n = retry.notifier(
        client(
          'gemini',
          () => retry.TrackedClient((request) async {
            bodies.add(request.body);
            return switch (bodies.length) {
              1 => retry.reply('gemini', fixture.paper(complete: false)),
              2 || 3 => http.Response('busy', 503),
              _ => retry.reply('gemini', completed),
            };
          }),
        ),
      );
      await n.analyzeShoppingPrompt('Carta 12 rotoli 5 euro');
      final previous = n.plannerAnalysis!;
      await n.analyzeShoppingPrompt('500');
      expect(n.plannerAnalysis, same(previous));
      expect(n.failure, failure(SavingsFailureKind.serviceUnavailable));
      await n.retryLastPlannerTurn();
      expect(bodies[2], bodies[1]);
      expect(bodies[3], bodies[1]);
      expect(n.plannerAnalysis!.id, previous.id);
      expect(n.plannerAnalysis!.revision, previous.revision + 1);
      expect(n.plannerAnalysis!.userTurns, ['Carta 12 rotoli 5 euro', '500']);
      expect(retry.userMessages(n), hasLength(2));
      expect(n.comparablePrice!.quantity, 6000);
      expect(n.failure, isNull);
      await retry.expectNoWrites();
      n.dispose();
    },
  );

  test('automatic retry can succeed without a duplicate user turn', () async {
    var calls = 0;
    final n = retry.notifier(
      client(
        'openai',
        () => retry.TrackedClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('busy', 429, headers: {'retry-after': '0'})
              : retry.reply('openai', fixture.plan());
        }),
      ),
    );
    await n.analyzeShoppingPrompt('Acqua');
    expect(calls, 2);
    expect(n.failure, isNull);
    expect(n.plannerAnalysis!.revision, 1);
    expect(retry.userMessages(n), hasLength(1));
    await retry.expectNoWrites();
    n.dispose();
  });

  test(
    'provider not configured is a configuration error, never a demo',
    () async {
      final n = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(aiClient: null),
      );
      await n.analyzeShoppingPrompt('Acqua');
      expect(n.failure, failure(SavingsFailureKind.configurationError));
      expect(n.analyzedProducts, isEmpty);
      expect(n.canRetryPlannerTurn, isTrue);
      await retry.expectNoWrites();
      n.dispose();
    },
  );

  testWidgets(
    'corrupt history is a visible local error before AI and is not reset',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        VerifiedPriceStore.storageKey: '{broken',
      });
      final ai = fixture.Client([fixture.plan()]);
      final n = retry.notifier(ai);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: n,
          child: const MaterialApp(home: SavingsCheckerPage()),
        ),
      );
      await tester.runAsync(() => n.analyzeShoppingPrompt('Acqua'));
      await tester.pump();
      expect(ai.requests, isEmpty);
      expect(n.failure, failure(SavingsFailureKind.storageError));
      expect(
        find.text('Non riesco a leggere o salvare i prezzi sul dispositivo.'),
        findsOneWidget,
      );
      expect(find.text('Riprova'), findsOneWidget);
      expect(n.comparablePrice, isNull);
      await tester.runAsync(n.retryLastPlannerTurn);
      expect(ai.requests, isEmpty);
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getString(VerifiedPriceStore.storageKey), '{broken');
      await tester.pumpWidget(const SizedBox());
      n.dispose();
    },
  );

  test(
    'failed write is storageError without saved success; explicit retry remains',
    () async {
      final disk = history.DelayedHistory()..fail = true;
      disk.gate.complete();
      final n = SavingsChatNotifier(
        repository: SavingsRepositoryImpl(),
        planner: QuantityPlannerRepositoryImpl(
          aiClient: fixture.Client([fixture.plan()]),
        ),
        priceHistory: disk,
      );
      await n.analyzeShoppingPrompt('Acqua');
      await n.saveCurrentPrice();
      expect(n.failure, failure(SavingsFailureKind.storageError));
      expect(n.saveMessage, contains('Non riesco a leggere o salvare'));
      expect(n.priceSaved, isFalse);
      expect(n.canSavePrice, isTrue);
      disk.fail = false;
      await n.saveCurrentPrice();
      expect(n.failure, isNull);
      expect(n.priceSaved, isTrue);
      n.dispose();
    },
  );

  test(
    'zero descriptors survive calculation and explicit persistence',
    () async {
      final plan = fixture.plan();
      plan['facts']['sugar'] = fixture.fact(0, 'gram');
      plan['facts']['fat'] = fixture.fact(0, 'gram');
      final n = retry.notifier(fixture.Client([plan]));
      await n.analyzeShoppingPrompt('Acqua, zero zuccheri e grassi');
      expect(n.comparablePrice!.unitCost, 0.75 / 1.5);
      expect(n.failure, isNull);
      await retry.expectNoWrites();
      await n.saveCurrentPrice();
      final saved = (await const VerifiedPriceStore().read()).single;
      expect(saved.price.analysis.plan.facts['sugar']!.value, 0);
      expect(saved.price.analysis.plan.facts['fat']!.value, 0);
      n.dispose();
    },
  );

  for (final value in [0.0, -5.0]) {
    test('operand $value stays invalid in direct and multiply', () {
      expect(
        fixture.resolve(fixture.plan(value: value)).status,
        QuantityResolutionStatus.rejected,
      );
      final paper = fixture.paper();
      paper['facts']['rolls_count'] = fixture.fact(value, 'roll');
      expect(fixture.resolve(paper).status, QuantityResolutionStatus.rejected);
    });
  }

  test(
    'negative or nonfinite descriptors remain invalid without semantic exceptions',
    () {
      for (final value in [-1.0, double.nan, double.infinity]) {
        final plan = fixture.plan();
        plan['facts']['description'] = fixture.fact(value, 'gram');
        expect(fixture.resolve(plan).status, QuantityResolutionStatus.rejected);
      }
    },
  );

  test(
    'incomplete and rejected domain plans are not technical failures or auto retries',
    () async {
      for (final plan in [
        fixture.paper(complete: false),
        fixture.plan(value: 0),
      ]) {
        var calls = 0;
        final n = retry.notifier(
          client(
            'openai',
            () => retry.TrackedClient((_) async {
              calls++;
              return retry.reply('openai', plan);
            }),
          ),
        );
        await n.analyzeShoppingPrompt('Prodotto');
        expect(calls, 1);
        expect(n.failure, isNull);
        expect(n.canRetryPlannerTurn, isFalse);
        expect(n.canSavePrice, isFalse);
        await retry.expectNoWrites();
        n.dispose();
      }
    },
  );
}
