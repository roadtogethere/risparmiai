class CategoryReference {
  const CategoryReference({
    required this.key,
    required this.displayName,
    required this.primaryUnit,
    required this.averageUnitCost,
    required this.requiredAttributes,
  });

  final String key;
  final String displayName;
  final String primaryUnit;
  final double averageUnitCost;
  final List<String> requiredAttributes;

  factory CategoryReference.fromJson(Map<String, dynamic> json) {
    final rawRequiredAttributes = json['required_attributes'];

    return CategoryReference(
      key: (json['key'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      primaryUnit: (json['primary_unit'] ?? '').toString(),
      averageUnitCost: (json['average_unit_cost'] is num)
          ? (json['average_unit_cost'] as num).toDouble()
          : double.tryParse(json['average_unit_cost']?.toString() ?? '') ?? 0,
      requiredAttributes: rawRequiredAttributes is List
          ? rawRequiredAttributes.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}
