import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/product_analysis.dart';
import '../../domain/entities/quantity_plan.dart';
import '../../domain/entities/savings_failure.dart';
import '../../domain/repositories/quantity_planner_repository.dart';
import '../../domain/entities/category_reference.dart';
import '../../domain/repositories/savings_repository.dart';
import '../models/chat_message.dart';
import '../../domain/entities/price_analysis.dart';
import '../../domain/repositories/verified_price_history.dart';
import '../../domain/services/price_comparison_service.dart';
import '../../data/datasources/verified_price_store.dart';

/// Unvalidated input plus the immutable context to replay, never economic data.
class _PlannerAttempt {
  const _PlannerAttempt(
    this.prompt,
    this.previous,
    this.analysisNumber,
    this.turnId,
    this.clarificationTurns,
  );
  final int analysisNumber;
  final int turnId;
  final String prompt;
  // Includes the local identity, revision, facts, question and accepted turns.
  final PlannerAnalysis? previous;
  final List<Map<String, String>> clarificationTurns;
}

class SavingsChatNotifier extends ChangeNotifier {
  SavingsChatNotifier({
    required SavingsRepository repository,
    this.planner,
    VerifiedPriceHistory? priceHistory,
  }) : _repository = repository,
       _priceHistory = priceHistory ?? const VerifiedPriceStore();

  final VerifiedPriceHistory _priceHistory;
  ComparablePrice? _price;
  PriceComparison? _priceComparison;
  String? _savedRevision;
  bool _isSaving = false;
  String? _saveMessage;
  SavingsFailure? _failure;
  SavingsFailure? get failure => _failure;
  ComparablePrice? get comparablePrice => _price;
  PriceComparison? get priceComparison => _priceComparison;
  bool get isSaving => _isSaving;
  bool get priceSaved =>
      _price != null && _savedRevision == _price!.observationId;
  String? get saveMessage => _saveMessage;
  bool get canSavePrice =>
      _clarificationTurns.isEmpty &&
      !_isLoading &&
      !_isSaving &&
      !priceSaved &&
      _priceComparison != null &&
      _price?.canSave == true;

