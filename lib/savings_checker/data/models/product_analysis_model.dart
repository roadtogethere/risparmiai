import 'package:spesai/savings_checker/domain/entities/product_analysis.dart';
import 'package:spesai/savings_checker/domain/entities/product_category.dart';

class ProductAnalysisModel extends ProductAnalysis {
  const ProductAnalysisModel({
    required super.id,
    required super.productName,
    required super.brand,
    required super.category,
    required super.totalPrice,
    required super.primaryUnitName,
    required super.totalUnitsCount,
    required super.specificAttributes,
    super.analysisSummary,
  });

  factory ProductAnalysisModel.fromJson(Map<String, dynamic> json) {
    final rawCategory = json['category'] ?? json['productCategory'];
    final category = _parseCategory(rawCategory);

    final rawSpecificAttributes = json['specificAttributes'];
    final Map<String, dynamic> specificAttributes = <String, dynamic>{};

    if (rawSpecificAttributes is Map) {
      for (final entry in rawSpecificAttributes.entries) {
        final key = entry.key.toString();
        specificAttributes[key] = entry.value;
      }
    }

    return ProductAnalysisModel(
      id: (json['id'] ?? json['productId'] ?? _generateIdFromBrand(json)).toString(),
      productName: _stringFromJson(json['productName'] ?? json['name'], fallback: 'Prodotto sconosciuto'),
      brand: _stringFromJson(json['brand'], fallback: 'Brand sconosciuto'),
      category: category,
      totalPrice: _doubleFromJson(json['totalPrice'], fallback: 0),
      primaryUnitName: _stringFromJson(json['primaryUnitName'] ?? json['unitName'], fallback: 'unità'),
      totalUnitsCount: _doubleFromJson(json['totalUnitsCount'] ?? json['unitsCount'], fallback: 1),
      specificAttributes: specificAttributes,
      analysisSummary: json['analysisSummary'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'productName': productName,
      'brand': brand,
      'category': category.name,
      'totalPrice': totalPrice,
      'primaryUnitName': primaryUnitName,
      'totalUnitsCount': totalUnitsCount,
      'specificAttributes': specificAttributes,
      if (analysisSummary != null) 'analysisSummary': analysisSummary,
    };
  }

  static ProductCategory _parseCategory(dynamic value) {
    if (value is ProductCategory) {
      return value;
    }

    final normalized = value?.toString().toLowerCase() ?? 'other';

    switch (normalized) {
      case 'pantry':
      case 'alimentare':
        return ProductCategory.pantry;
      case 'household':
      case 'casa':
        return ProductCategory.household;
      case 'bakery':
      case 'pane':
      case 'forno':
        return ProductCategory.bakery;
      case 'beverage':
      case 'bevande':
        return ProductCategory.beverage;
      case 'personalcare':
      case 'cura_personale':
      case 'cura personale':
        return ProductCategory.personalCare;
      default:
        return ProductCategory.other;
    }
  }

  static String _stringFromJson(dynamic value, {required String fallback}) {
    if (value == null) {
      return fallback;
    }

    if (value is String) {
      return value.trim().isEmpty ? fallback : value.trim();
    }

    return value.toString();
  }

  static double _doubleFromJson(dynamic value, {required double fallback}) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      return parsed ?? fallback;
    }

    return fallback;
  }

  static String _generateIdFromBrand(Map<String, dynamic> json) {
    final name = json['productName'] ?? json['name'] ?? 'product';
    final brand = json['brand'] ?? 'brand';
    return '${brand}_${name}_${DateTime.now().microsecondsSinceEpoch}'.replaceAll(' ', '_').toLowerCase();
  }
}
