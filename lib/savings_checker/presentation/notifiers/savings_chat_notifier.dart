import 'package:flutter/foundation.dart';

import '../../domain/entities/product_analysis.dart';
import '../../domain/repositories/savings_repository.dart';
import '../models/chat_message.dart';

class SavingsChatNotifier extends ChangeNotifier {
  SavingsChatNotifier({
    required SavingsRepository repository,
  }) : _repository = repository;

  static String formatUnitCost(double value) {
    if (value.isNaN || value.isInfinite) {
      return '0';
    }

    final abs = value.abs();
    if (abs >= 1) {
      return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '').replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }

    if (abs >= 0.01) {
      return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }

    final trimmed = value.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return trimmed == '-0' ? '0' : trimmed;
  }

  final SavingsRepository _repository;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<ProductAnalysis> _analyzedProducts = <ProductAnalysis>[];

  bool _isLoading = false;
  String? _errorMessage;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  List<ProductAnalysis> get analyzedProducts => List<ProductAnalysis>.unmodifiable(_analyzedProducts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> analyzeShoppingPrompt(String rawPrompt) async {
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty) {
      return;
    }

    final isMeaningfulPrompt = _looksLikeProductPrompt(prompt);
    if (!isMeaningfulPrompt) {
      final friendlyMessage = 'Ciao! Inserisci un elemento da valutare e ti aiuterò.';
      _messages.add(ChatMessage(sender: ChatMessageSender.user, text: prompt, createdAt: DateTime.now()));
      _messages.add(ChatMessage(sender: ChatMessageSender.assistant, text: friendlyMessage, createdAt: DateTime.now()));
      _errorMessage = friendlyMessage;
      notifyListeners();
      return;
    }

    _messages.add(ChatMessage(sender: ChatMessageSender.user, text: prompt, createdAt: DateTime.now()));
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      final products = await _repository.analyzeProducts(userPrompt: prompt);

      _analyzedProducts
        ..clear()
        ..addAll(products);

      final summary = _buildAssistantSummary(products);
      _messages.add(ChatMessage(sender: ChatMessageSender.assistant, text: summary, createdAt: DateTime.now()));
    } catch (error) {
      final friendlyMessage = error.toString().contains('Inserisci un elemento da valutare')
          ? error.toString().replaceFirst('Bad state: ', '')
          : 'Ciao! Inserisci un elemento da valutare e ti aiuterò.';
      _errorMessage = friendlyMessage;
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: friendlyMessage,
          createdAt: DateTime.now(),
        ),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _looksLikeProductPrompt(String prompt) {
    if (prompt.isEmpty || prompt.length < 3) {
      return false;
    }

    final normalized = prompt.toLowerCase();
    final genericInputs = <String>{
      'ciao',
      'prova',
      'test',
      'come stai',
      'come va',
      'hi',
      'hello',
      'salve',
      'buongiorno',
      'buonasera',
      'ciao come stai',
      'ok',
    };

    if (genericInputs.contains(normalized)) {
      return false;
    }

    final hasLetters = RegExp(r'[a-zà-ù]').hasMatch(normalized);
    final hasNumber = RegExp(r'\d').hasMatch(normalized);
    final hasProductWord = RegExp(r'\b(carta|igienica|detergente|lavastoviglie|pastiglie|pane|latte|sapone|shampoo|acqua|pasta|biscotti|caffè|caffe|rotoli|strappi|kg|litro|ml|euro|\€|prezzo)\b').hasMatch(normalized);

    return hasLetters && (hasNumber || hasProductWord);
  }

  String _buildAssistantSummary(List<ProductAnalysis> products) {
    if (products.isEmpty) {
      return 'Non ho trovato prodotti da confrontare.';
    }

    final buffer = StringBuffer();
    for (final product in products) {
      final summary = product.analysisSummary;
      if (summary != null && summary.trim().isNotEmpty) {
        buffer.writeln(summary.trim());
      }
    }

    final fallback = buffer.toString().trim();
    return fallback.isNotEmpty ? fallback : 'Nessun dato disponibile per questo prodotto.';
  }
}
