import 'package:risparmiai/savings_checker/domain/entities/product_analysis.dart';
import 'package:risparmiai/savings_checker/domain/entities/product_category.dart';

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
    super.categoryKey,
    super.canonicalMetric,
  });

  factory ProductAnalysisModel.fromJson(Map<String, dynamic> json) {
    final rawCategory =
        json['category'] ?? json['productCategory'] ?? json['categoryKey'];
    final category = _parseCategory(rawCategory);

    final rawSpecificAttributes = json['specificAttributes'];
    final Map<String, dynamic> specificAttributes = <String, dynamic>{};

    if (rawSpecificAttributes is Map) {
      for (final entry in rawSpecificAttributes.entries) {
        final key = entry.key.toString();
        specificAttributes[key] = entry.value;
      }
    }

    final primaryUnitName = _normalizePrimaryUnitName(
      json: json,
      category: category,
      specificAttributes: specificAttributes,
    );
    final totalUnitsCount = _normalizeTotalUnitsCount(
      json: json,
      category: category,
      specificAttributes: specificAttributes,
      primaryUnitName: primaryUnitName,
    );

    return ProductAnalysisModel(
      id: (json['id'] ?? json['productId'] ?? _generateIdFromBrand(json))
          .toString(),
      productName: _stringFromJson(
        json['productName'] ?? json['name'],
        fallback: 'Prodotto sconosciuto',
      ),
      brand: _stringFromJson(json['brand'], fallback: 'Brand sconosciuto'),
      category: category,
      totalPrice: _doubleFromJson(json['totalPrice'], fallback: 0),
      primaryUnitName: primaryUnitName,
      totalUnitsCount: totalUnitsCount,
      specificAttributes: specificAttributes,
      analysisSummary: json['analysisSummary'] as String?,
      categoryKey: json['categoryKey'] as String?,
      canonicalMetric: json['canonicalMetric'] as String?,
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
      if (categoryKey != null) 'categoryKey': categoryKey,
      if (canonicalMetric != null) 'canonicalMetric': canonicalMetric,
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

  static String _normalizePrimaryUnitName({
    required Map<String, dynamic> json,
    required ProductCategory category,
    required Map<String, dynamic> specificAttributes,
  }) {
    final rawUnit = (json['primaryUnitName'] ?? json['unitName'] ?? '')
        .toString()
        .trim();
    final normalizedUnit = rawUnit.isEmpty ? '' : rawUnit.toLowerCase();
    switch (normalizedUnit) {
      case 'strappo':
      case 'strappi':
      case 'stramppi':
      case 'sheet':
      case 'sheets':
        return 'strappo';
      case 'rotolo':
      case 'rotoli':
      case 'rotolii':
        return 'rotolo';
      case 'litro':
      case 'litri':
      case 'litrii':
        return 'litro';
      case 'kg':
      case 'kilogrammo':
        return 'kg';
      case 'capsula':
      case 'capsule':
        return 'capsula';
      case 'lavaggio':
      case 'lavaggi':
        return 'lavaggio';
      case 'fetta':
      case 'fette':
        return 'fetta';
      case 'sacchetto':
      case 'sacchetti':
        return 'sacchetto';
      default:
        return rawUnit.isEmpty ? 'unità' : rawUnit;
    }
  }

  static double _normalizeTotalUnitsCount({
    required Map<String, dynamic> json,
    required ProductCategory category,
    required Map<String, dynamic> specificAttributes,
    required String primaryUnitName,
  }) {
    final explicitCount = _doubleFromJson(
      json['totalUnitsCount'] ??
          json['unitsCount'] ??
          json['total_units_count'],
      fallback: -1,
    );
    if (explicitCount > 0) {
      return explicitCount;
    }

    final rolls = _doubleFromJson(
      json['rollsCount'] ??
          json['rolls_count'] ??
          json['piecesCount'] ??
          json['pieces_count'],
      fallback: 0,
    );
    final sheetsPerRoll = _doubleFromJson(
      json['sheetsPerRoll'] ??
          json['sheets_per_roll'] ??
          json['strappiPerRotolo'] ??
          json['strappi_per_rotolo'],
      fallback: 0,
    );

    if (primaryUnitName == 'strappo') {
      if (rolls > 0 && sheetsPerRoll > 0) {
        return rolls * sheetsPerRoll;
      }
    }

    final totalAttribute = _doubleFromJson(
      specificAttributes['totalUnitsCount'] ??
          specificAttributes['total_units_count'],
      fallback: 0,
    );
    if (totalAttribute > 0) {
      return totalAttribute;
    }

    final specificTotal = _doubleFromJson(
      specificAttributes['totalUnits'] ?? specificAttributes['total_units'],
      fallback: 0,
    );
    if (specificTotal > 0) {
      return specificTotal;
    }

    return 1;
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
    return '${brand}_${name}_${DateTime.now().microsecondsSinceEpoch}'
        .replaceAll(' ', '_')
        .toLowerCase();
  }
}
