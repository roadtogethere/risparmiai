import 'package:flutter/material.dart';
import '../../../advertising/presentation/advertising_banner.dart';

import '../../data/datasources/verified_price_store.dart';
import '../../domain/entities/price_analysis.dart';
import '../../domain/entities/savings_failure.dart';
import '../../domain/repositories/verified_price_history.dart';
import '../../domain/services/price_comparison_service.dart';
import '../widgets/price_result_card.dart';
import 'archive_page.dart';

class VerifiedPricesPage extends StatefulWidget {
  const VerifiedPricesPage({
    super.key,
    this.history = const VerifiedPriceStore(),
  });
  final VerifiedPriceHistory history;
  @override
  State<VerifiedPricesPage> createState() => _VerifiedPricesPageState();
}

class _VerifiedPricesPageState extends State<VerifiedPricesPage> {
  late Future<List<SavedPrice>> _observations = widget.history.read();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _busy = false;

  void _reload() => setState(() {
    _observations = widget.history.read();
  });

  Future<void> _delete(SavedPrice observation) async {
    if (_busy) return;
    _messenger.currentState?.removeCurrentSnackBar();
    setState(() => _busy = true);
    try {
      final removed = await widget.history.delete(
        observation.price.observationId,
      );
      if (!mounted) return;
      _reload();
      if (removed != null) {
        _messenger.currentState?.showSnackBar(
          SnackBar(
            content: const Text('Prezzo eliminato.'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Annulla',
              onPressed: () => _restore(removed),
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _reload();
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('Eliminazione non riuscita. Riprova.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(SavedPrice observation) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.history.restore(observation);
      if (!mounted) return;
      _reload();
    } catch (_) {
      if (!mounted) return;
      _reload();
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: const Text('Ripristino non riuscito.'),
          action: SnackBarAction(
            label: 'Riprova',
            onPressed: () => _restore(observation),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _unitCost(double value) => value >= 0.0001 && value < 1
      ? value.toStringAsFixed(4).replaceAll('.', ',')
      : PriceResultCard.amount(value);

  Widget _summary(List<SavedPrice> observations) {
    final price = observations.first.price;
    final summary = const PriceComparisonService().summarize(observations);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            price.analysis.schema.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('Minimo: ${_unitCost(summary.minimum!)} €/${price.displayUnit}'),
          Text('Media: ${_unitCost(summary.average!)} €/${price.displayUnit}'),
          Text('Osservazioni: ${summary.count}'),
        ],
      ),
    );
  }

  Widget _observation(SavedPrice record) {
    final price = record.price;
    final date = record.savedAt.toLocal();
    return ListTile(
      key: ValueKey(price.observationId),
      title: Text(price.analysis.schema.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${PriceResultCard.amount(price.totalPrice)} € per ${PriceResultCard.amount(price.quantity)} ${price.displayUnit} · ${date.day}/${date.month}/${date.year}',
          ),
          Text('${_unitCost(price.unitCost)} €/${price.displayUnit}'),
        ],
      ),
      trailing: IconButton(
        key: ValueKey('delete-${price.observationId}'),
        tooltip: 'Elimina prezzo',
        icon: const Icon(Icons.delete_outline),
        onPressed: _busy ? null : () => _delete(record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    key: _messenger,
    child: Scaffold(
      bottomNavigationBar: const SafeArea(child: AdvertisingBanner()),
      appBar: AppBar(
        title: const Text('Prezzi salvati'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ArchivePage()),
            ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    const SavingsFailure(
                      SavingsFailureKind.storageError,
                    ).message,
                  ),
                  TextButton(onPressed: _reload, child: const Text('Riprova')),
                ],
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
          final groups = <(String, String), List<SavedPrice>>{};
          for (final observation in observations) {
            final price = observation.price;
            groups
                .putIfAbsent((
                  price.categoryKey,
                  price.canonicalMetric,
                ), () => [])
                .add(observation);
          }
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Questi prezzi sono usati nei confronti. L’archivio precedente resta escluso. Non sono acquisti registrati.',
                ),
              ),
              for (final entries in groups.values) ...[
                _summary(entries),
                ...entries.map(_observation),
              ],
            ],
          );
        },
      ),
    ),
  );
}
