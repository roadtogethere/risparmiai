import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/product_analysis.dart';
import '../models/chat_message.dart';
import '../notifiers/savings_chat_notifier.dart';
import 'archive_page.dart';
import '../widgets/price_result_card.dart';
import 'verified_prices_page.dart';

/// Pagina principale per la verifica del risparmio sui prodotti.
/// Utilizza un [StatefulWidget] per gestire il controller del campo di testo locale.
class SavingsCheckerPage extends StatefulWidget {
  const SavingsCheckerPage({super.key});

  @override
  State<SavingsCheckerPage> createState() => _SavingsCheckerPageState();
}

class _SavingsCheckerPageState extends State<SavingsCheckerPage> {
  // Controller per gestire l'input di testo dell'utente
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    // Rilascio delle risorse del controller per evitare memory leak
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ascolta i cambiamenti in SavingsChatNotifier e ri-esegue il build all'aggiornamento
    final notifier = context.watch<SavingsChatNotifier>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(
        0xFFF8F9FA,
      ), // Sfondo neutro, pulito e moderno
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        title: Text(
          'Verifica Risparmio',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: true,
        actions: <Widget>[
          if (notifier.planner != null)
            IconButton(
              onPressed: notifier.isLoading || notifier.isSaving
                  ? null
                  : notifier.startNewAnalysis,
              tooltip: 'Nuova analisi',
              icon: const Icon(Icons.add),
            ),
          // Pulsante per navigare alla schermata dell'Archivio
          IconButton(
            icon: const Icon(
              Icons.inventory_2_outlined,
              color: Color(0xFF495057),
            ),
            tooltip: 'Archivio',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => notifier.planner != null
                      ? const VerifiedPricesPage()
                      : const ArchivePage(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // --- SEZIONE 1: Cronologia della Chat ---
            Expanded(
              child: ListView.builder(
                // Inverte l'ordine della lista: utile per le chat dove i nuovi messaggi compaiono in basso
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: notifier.messages.length,
                itemBuilder: (context, index) {
                  // Inverte l'indice per mostrare il messaggio più recente in fondo alla vista
                  final message =
                      notifier.messages[notifier.messages.length - 1 - index];
                  final isUser = message.sender == ChatMessageSender.user;

                  return Align(
                    // Allinea i messaggi dell'utente a destra e quelli del bot a sinistra
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      constraints: BoxConstraints(
                        // Limita la larghezza massima del bubble al 78% dello schermo
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: isUser ? const Color(0xFF0F62FE) : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          // Smussa tre angoli e ne lascia uno più stretto per creare l'effetto "fumetto"
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          height: 1.4,
                          fontSize: 15,
                          color: isUser
                              ? Colors.white
                              : const Color(0xFF212529),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // --- SEZIONE 2: Card di Analisi (Rendering Condizionale) ---
            if (notifier.comparablePrice != null)
              PriceResultCard(notifier: notifier),
            // Mostra la scheda del miglior prodotto solo se ci sono prodotti analizzati
            if (notifier.analyzedProducts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _ProductInsightCard(products: notifier.analyzedProducts),
              ),

            // --- SEZIONE 3: Area di Input Testo ---
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE9ECEF), width: 1),
                ),
              ),
              child: Row(
                children: <Widget>[
                  // Campo di testo per l'inserimento del prompt
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText:
                            'Confronta prodotti (es. detersivo, carta)...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF1F3F5),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      // Invio del messaggio tramite tastiera mobile
                      onSubmitted: (_) => _submitPrompt(context),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Pulsante Invio / Indicatore di caricamento
                  Material(
                    color: const Color(0xFF0F62FE),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      // Disabilita il click se il notifier è in stato di caricamento
                      onTap: notifier.isLoading || notifier.isSaving
                          ? null
                          : () => _submitPrompt(context),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: notifier.isLoading
                            // Spinner di caricamento se la richiesta è in corso
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            // Icona invio standard
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Invia il prompt inserito al [SavingsChatNotifier] e pulisce il campo di testo
  Future<void> _submitPrompt(BuildContext context) async {
    final notifier = context.read<SavingsChatNotifier>();
    if (notifier.isLoading || notifier.isSaving) return;
    final prompt = _controller.text;
    if (prompt.trim().isEmpty) return;

    _controller.clear();
    // Invia il prompt al notifier senza bloccare l'interfaccia principale
    await context.read<SavingsChatNotifier>().analyzeShoppingPrompt(prompt);
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
