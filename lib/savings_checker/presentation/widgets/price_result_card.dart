import 'package:flutter/material.dart';

import '../../domain/entities/price_analysis.dart';
import '../notifiers/savings_chat_notifier.dart';

class PriceResultCard extends StatelessWidget {
  const PriceResultCard({super.key, required this.notifier});
  final SavingsChatNotifier notifier;

  static String amount(double value) {
    if (value != 0 && value.abs() < 0.000001) {
      return value.toStringAsPrecision(4).replaceAll('.', ',');
    }
    return SavingsChatNotifier.formatUnitCost(value).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final price = notifier.comparablePrice!;
    final comparison = notifier.priceComparison;
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: SingleChildScrollView(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${amount(price.unitCost)} €/${price.displayUnit}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${amount(price.totalPrice)} € per ${amount(price.quantity)} ${price.displayUnit}',
                  ),
                  Text(message),
                  if (comparison != null && comparison.count > 0) ...[
                    Text(
                      'Storico precedente: ${comparison.count} prezzi salvati.',
                    ),
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
                    const Text(
                      'Il prezzo zero è analizzabile, ma non salvabile.',
                    ),
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
        ),
      ),
    );
  }
}
