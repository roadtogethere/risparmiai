import 'package:risparmiai/savings_checker/domain/entities/category_reference.dart';
import 'package:risparmiai/savings_checker/domain/entities/required_attribute.dart';

class CategoryReferenceModel extends CategoryReference {
  const CategoryReferenceModel({
    required super.key,
    required super.displayName,
    required super.primaryUnit,
    required super.averageUnitCost,
    required super.requiredAttributes,
    super.canonicalMetric,
    super.sumOfUnitCosts = 0,
    super.entriesCount = 0,
  });

  factory CategoryReferenceModel.fromJson(Map<String, dynamic> json) {
    final rawRequiredAttributes = json['required_attributes'];

    return CategoryReferenceModel(
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

  factory CategoryReferenceModel.fromEntity(CategoryReference entity) {
    return CategoryReferenceModel(
      key: entity.key,
      displayName: entity.displayName,
      primaryUnit: entity.primaryUnit,
      canonicalMetric: entity.canonicalMetric,
      averageUnitCost: entity.averageUnitCost,
      requiredAttributes: entity.requiredAttributes,
      sumOfUnitCosts: entity.sumOfUnitCosts,
      entriesCount: entity.entriesCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'display_name': displayName,
      'primary_unit': primaryUnit,
      if (canonicalMetric != null) 'canonical_metric': canonicalMetric,
      'average_unit_cost': averageUnitCost,
      'sum_of_unit_costs': sumOfUnitCosts,
      'entries_count': entriesCount,
      'required_attributes': requiredAttributes
          .map((attribute) => attribute.toJson())
          .toList(growable: false),
    };
  }

  CategoryReferenceModel copyWith({
    String? key,
    String? displayName,
    String? primaryUnit,
    String? canonicalMetric,
    double? averageUnitCost,
    double? sumOfUnitCosts,
    int? entriesCount,
    List<RequiredAttribute>? requiredAttributes,
  }) {
    return CategoryReferenceModel(
      key: key ?? this.key,
      displayName: displayName ?? this.displayName,
      primaryUnit: primaryUnit ?? this.primaryUnit,
      canonicalMetric: canonicalMetric ?? this.canonicalMetric,
      averageUnitCost: averageUnitCost ?? this.averageUnitCost,
      sumOfUnitCosts: sumOfUnitCosts ?? this.sumOfUnitCosts,
      entriesCount: entriesCount ?? this.entriesCount,
      requiredAttributes: requiredAttributes ?? this.requiredAttributes,
    );
  }

  /// Registra un nuovo prezzo unitario osservato per questa categoria:
  /// aggiorna il minimo storico (averageUnitCost, mostrato come "migliore
  /// convenienza") e accumula somma/conteggio per la media storica.
  CategoryReferenceModel withNewObservedUnitCost(double unitCost) {
    if (unitCost <= 0) {
      return this;
    }

    final isFirstEntry = entriesCount == 0;
    final newCheapest = isFirstEntry
        ? unitCost
        : (unitCost < averageUnitCost ? unitCost : averageUnitCost);

    return copyWith(
      averageUnitCost: newCheapest,
      sumOfUnitCosts: sumOfUnitCosts + unitCost,
      entriesCount: entriesCount + 1,
    );
  }
}
