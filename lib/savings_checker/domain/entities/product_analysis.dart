import 'product_category.dart';

class ProductAnalysis {
  const ProductAnalysis({
    required this.id,
    required this.productName,
    required this.brand,
    required this.category,
    required this.totalPrice,
    required this.primaryUnitName,
    required this.totalUnitsCount,
    required this.specificAttributes,
    this.analysisSummary,
    this.categoryKey,
    this.canonicalMetric,
  }) : assert(totalPrice >= 0, 'totalPrice must be >= 0'),
       assert(totalUnitsCount > 0, 'totalUnitsCount must be > 0');

  final String id;
  final String productName;
  final String brand;
  final ProductCategory category;
  final double totalPrice;
  final String primaryUnitName;
  final double totalUnitsCount;
  final Map<String, dynamic> specificAttributes;
  final String? analysisSummary;
  final String? categoryKey;
  final String? canonicalMetric;

  double get unitCost => totalPrice / totalUnitsCount;

  ProductAnalysis copyWith({
    String? id,
    String? productName,
    String? brand,
    ProductCategory? category,
    double? totalPrice,
    String? primaryUnitName,
    double? totalUnitsCount,
    Map<String, dynamic>? specificAttributes,
    String? analysisSummary,
    String? categoryKey,
    String? canonicalMetric,
  }) {
    return ProductAnalysis(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      totalPrice: totalPrice ?? this.totalPrice,
      primaryUnitName: primaryUnitName ?? this.primaryUnitName,
      totalUnitsCount: totalUnitsCount ?? this.totalUnitsCount,
      specificAttributes:
          specificAttributes ??
          Map<String, dynamic>.from(this.specificAttributes),
      analysisSummary: analysisSummary ?? this.analysisSummary,
      categoryKey: categoryKey ?? this.categoryKey,
      canonicalMetric: canonicalMetric ?? this.canonicalMetric,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ProductAnalysis &&
        other.id == id &&
        other.productName == productName &&
        other.brand == brand &&
        other.category == category &&
        other.totalPrice == totalPrice &&
        other.primaryUnitName == primaryUnitName &&
        other.totalUnitsCount == totalUnitsCount &&
        other.specificAttributes == specificAttributes &&
        other.analysisSummary == analysisSummary &&
        other.categoryKey == categoryKey &&
        other.canonicalMetric == canonicalMetric;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      productName,
      brand,
      category,
      totalPrice,
      primaryUnitName,
      totalUnitsCount,
      Object.hashAll(specificAttributes.entries),
      analysisSummary,
      categoryKey,
      canonicalMetric,
    );
  }
}
