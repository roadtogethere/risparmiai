import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/ai_response_parser.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_store.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';
import 'package:risparmiai/savings_checker/domain/entities/required_attribute.dart';
import 'package:risparmiai/savings_checker/presentation/models/chat_message.dart';
import 'package:risparmiai/savings_checker/presentation/widgets/recognized_facts.dart';
import 'quantity_planner_test.dart' as fixture;
import 'planner_retry_test.dart' as retry;
import 'conversational_ux_test.dart' as ux;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final complete in [true, false]) {
    testWidgets('attribution after provider failure, complete=$complete', (
      tester,
    ) async {
      var calls = 0;
      final n = retry.notifier(
        retry.providerClient(
          'gemini',
          () => retry.TrackedClient((_) async {
            calls++;
            if (calls == 1) {
              return retry.reply('gemini', fixture.paper(complete: complete));
            }
            if (calls == 3) return retry.reply('gemini', fixture.paper());
            return http.Response('unavailable', 503);
          }),
        ),
      );
      addTearDown(n.dispose);
      await ux.mount(tester, n);
      await tester.runAsync(() => n.analyzeShoppingPrompt('12 rotoli 5 euro'));
      final previous = n.plannerAnalysis!;
      await tester.runAsync(() => n.analyzeShoppingPrompt('500'));
      await tester.pumpAndSettle();
      expect(n.plannerAnalysis, same(previous));
      expect(n.comparablePrice, isNull);
      expect(n.messages.last.failed, isTrue);
      expect(n.messages.last.analysisId, previous.id);
      expect(n.messages.last.contextRevision, previous.revision);
      expect(n.messages.last.revision, isNull);
      expect(
        find.text(
          'Dati dell’ultimo tentativo elaborato, non della richiesta fallita.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Analisi 1 ·'), findsNothing);
      expect(find.text('Richiesta non riuscita'), findsOneWidget);
      await retry.expectNoWrites();
      await tester.runAsync(n.retryLastPlannerTurn);
      await tester.pumpAndSettle();
      expect(n.plannerAnalysis!.id, previous.id);
      expect(n.plannerAnalysis!.revision, 2);
      expect(n.messages.last.turnId, 2);
      expect(n.messages.last.revision, 2);
      expect(
        n.messages.where((m) => m.sender == ChatMessageSender.user),
        hasLength(2),
      );
      expect(find.textContaining('Dati dell’ultimo tentativo'), findsNothing);
      await tester.runAsync(() => n.analyzeShoppingPrompt('450'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuova analisi'));
      await tester.pumpAndSettle();
      expect(n.plannerAnalysis, isNull);
      expect(n.hasFailedPlannerTurn, isFalse);
      expect(find.byKey(const ValueKey('analysis-boundary-2')), findsOneWidget);
      await tester.runAsync(() => n.analyzeShoppingPrompt('Altro prodotto'));
      await tester.pumpAndSettle();
      expect(n.messages.last.analysisNumber, 2);
      expect(n.messages.last.analysisId, isNull);
      expect(find.byType(RecognizedFacts), findsNothing);
      expect(find.textContaining('Analisi 2 ·'), findsNothing);
      expect(n.messages.where((m) => m.analysisNumber == 1), isNotEmpty);
      await retry.expectNoWrites();
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('default tablet label and strict canonical units', () async {
    final categories = await const CategoryReferenceStore().loadCategories();
    final schema = categories.singleWhere((c) => c.key == 'dishwasher_tabs');
    expect(schema.canonicalMetric, 'tablet');
    expect(schema.requiredAttributes.single.label, 'Numero di pastiglie');
    expect(RequiredAttribute.fromJson('tabs_count').label, 'Tabs count');
    final legacy = schema.toJson();
    legacy['required_attributes'] = ['tabs_count'];
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonEncode([legacy]);
    await prefs.setString('user_custom_categories', saved);
    final effective = (await const CategoryReferenceStore().loadCategories())
        .singleWhere((c) => c.key == 'dishwasher_tabs');
    expect(effective.requiredAttributes.single.label, 'Tabs count');
    expect(effective.canonicalMetric, 'tablet');
    expect(prefs.getString('user_custom_categories'), saved);
    for (final unit in ['tablet', 'pastiglia']) {
      final payload = fixture.plan(
        key: 'dishwasher_tabs',
        metric: 'tablet',
        value: 85,
        observed: unit,
      );
      payload['category'] = {'key': 'dishwasher_tabs'};
      final analysis = await QuantityPlannerRepositoryImpl(
        aiClient: fixture.Client([payload]),
      ).analyzeTurn('85 pastiglie');
      expect(
        analysis.result.status,
        unit == 'tablet'
            ? QuantityResolutionStatus.calculable
            : QuantityResolutionStatus.rejected,
      );
      if (unit == 'tablet') {
        expect(analysis.result.quantity, 85);
      } else {
        expect(analysis.result.reason, 'incompatible_metric');
      }
    }
    expect(kSavingsSystemPrompt, contains('primary_unit è solo'));
    expect(
      kSavingsSystemPrompt,
      contains('Non sostituire tablet con pastiglia'),
    );
  });
}
