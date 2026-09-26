import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'savings_checker/data/datasources/ai_savings_client.dart';
import 'savings_checker/data/datasources/gemini_savings_client.dart';
import 'savings_checker/data/datasources/openai_savings_client.dart';
import 'savings_checker/data/repositories/savings_repository_impl.dart';
import 'savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'savings_checker/presentation/pages/savings_checker_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isDotEnvLoaded = false;
  try {
    await dotenv.load(fileName: '.env');
    isDotEnvLoaded = true;
  } catch (_) {
    isDotEnvLoaded = false;
  }

  final providerName = (dotenv.env['AI_PROVIDER'] ?? 'openai')
      .trim()
      .toLowerCase();
  final openAiKey = dotenv.env['OPENAI_API_KEY'];
  final geminiKey = dotenv.env['GEMINI_API_KEY'];

  debugPrint('Risparmiai startup: dotenv loaded = $isDotEnvLoaded');
  debugPrint('Risparmiai startup: AI_PROVIDER=$providerName');
  debugPrint(
    'Risparmiai startup: OPENAI_API_KEY present = ${((openAiKey ?? '').trim().isNotEmpty)}',
  );
  debugPrint(
    'Risparmiai startup: GEMINI_API_KEY present = ${((geminiKey ?? '').trim().isNotEmpty)}',
  );

  AiSavingsClient? aiClient;
  switch (providerName) {
    case 'gemini':
      if ((geminiKey ?? '').trim().isNotEmpty) {
        aiClient = GeminiSavingsClient(apiKey: geminiKey);
        debugPrint('Risparmiai startup: selected Gemini client');
      } else {
        debugPrint(
          'Risparmiai startup: Gemini selected but key missing, analysis will report a configuration error',
        );
      }
      break;
    case 'mock':
      aiClient = null;
      debugPrint('Risparmiai startup: mock mode selected');
      break;
    case 'openai':
    default:
      if ((openAiKey ?? '').trim().isNotEmpty) {
        aiClient = OpenAiSavingsClient(apiKey: openAiKey);
        debugPrint('Risparmiai startup: selected OpenAI client');
      } else {
        debugPrint(
          'Risparmiai startup: OpenAI selected but key missing, analysis will report a configuration error',
        );
      }
      break;
  }

  final useMockData = providerName == 'mock';
  debugPrint(
    'Risparmiai startup: final provider = ${useMockData ? 'mock' : providerName}; usingMockData = $useMockData',
  );

  runApp(MainApp(useMockData: useMockData, aiClient: aiClient));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.useMockData, this.aiClient});

  final bool useMockData;
  final AiSavingsClient? aiClient;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SavingsChatNotifier>(
      create: (_) => SavingsChatNotifier(
        repository: SavingsRepositoryImpl(
          useMockData: useMockData,
          aiClient: aiClient,
        ),
      ),
      child: MaterialApp(
        title: 'Verifica Risparmio',
        debugShowCheckedModeBanner: false,
        home: const SavingsCheckerPage(),
      ),
    );
  }
}
