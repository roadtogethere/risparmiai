import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/product_analysis.dart';
import '../models/chat_message.dart';
import '../notifiers/savings_chat_notifier.dart';

class SavingsCheckerPage extends StatefulWidget {
  const SavingsCheckerPage({
    super.key,
  });

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifica Risparmio'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: notifier.messages.length,
                itemBuilder: (context, index) {
                  final message = notifier.messages[notifier.messages.length - 1 - index];
                  final isUser = message.sender == ChatMessageSender.user;

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blue.shade600 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          color: isUser ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (notifier.analyzedProducts.isNotEmpty)
              _ProductInsightCard(products: notifier.analyzedProducts),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Es: confronta i costi di carta igienica e detersivo',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitPrompt(context),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: notifier.isLoading ? null : () => _submitPrompt(context),
                  icon: Icon(notifier.isLoading ? Icons.hourglass_top : Icons.send),
                  label: Text(notifier.isLoading ? 'Analizzo...' : 'Invia'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitPrompt(BuildContext context) async {
    final prompt = _controller.text;
    if (prompt.trim().isEmpty) {
      return;
    }

    _controller.clear();
    await context.read<SavingsChatNotifier>().analyzeShoppingPrompt(prompt);
  }
}

class _ProductInsightCard extends StatelessWidget {
  const _ProductInsightCard({
    required this.products,
  });

  final List<ProductAnalysis> products;

  @override
  Widget build(BuildContext context) {
    final best = products.reduce((currentBest, candidate) {
      return candidate.unitCost < currentBest.unitCost ? candidate : currentBest;
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Migliore convenienza',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${best.brand} ${best.productName}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text('Costo unitario: ${best.unitCost.toStringAsFixed(2)} €/ ${best.primaryUnitName}'),
          const SizedBox(height: 10),
          if (best.specificAttributes.isNotEmpty) ...<Widget>[
            const Divider(),
            Text(
              'Specific attributes',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...best.specificAttributes.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: Text('${entry.key}:', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(entry.value.toString()),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
