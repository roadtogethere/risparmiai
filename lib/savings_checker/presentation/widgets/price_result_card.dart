import 'package:flutter/material.dart';

import '../../domain/entities/price_analysis.dart';
import '../notifiers/savings_chat_notifier.dart';
import '../models/analysis_display.dart';
import 'recognized_facts.dart';

class PriceResultCard extends StatelessWidget {
  const PriceResultCard({super.key, required this.notifier});
  final SavingsChatNotifier notifier;

  static String amount(double value) => AnalysisDisplay.amount(value);

  @override
  Widget build(BuildContext context) {
    final price = notifier.comparablePrice!;
    final comparison = notifier.priceComparison;
    final scaled = AnalysisDisplay.scaledCost(
      price.unitCost,
      price.canonicalMetric,
    );
    final message = switch (comparison?.position) {
      PricePosition.noHistory =>
        'Nessuno storico verificato: convenienza non valutabile.',
      PricePosition.potentialMinimum =>
        'Nuovo minimo potenziale rispetto ai prezzi salvati.',
      PricePosition.tiedMinimum => 'Prezzo pari al minimo precedente.',
      PricePosition.belowAverage =>
        'Prezzo sopra il minimo e sotto la media precedente.',
      PricePosition.tiedAverage => 'Prezzo pari alla media precedente.',
      PricePosition.aboveAverage => 'Prezzo sopra la media precedente.',
      null => 'Storico verificato non disponibile.',
    };
    String difference(double value, double? percentage) =>
        '${value > 0 ? '+' : ''}${amount(value)} €/${price.displayUnit}'
        '${percentage == null ? '' : ' (${percentage > 0 ? '+' : ''}${amount(percentage)}%)'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RecognizedFacts(analysis: price.analysis),
              const Divider(),
              const Text(
                'Costo comparabile',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${amount(price.unitCost)} €/${price.displayUnit}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Quantità comparabile: ${amount(price.quantity)} ${price.displayUnit}',
              ),
              if (scaled != null) Text(scaled),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: comparison?.isPotentialNewMinimum == true
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Confronto con lo storico personale\n$message'),
              ),
              if (comparison != null && comparison.count > 0) ...[
                Text('Storico precedente: ${comparison.count} prezzi salvati.'),
                Text(
                  'Minimo: ${amount(comparison.previousMinimum!)} €/${price.displayUnit}; media: ${amount(comparison.previousAverage!)} €/${price.displayUnit}.',
                ),
                Text(
                  'Differenza dal minimo: ${difference(comparison.differenceFromMinimum!, comparison.percentFromMinimum)}',
                ),
                Text(
                  'Differenza dalla media: ${difference(comparison.differenceFromAverage!, comparison.percentFromAverage)}',
                ),
              ],
              if (price.totalPrice == 0)
                const Text('Il prezzo zero è analizzabile, ma non salvabile.'),
              if (price.canSave)
                FilledButton(
                  onPressed: notifier.canSavePrice
                      ? notifier.saveCurrentPrice
                      : null,
                  child: Text(
                    notifier.priceSaved
                        ? 'Prezzo salvato'
                        : notifier.isSaving
                        ? 'Salvataggio…'
                        : 'Salva questo prezzo',
                  ),
                ),
              if (notifier.saveMessage != null)
                Text(
                  notifier.saveMessage!,
                  semanticsLabel: notifier.saveMessage,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
