import 'dart:async';
import 'package:flutter/material.dart';
import '../../../advertising/domain/advertising_service.dart';
import '../../../advertising/data/advertising_debug_log.dart';
import '../../../advertising/presentation/interstitial_coordinator.dart';
import 'package:provider/provider.dart';
import '../../../privacy/domain/privacy_repository.dart';
import '../../../privacy/presentation/privacy_policy_page.dart';

import '../../domain/entities/product_analysis.dart';
import '../models/chat_message.dart';
import '../models/analysis_display.dart';
import '../notifiers/savings_chat_notifier.dart';
import '../widgets/price_result_card.dart';
import '../widgets/recognized_facts.dart';
import 'archive_page.dart';
import 'verified_prices_page.dart';

class SavingsCheckerPage extends StatefulWidget {
  const SavingsCheckerPage({super.key, this.isDemo = false});
  final bool isDemo;

  @override
  State<SavingsCheckerPage> createState() => _SavingsCheckerPageState();
}

class _SavingsCheckerPageState extends State<SavingsCheckerPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _showLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _newAnalysis(SavingsChatNotifier notifier) {
    logAdvertisingEvent(
      'interstitial',
      'new_analysis_clicked',
      trigger: 'newAnalysis',
    );
    if (notifier.isLoading || notifier.isSaving) {
      logAdvertisingEvent(
        'interstitial',
        'skipped_processing',
        trigger: 'newAnalysis',
      );
      return;
    }
    final offerAd = notifier.plannerAnalysis != null;
    final ads = context.read<AdvertisingService?>();
    if (!offerAd || ads == null) {
      final reason = ads == null
          ? 'skipped_service_missing'
          : notifier.hasPendingClarification
          ? 'skipped_pending_clarification'
          : 'skipped_empty_analysis';
      logAdvertisingEvent('interstitial', reason, trigger: 'newAnalysis');
    }
    notifier.startNewAnalysis();
    _controller.clear();
    _showLatest();
    final analysisNumber = notifier.analysisNumber;
    if (offerAd && ads != null) {
      unawaited(
        InterstitialCoordinator(ads).afterNewAnalysis(
          context,
          canShow: () =>
              mounted &&
              !notifier.isLoading &&
              !notifier.isSaving &&
              !notifier.hasPendingClarification &&
              notifier.analysisNumber == analysisNumber &&
              notifier.plannerAnalysis == null &&
              _controller.text.isEmpty,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<SavingsChatNotifier>();
    final items = <Widget>[];
    int? previousGroup;
    for (var i = 0; i <= notifier.messages.length; i++) {
      final group = i < notifier.messages.length
          ? notifier.messages[i].analysisNumber
          : notifier.analysisNumber;
      if (group != previousGroup && notifier.planner != null) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nuovo prodotto',
              key: ValueKey('analysis-boundary-$group'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
        previousGroup = group;
      }
      if (i < notifier.messages.length) {
        items.add(_message(notifier.messages[i]));
      }
    }
    if (notifier.comparablePrice != null) {
      items.add(PriceResultCard(notifier: notifier));
    } else if (notifier.plannerAnalysis != null && !notifier.isLoading) {
      // Keep the latest question/error below the facts, close to the input.
      items.insert(
        items.isEmpty ? 0 : items.length - 1,
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (notifier.hasFailedPlannerTurn)
                  const Text(
                    'Dati dell’ultimo tentativo elaborato, non della richiesta fallita.',
                  ),
                RecognizedFacts(analysis: notifier.plannerAnalysis!),
              ],
            ),
          ),
        ),
      );
    }
    if (notifier.analyzedProducts.isNotEmpty) {
      items.add(_ProductInsightCard(products: notifier.analyzedProducts));
    }
    if (notifier.hasFailedPlannerTurn) {
      items.add(
        TextButton(
          onPressed: notifier.canRetryPlannerTurn
              ? () async {
                  await notifier.retryLastPlannerTurn();
                  _showLatest();
                }
              : null,
          child: const Text('Riprova'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Verifica Risparmio',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (context.read<PrivacyRepository?>() case final privacy?)
            IconButton(
              icon: const Icon(Icons.privacy_tip_outlined),
              tooltip: 'Informativa privacy',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PrivacyPolicyPage(repository: privacy),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Archivio',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => notifier.planner != null
                      ? const VerifiedPricesPage()
                      : const ArchivePage(),
                ),
              );
              if (mounted) await notifier.refreshPriceHistory();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.isDemo)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.tertiaryContainer,
                padding: const EdgeInsets.all(8),
                child: const Text(
                  'Modalità demo — dati simulati',
                  textAlign: TextAlign.center,
                ),
              ),
            if (notifier.planner != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: 'Nuova analisi',
                  child: TextButton.icon(
                    onPressed: notifier.isLoading || notifier.isSaving
                        ? null
                        : () => _newAnalysis(notifier),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuova analisi'),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                key: const ValueKey('conversation'),
                controller: _scroll,
                reverse: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: items.reversed.toList(),
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        labelText: 'Scrivi in chat',
                        hintText: 'Descrivi un prodotto o correggi i dati',
                        filled: true,
                        fillColor: const Color(0xFFF1F3F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _submitPrompt(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (notifier.isLoading)
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    IconButton.filled(
                      tooltip: 'Invia',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0F62FE),
                      ),
                      onPressed: notifier.isSaving
                          ? null
                          : () => _submitPrompt(context),
                      icon: const Icon(Icons.send_rounded),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(ChatMessage message) {
    final isUser = message.sender == ChatMessageSender.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF0F62FE) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.failed) const Text('Richiesta non riuscita'),
            Text(
              !isUser && message.revision != null
                  ? AnalysisDisplay.quantitySummary(message.text)
                  : message.text,
              style: TextStyle(
                height: 1.4,
                color: isUser ? Colors.white : const Color(0xFF212529),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitPrompt(BuildContext context) async {
    final notifier = context.read<SavingsChatNotifier>();
    if (notifier.isLoading || notifier.isSaving) return;
    final prompt = _controller.text;
    if (prompt.trim().isEmpty) return;
    final ads = context.read<AdvertisingService?>();
    final coordinator = ads == null ? null : InterstitialCoordinator(ads);
    final registration = notifier.planner != null
        ? coordinator?.recordChatMessage()
        : null;
    _controller.clear();
    _showLatest();
    await notifier.analyzeShoppingPrompt(prompt);
    if (!context.mounted) return;
    _showLatest();
    final analysis = notifier.plannerAnalysis;
    if (registration != null && analysis != null) {
      unawaited(
        coordinator!.afterChatAnalysis(
          context,
          registration: registration,
          canShow: () =>
              mounted &&
              !notifier.isLoading &&
              !notifier.isSaving &&
              !notifier.hasPendingClarification &&
              !notifier.hasFailedPlannerTurn &&
              notifier.failure == null &&
              notifier.comparablePrice != null &&
              identical(notifier.plannerAnalysis, analysis) &&
              _controller.text.isEmpty,
        ),
      );
    }
  }
}

/// Componente per mostrare il prodotto con la migliore convenienza economica
class _ProductInsightCard extends StatelessWidget {
  const _ProductInsightCard({required this.products});

  final List<ProductAnalysis> products;

  @override
  Widget build(BuildContext context) {
    // Algoritmo di riduzione per individuare il prodotto con il costo unitario più basso
    final best = products.reduce((currentBest, candidate) {
      return candidate.unitCost < currentBest.unitCost
          ? candidate
          : currentBest;
    });

    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD3E5D8)),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Badge: "Migliore Convenienza"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F4EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.stars_rounded,
                      size: 14,
                      color: Color(0xFF137333),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Migliore convenienza',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF137333),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Nome del prodotto vincitore e marca
          Text(
            '${best.brand} ${best.productName}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),

          // Prezzo unitario formattato
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Color(0xFF495057), fontSize: 14),
              children: [
                const TextSpan(text: 'Costo unitario: '),
                TextSpan(
                  text:
                      '${SavingsChatNotifier.formatUnitCost(best.unitCost)} €',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF137333),
                  ),
                ),
                TextSpan(text: ' / ${best.primaryUnitName}'),
              ],
            ),
          ),

          // Sezione Chip: Attributi specifici del prodotto (se presenti)
        ],
      ),
    );
  }
}
