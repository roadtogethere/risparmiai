import 'package:flutter/material.dart';
import '../../../advertising/presentation/advertising_banner.dart';

import '../../data/datasources/verified_price_store.dart';
import '../../domain/entities/price_analysis.dart';
import '../../domain/entities/savings_failure.dart';
import '../widgets/price_result_card.dart';
import 'archive_page.dart';

class VerifiedPricesPage extends StatefulWidget {
  const VerifiedPricesPage({super.key});
  @override
  State<VerifiedPricesPage> createState() => _VerifiedPricesPageState();
}

class _VerifiedPricesPageState extends State<VerifiedPricesPage> {
  late final Future<List<SavedPrice>> _observations = const VerifiedPriceStore()
      .read();
  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: const SafeArea(child: AdvertisingBanner()),
    appBar: AppBar(
      title: const Text('Prezzi salvati'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const ArchivePage())),
          child: const Text('Archivio precedente'),
        ),
      ],
    ),
    body: FutureBuilder<List<SavedPrice>>(
      future: _observations,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              const SavingsFailure(SavingsFailureKind.storageError).message,
            ),
          );
        }
        final observations = snapshot.data!.reversed.toList();
        if (observations.isEmpty) {
          return const Center(
            child: Text(
              'Nessun prezzo salvato. Usa «Salva questo prezzo» dopo un’analisi.',
            ),
          );
        }
        return ListView.builder(
          itemCount: observations.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Questi prezzi sono usati nei confronti. L’archivio precedente resta escluso. Non sono acquisti registrati.',
                ),
              );
            }
            final record = observations[index - 1];
            final price = record.price;
            final date = record.savedAt.toLocal();
            return ListTile(
              title: Text(price.analysis.schema.displayName),
              subtitle: Text(
                '${PriceResultCard.amount(price.totalPrice)} € per ${PriceResultCard.amount(price.quantity)} ${price.displayUnit} · ${date.day}/${date.month}/${date.year}',
              ),
              trailing: Text(
                '${PriceResultCard.amount(price.unitCost)} €/${price.displayUnit}',
              ),
            );
          },
        );
      },
    ),
  );
}
