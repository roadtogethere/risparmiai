import 'required_attribute.dart';

/// A valid observation cannot be aggregated under a different denominator.
class UnitMetricMismatch implements Exception {
  const UnitMetricMismatch(this.observationMetric, this.expectedMetric);

  final String observationMetric;
  final String expectedMetric;
}

class CategoryReference {
  const CategoryReference({
    required this.key,
    required this.displayName,
    required this.primaryUnit,
    required this.averageUnitCost,
    required this.requiredAttributes,
    this.sumOfUnitCosts = 0,
    this.entriesCount = 0,
  });

  final String key;
  final String displayName;
  final String primaryUnit;

  /// Il prezzo unitario più economico trovato finora per questa categoria.
  /// È il valore mostrato come benchmark/"migliore convenienza" in Archivio.
  final double averageUnitCost;

  /// Somma di tutti i prezzi unitari registrati nel tempo, usata per calcolare
  /// la media storica senza dover conservare ogni singolo valore.
  final double sumOfUnitCosts;

  /// Numero di volte in cui questa categoria è stata aggiornata con un nuovo prezzo.
  final int entriesCount;

  final List<RequiredAttribute> requiredAttributes;

  /// Media di tutti i prezzi unitari visti finora per questa categoria.
  /// Ricade sul prezzo più economico se non ci sono ancora dati storici.
  double get averageOfAllEntries =>
      entriesCount > 0 ? sumOfUnitCosts / entriesCount : averageUnitCost;

  factory CategoryReference.fromJson(Map<String, dynamic> json) {
    final rawRequiredAttributes = json['required_attributes'];

    return CategoryReference(
      key: (json['key'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      primaryUnit: (json['primary_unit'] ?? '').toString(),
      averageUnitCost: (json['average_unit_cost'] is num)
          ? (json['average_unit_cost'] as num).toDouble()
          : double.tryParse(json['average_unit_cost']?.toString() ?? '') ?? 0,
      sumOfUnitCosts: (json['sum_of_unit_costs'] is num)
          ? (json['sum_of_unit_costs'] as num).toDouble()
          : double.tryParse(json['sum_of_unit_costs']?.toString() ?? '') ?? 0,
      entriesCount: (json['entries_count'] is num)
          ? (json['entries_count'] as num).toInt()
          : int.tryParse(json['entries_count']?.toString() ?? '') ?? 0,
      requiredAttributes: rawRequiredAttributes is List
          ? rawRequiredAttributes
                .map(RequiredAttribute.fromJson)
                .toList(growable: false)
          : const <RequiredAttribute>[],
    );
  }
}
