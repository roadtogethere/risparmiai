import 'package:flutter/material.dart';
import '../../domain/entities/quantity_plan.dart';
import '../models/analysis_display.dart';

class RecognizedFacts extends StatelessWidget {
  const RecognizedFacts({super.key, required this.analysis});
  final PlannerAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final operands = analysis.plan.operation?.operands ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The current planner has no structured product name or brand.
        Text(
          'Categoria: ${AnalysisDisplay.label(analysis.schema.displayName)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: ValueKey('${analysis.id}:${analysis.revision}'),
          tilePadding: EdgeInsets.zero,
          title: Text(
            analysis.revision > 1 ? 'Dati aggiornati' : 'Dati riconosciuti',
          ),
          children: [
            for (final entry in analysis.plan.facts.entries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${AnalysisDisplay.factLabel(analysis, entry.key)}: '
                  '${AnalysisDisplay.factValue(entry.value)}'
                  '${operands.contains(entry.key) ? ' · usato per la quantità' : ''}'
                  '${entry.value.isConfirmed ? '' : ' · da confermare'}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Puoi correggere i dati in chat, per esempio: «Scusa, la quantità è diversa». Per un altro prodotto usa «Nuova analisi».',
        ),
      ],
    );
  }
}
