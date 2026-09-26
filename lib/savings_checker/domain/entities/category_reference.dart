import 'required_attribute.dart';

/// A valid observation cannot be aggregated under a different denominator.
class UnitMetricMismatch implements Exception {
  const UnitMetricMismatch(this.observationMetric, this.expectedMetric);

  final String observationMetric;
  final String expectedMetric;
}

class CategorySchemaMismatch implements Exception {
  const CategorySchemaMismatch(this.message);
  final String message;
}

class CategoryReference {
  const CategoryReference({
    required this.key,
    required this.displayName,
    required this.primaryUnit,
    required this.averageUnitCost,
    required this.requiredAttributes,
    this.canonicalMetric,
    this.sumOfUnitCosts = 0,
    this.entriesCount = 0,
  });

  final String key;
  final String displayName;
  final String primaryUnit;
  // Null means legacy/unverified: never infer this identifier from a UI label.
  final String? canonicalMetric;

  void validateSchema({bool requireCanonicalMetric = false}) {
    if (key.trim().isEmpty ||
        displayName.trim().isEmpty ||
        primaryUnit.trim().isEmpty) {
      throw const FormatException('Incomplete category schema.');
    }
    if ((requireCanonicalMetric && canonicalMetric == null) ||
        (canonicalMetric != null &&
            !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(canonicalMetric!))) {
      throw const FormatException('Invalid canonical metric.');
    }
    final keys = <String>{};
    for (final attribute in requiredAttributes) {
      if (attribute.key.trim().isEmpty ||
          attribute.label.trim().isEmpty ||
          !keys.add(attribute.key)) {
        throw const FormatException('Invalid required attributes.');
      }
    }
  }

  void validateObservation({
    required String unit,
    String? metric,
    Map<String, dynamic> attributes = const {},
  }) {
    if (canonicalMetric != null) {
      if (metric != canonicalMetric) {
        throw UnitMetricMismatch(metric ?? unit, canonicalMetric!);
      }
    } else {
      String normalize(String text) =>
          text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (normalize(unit) != normalize(primaryUnit)) {
        throw UnitMetricMismatch(unit, primaryUnit);
      }
    }
    for (final attribute in requiredAttributes) {
      final value = attributes[attribute.key];
      if (value == null || (value is String && value.trim().isEmpty)) {
        throw CategorySchemaMismatch(
          'Missing required attribute: ${attribute.key}',
        );
      }
    }
  }

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
      canonicalMetric: json['canonical_metric'] as String?,
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
