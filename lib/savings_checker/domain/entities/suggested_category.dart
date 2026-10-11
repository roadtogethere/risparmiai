class SuggestedCategory {
  const SuggestedCategory({
    required this.categoryKey,
    required this.displayName,
    required this.primaryUnitName,
    required this.averageUnitCost,
    required this.aliases,
    required this.requiredAttributes,
  });

  final String categoryKey;
  final String displayName;
  final String primaryUnitName;
  final double averageUnitCost;
  final List<String> aliases;
  final List<String> requiredAttributes;

  factory SuggestedCategory.fromJson(Map<String, dynamic> json) {
    final aliasList = json['aliases'];
    final required = json['required_attributes'];

    return SuggestedCategory(
      categoryKey: (json['category_key'] ?? json['key'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['name'] ?? '').toString(),
      primaryUnitName: (json['primary_unit_name'] ?? json['primary_unit'] ?? '')
          .toString(),
      averageUnitCost: (json['average_unit_cost'] is num)
          ? (json['average_unit_cost'] as num).toDouble()
          : double.tryParse(json['average_unit_cost']?.toString() ?? '') ?? 0,
      aliases: aliasList is List
          ? aliasList.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      requiredAttributes: required is List
          ? required.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'category_key': categoryKey,
      'display_name': displayName,
      'primary_unit_name': primaryUnitName,
      'average_unit_cost': averageUnitCost,
      'aliases': aliases,
      'required_attributes': requiredAttributes,
    };
  }
}
