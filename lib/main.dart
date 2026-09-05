import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

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

  final hasOpenAiKey = isDotEnvLoaded &&
      (dotenv.env['OPENAI_API_KEY'] ?? '').trim().isNotEmpty;

  runApp(
    MainApp(
      useMockData: !hasOpenAiKey,
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({
    super.key,
    required this.useMockData,
  });

  final bool useMockData;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SavingsChatNotifier>(
      create: (_) => SavingsChatNotifier(
        repository: SavingsRepositoryImpl(
          useMockData: useMockData,
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
