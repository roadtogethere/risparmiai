import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'savings_checker/data/repositories/savings_repository_impl.dart';
import 'savings_checker/presentation/notifiers/savings_chat_notifier.dart';
import 'savings_checker/presentation/pages/savings_checker_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = SavingsChatNotifier(
      repository: SavingsRepositoryImpl(
        useMockData: true,
      ),
    );

    return MaterialApp(
      title: 'Verifica Risparmio',
      debugShowCheckedModeBanner: false,
      home: SavingsCheckerPage(notifier: notifier),
    );
  }
}
