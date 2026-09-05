import 'package:risparmiai/savings_checker/domain/entities/category_reference.dart';

class CategoryReferenceModel extends CategoryReference {
  const CategoryReferenceModel({
    required super.key,
    required super.displayName,
    required super.primaryUnit,
    required super.averageUnitCost,
    required super.requiredAttributes,
  });

  factory CategoryReferenceModel.fromJson(Map<String, dynamic> json) {
    return CategoryReferenceModel(
      key: (json['key'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      primaryUnit: (json['primary_unit'] ?? '').toString(),
      averageUnitCost: (json['average_unit_cost'] is num)
          ? (json['average_unit_cost'] as num).toDouble()
          : double.tryParse(json['average_unit_cost']?.toString() ?? '') ?? 0,
      requiredAttributes: (json['required_attributes'] is List)
          ? (json['required_attributes'] as List).map((item) => item.toString()).toList(growable: false)
          : const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'display_name': displayName,
      'primary_unit': primaryUnit,
      'average_unit_cost': averageUnitCost,
      'required_attributes': requiredAttributes,
    };
  }
}
