// Opt-in: RUN_LIVE_PLANNER=1 flutter test test/live_planner_test.dart
// Keys are read locally; no credentials or raw provider responses are printed.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risparmiai/savings_checker/data/datasources/gemini_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/repositories/quantity_planner_repository_impl.dart';
import 'package:risparmiai/savings_checker/domain/entities/quantity_plan.dart';

class _LiveBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _LiveBinding();
  for (final provider in ['gemini', 'openai']) {
    test(
      'live $provider retains facts, completes 500, and corrects price',
      () async {
        if (File('.env').existsSync()) {
          dotenv.testLoad(fileInput: File('.env').readAsStringSync());
        }
        final name = provider == 'gemini' ? 'GEMINI_API_KEY' : 'OPENAI_API_KEY';
        final key =
            Platform.environment[name] ??
            (dotenv.isInitialized ? dotenv.env[name] : null);
        if (key == null || key.trim().isEmpty) {
          markTestSkipped('$name not configured');
          return;
        }
        SharedPreferences.setMockInitialValues({});
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {};
        final repo = QuantityPlannerRepositoryImpl(
          aiClient: provider == 'gemini'
              ? GeminiSavingsClient(apiKey: key)
              : OpenAiSavingsClient(apiKey: key),
        );
        Future<PlannerAnalysis> turn(
          String input, [
          PlannerAnalysis? previous,
        ]) async {
          try {
            return await repo
                .analyzeTurn(input, previous: previous)
                .timeout(const Duration(seconds: 45));
          } catch (error) {
            // Avoid exposing raw errors containing request URLs or provider bodies.
            final status = RegExp(
              r'status (\d{3})',
            ).firstMatch(error.toString())?.group(1);
            fail(
              '$provider live request failed (${error.runtimeType}${status == null ? '' : ', HTTP $status'}).',
            );
          }
        }

        try {
          final first = await turn('carta igienica 12 rotolo 5 euro 3 veli');
          expect(first.needsInformation, isTrue);
          expect(first.plan.facts['price']?.value, 5);
          expect(first.plan.facts['rolls_count']?.value, 12);
          expect(first.plan.facts['plies_count']?.value, 3);
          expect(first.result.missing, ['sheets_per_roll']);
          expect(first.result.quantity, isNull);
          final second = await turn('500', first);
          expect(second.id, first.id);
          expect(second.result.quantity, 6000);
          expect(second.plan.facts['price']?.value, 5);
          expect(second.plan.facts['rolls_count']?.value, 12);
          expect(second.plan.facts['plies_count']?.value, 3);
          final third = await turn(
            'Correzione: il prezzo è 6 euro, gli altri dati sono invariati',
            second,
          );
          expect(third.id, first.id);
          expect(third.plan.facts['price']?.value, 6);
          expect(third.plan.facts['rolls_count']?.value, 12);
          expect(third.plan.facts['plies_count']?.value, 3);
          expect(third.result.quantity, 6000);
          expect(
            (await SharedPreferences.getInstance()).getString(
              'user_custom_categories',
            ),
            isNull,
          );
        } finally {
          debugPrint = originalDebugPrint;
        }
      },
      skip: Platform.environment['RUN_LIVE_PLANNER'] != '1',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
