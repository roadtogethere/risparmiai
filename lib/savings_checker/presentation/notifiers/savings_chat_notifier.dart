import 'package:flutter/foundation.dart';

import '../../domain/entities/product_analysis.dart';
import '../../domain/repositories/savings_repository.dart';
import '../models/chat_message.dart';

class SavingsChatNotifier extends ChangeNotifier {
  SavingsChatNotifier({
    required SavingsRepository repository,
  }) : _repository = repository;

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
      _errorMessage = error.toString();
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: 'Si è verificato un problema durante l’analisi. Riprova con una richiesta più specifica.',
          createdAt: DateTime.now(),
        ),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _buildAssistantSummary(List<ProductAnalysis> products) {
    if (products.isEmpty) {
      return 'Non ho trovato prodotti da confrontare.';
    }

    final bestProduct = products.reduce((best, current) {
      return current.unitCost < best.unitCost ? current : best;
    });

    final buffer = StringBuffer();
    buffer.writeln('Ho analizzato ${products.length} prodotto/i.');
    buffer.writeln('Il miglior prezzo unitario è ${bestProduct.brand} ${bestProduct.productName}: ${bestProduct.unitCost.toStringAsFixed(2)} €/unità.');

    for (final product in products) {
      final cost = product.unitCost;
      buffer.writeln('- ${product.brand} ${product.productName}: ${cost.toStringAsFixed(2)} €/ ${product.primaryUnitName}');
    }

    return buffer.toString();
  }
}
