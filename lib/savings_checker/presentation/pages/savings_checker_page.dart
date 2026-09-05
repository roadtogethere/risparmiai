import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/product_analysis.dart';
import '../models/chat_message.dart';
import '../notifiers/savings_chat_notifier.dart';
import 'archive_page.dart';

class SavingsCheckerPage extends StatefulWidget {
  const SavingsCheckerPage({super.key});

  @override
  State<SavingsCheckerPage> createState() => _SavingsCheckerPageState();
}

class _SavingsCheckerPageState extends State<SavingsCheckerPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<SavingsChatNotifier>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Sfondo neutro, pulito e moderno
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
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF495057)),
            tooltip: 'Archivio',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ArchivePage()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Lista Messaggi
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: notifier.messages.length,
                itemBuilder: (context, index) {
                  final message = notifier.messages[notifier.messages.length - 1 - index];
                  final isUser = message.sender == ChatMessageSender.user;

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: isUser ? const Color(0xFF0F62FE) : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
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
                          color: isUser ? Colors.white : const Color(0xFF212529),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Card Insight Risparmio (se presente)
            if (notifier.analyzedProducts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _ProductInsightCard(products: notifier.analyzedProducts),
              ),

            // Campo di input inferiore
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
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Confronta prodotti (es. detersivo, carta)...',
                        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFFF1F3F5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _submitPrompt(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFF0F62FE),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: notifier.isLoading ? null : () => _submitPrompt(context),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: notifier.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
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

  Future<void> _submitPrompt(BuildContext context) async {
    final prompt = _controller.text;
    if (prompt.trim().isEmpty) return;

    _controller.clear();
    await context.read<SavingsChatNotifier>().analyzeShoppingPrompt(prompt);
  }
}

class _ProductInsightCard extends StatelessWidget {
  const _ProductInsightCard({required this.products});

  final List<ProductAnalysis> products;

  @override
  Widget build(BuildContext context) {
    final best = products.reduce((currentBest, candidate) {
      return candidate.unitCost < currentBest.unitCost ? candidate : currentBest;
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
            color: Colors.green.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Badge "Migliore Convenienza"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F4EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.stars_rounded, size: 14, color: Color(0xFF137333)),
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
          Text(
            '${best.brand} ${best.productName}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Color(0xFF495057), fontSize: 14),
              children: [
                const TextSpan(text: 'Costo unitario: '),
                TextSpan(
                  text: '${SavingsChatNotifier.formatUnitCost(best.unitCost)} €',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF137333)),
                ),
                TextSpan(text: ' / ${best.primaryUnitName}'),
              ],
            ),
          ),

          // Attributi Specifici (Chip Style)
          if (best.specificAttributes.isNotEmpty) ...<Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Color(0xFFF1F3F5)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: best.specificAttributes.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                  ),
                  child: Text(
                    '${entry.key}: ${entry.value}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF495057)),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}