  Future<bool> saveCurrentPrice() async {
    if (!canSavePrice) return false;
    final price = _price!;
    _isSaving = true;
    _saveMessage = null;
    _failure = null;
    notifyListeners();
    try {
      final saved = await _priceHistory.save(price);
      _savedRevision = price.observationId;
      _saveMessage = saved.alreadySaved
          ? 'Questo prezzo è già stato salvato.'
          : 'Prezzo salvato.';
      // Keep the original comparison: saving must not make the price its own reference.
      return !saved.alreadySaved;
    } catch (_) {
      _failure = const SavingsFailure(SavingsFailureKind.storageError);
      _saveMessage =
          '${_failure!.message} Salvataggio non riuscito. Puoi riprovare.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  static String formatUnitCost(double value) {
    if (value.isNaN || value.isInfinite) {
      return 'N/D';
    }

    // toStringAsFixed uses scientific notation for these values.
    if (value.abs() >= 1e21) return value.toString();
    final abs = value.abs();
    if (abs >= 1) {
      return value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }

    if (abs >= 0.01) {
      return value
          .toStringAsFixed(4)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }

    final trimmed = value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return trimmed == '-0' ? '0' : trimmed;
  }

  final SavingsRepository _repository;
  final QuantityPlannerRepository? planner;
  PlannerAnalysis? _plannerAnalysis;
  List<Map<String, String>> _clarificationTurns = [];
  PlannerAnalysis? get plannerAnalysis => _plannerAnalysis;
  _PlannerAttempt? _failedAttempt;
  int _plannerGeneration = 0;
  int _analysisNumber = 1;
  int _nextTurnId = 0;
  int get analysisNumber => _analysisNumber;
  bool get hasFailedPlannerTurn => _failedAttempt != null;
  bool get canRetryPlannerTurn =>
      hasFailedPlannerTurn && !_isLoading && !_isSaving;

  Future<void> retryLastPlannerTurn() async {
    if (!canRetryPlannerTurn) return;
    await _analyzePlannerTurn(_failedAttempt!, appendUserMessage: false);
  }

  Future<void> refreshPriceHistory() async {
    final price = _price;
    if (price == null || _isLoading || _isSaving) return;
    final generation = _plannerGeneration;
    try {
      final history = await _priceHistory.read();
      if (generation != _plannerGeneration ||
          _price != price ||
          _isLoading ||
          _isSaving) {
        return;
      }
      _priceComparison = const PriceComparisonService().compare(price, history);
      final stillSaved = history.any(
        (entry) =>
            entry.price.observationId == price.observationId ||
            (entry.price.analysis.id == price.analysis.id &&
                entry.price.samePriceAs(price)),
      );
      _savedRevision = stillSaved ? price.observationId : null;
      _saveMessage = null;
      notifyListeners();
    } catch (_) {
      if (generation != _plannerGeneration || _price != price) return;
      _priceComparison = null;
      _failure = const SavingsFailure(SavingsFailureKind.storageError);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _plannerGeneration++;
    super.dispose();
  }

  void startNewAnalysis() {
    if (_isLoading || _isSaving) return;
    _analysisNumber++;
    _plannerGeneration++;
    _failedAttempt = null;
    _plannerAnalysis = null;
    _clarificationTurns = [];
    _failure = null;
    _analyzedProducts.clear();
    _errorMessage = null;
    _price = null;
    _priceComparison = null;
    _saveMessage = null;
    _savedRevision = null;
    notifyListeners();
  }

  Future<void> _analyzePlannerTurn(
    _PlannerAttempt attempt, {
    bool appendUserMessage = true,
  }) async {
    final generation = ++_plannerGeneration;
    final previousPrice = _price;
    final previousComparison = _priceComparison;
    final previousSaveMessage = _saveMessage;
    if (appendUserMessage) {
      _failedAttempt = null;
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.user,
          text: attempt.prompt,
          analysisNumber: attempt.analysisNumber,
          turnId: attempt.turnId,
          analysisId: attempt.previous?.id,
          contextRevision: attempt.previous?.revision,
          createdAt: DateTime.now(),
        ),
      );
    }
    _isLoading = true;
    _errorMessage = null;
    _failure = null;
    _analyzedProducts.clear();
    _price = null;
    _priceComparison = null;
    _saveMessage = null;
    // Retain the authoritative context until the planner resolves the intention.
    notifyListeners();
    try {
      final analysis = await planner!.analyzeTurn(
        attempt.prompt,
        previous: attempt.previous,
        clarificationTurns: attempt.clarificationTurns,
      );
      if (generation != _plannerGeneration) return;
      _clarificationTurns = [];
      final changedProduct =
          attempt.previous != null && analysis.id != attempt.previous!.id;
      if (changedProduct) {
        _analysisNumber++;
        _savedRevision = null;
      }
      final resolvedNumber = _analysisNumber;
      _plannerAnalysis = analysis;
      final userIndex = _messages.indexWhere(
        (m) => m.sender == ChatMessageSender.user && m.turnId == attempt.turnId,
      );
      if (userIndex >= 0) {
        final message = _messages[userIndex];
        _messages[userIndex] = ChatMessage(
          sender: message.sender,
          text: message.text,
          createdAt: message.createdAt,
          analysisNumber: resolvedNumber,
          turnId: attempt.turnId,
          analysisId: analysis.id,
          revision: analysis.revision,
          contextRevision: changedProduct ? null : attempt.previous?.revision,
        );
      }
      _failedAttempt = null;
      if (_plannerAnalysis!.result.status ==
          QuantityResolutionStatus.calculable) {
        _price = ComparablePrice.fromAnalysis(_plannerAnalysis!);
        try {
          final snapshot = await _priceHistory.read();
          if (generation != _plannerGeneration) return;
          _priceComparison = const PriceComparisonService().compare(
            _price!,
            snapshot,
          );
        } catch (_) {
          if (generation != _plannerGeneration) return;
          _failure = const SavingsFailure(SavingsFailureKind.storageError);
          _errorMessage = '${_failure!.message} Salvataggio disabilitato.';
          _messages.add(
            ChatMessage(
              sender: ChatMessageSender.assistant,
              text: _errorMessage!,
              analysisNumber: resolvedNumber,
              turnId: attempt.turnId,
              analysisId: analysis.id,
              revision: analysis.revision,
              createdAt: DateTime.now(),
            ),
          );
        }
      }
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: _plannerAnalysis!.message,
          analysisNumber: resolvedNumber,
          turnId: attempt.turnId,
          analysisId: analysis.id,
          revision: analysis.revision,
          createdAt: DateTime.now(),
        ),
      );
    } on PlannerClarification catch (clarification) {
      if (generation != _plannerGeneration) return;
      _failedAttempt = null;
      _price = previousPrice;
      _priceComparison = previousComparison;
      _saveMessage = previousSaveMessage;
      _clarificationTurns = [
        ...attempt.clarificationTurns,
        {'role': 'user', 'text': attempt.prompt},
        {'role': 'assistant', 'text': clarification.question},
      ];
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: clarification.question,
          analysisNumber: _analysisNumber,
          turnId: attempt.turnId,
          analysisId: attempt.previous?.id,
          contextRevision: attempt.previous?.revision,
          createdAt: DateTime.now(),
        ),
      );
    } catch (error) {
      if (generation != _plannerGeneration) return;
      _failedAttempt = attempt;
      _failure = error is SavingsFailure
          ? error
          : SavingsFailure(
              error is TimeoutException
                  ? SavingsFailureKind.timeout
                  : SavingsFailureKind.parseError,
            );
      _errorMessage = _failure!.message;
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: _errorMessage!,
          analysisNumber: attempt.analysisNumber,
          turnId: attempt.turnId,
          analysisId: attempt.previous?.id,
          contextRevision: attempt.previous?.revision,
          failed: true,
          createdAt: DateTime.now(),
        ),
      );
    } finally {
      if (generation == _plannerGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<ProductAnalysis> _analyzedProducts = <ProductAnalysis>[];

  bool _isLoading = false;
  String? _errorMessage;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  List<ProductAnalysis> get analyzedProducts =>
      List<ProductAnalysis>.unmodifiable(_analyzedProducts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> analyzeShoppingPrompt(String rawPrompt) async {
    if (_isLoading || _isSaving) return;
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty) {
      return;
    }

    if (planner != null) {
      await _analyzePlannerTurn(
        _PlannerAttempt(
          prompt,
          _plannerAnalysis,
          _analysisNumber,
          ++_nextTurnId,
          List.unmodifiable(_clarificationTurns),
        ),
      );
      return;
    }
    // Legacy/demo path only.
    final isMeaningfulPrompt = _looksLikeProductPrompt(prompt);
    if (!isMeaningfulPrompt) {
      final friendlyMessage =
          'Ciao! Inserisci un elemento da valutare e ti aiuterò.';
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.user,
          text: prompt,
          createdAt: DateTime.now(),
        ),
      );
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: friendlyMessage,
          createdAt: DateTime.now(),
        ),
      );
      _errorMessage = friendlyMessage;
      notifyListeners();
      return;
    }

    _messages.add(
      ChatMessage(
        sender: ChatMessageSender.user,
        text: prompt,
        createdAt: DateTime.now(),
      ),
    );
    _errorMessage = null;
    _analyzedProducts.clear();
    _isLoading = true;
    notifyListeners();

    try {
      final products = await _repository.analyzeProducts(userPrompt: prompt);

      _analyzedProducts
        ..clear()
        ..addAll(products);

      final summary = _buildAssistantSummary(products);
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: summary,
          createdAt: DateTime.now(),
        ),
      );
    } on UnitMetricMismatch {
      const message =
          'Dati del prodotto riconosciuti, ma non confrontabili con '
          'lo storico della categoria usando la stessa unità. '
          'Lo storico non è stato aggiornato.';
      _errorMessage = message;
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: message,
          createdAt: DateTime.now(),
        ),
      );
    } on CategorySchemaMismatch {
      const message =
          'Dati incompleti o non coerenti con lo schema della categoria. '
          'Lo storico non è stato aggiornato.';
      _errorMessage = message;
      _messages.add(
        ChatMessage(
          sender: ChatMessageSender.assistant,
          text: message,
          createdAt: DateTime.now(),
        ),
      );
    } catch (error) {
      final friendlyMessage =
          error.toString().contains('Inserisci un elemento da valutare')
          ? error.toString().replaceFirst('Bad state: ', '')
          : 'Analisi non riuscita. Verifica i dati e la configurazione, poi riprova.';
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
    final hasProductWord = RegExp(
      r'\b(carta|igienica|detergente|lavastoviglie|pastiglie|pane|latte|sapone|shampoo|acqua|pasta|biscotti|caffè|caffe|rotoli|strappi|kg|litro|ml|euro|\€|prezzo)\b',
    ).hasMatch(normalized);

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
    return fallback.isNotEmpty
        ? fallback
        : 'Nessun dato disponibile per questo prodotto.';
  }
}
