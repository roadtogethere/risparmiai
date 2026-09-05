import 'package:flutter/foundation.dart';

import 'package:spesai/savings_checker/data/datasources/category_reference_data_source.dart';
import 'package:spesai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:spesai/savings_checker/data/matchers/category_matcher.dart';
import 'package:spesai/savings_checker/domain/entities/category_reference.dart';
import 'package:spesai/savings_checker/domain/entities/product_analysis.dart';
import 'package:spesai/savings_checker/domain/entities/product_category.dart';
import 'package:spesai/savings_checker/domain/repositories/savings_repository.dart';
import 'package:spesai/savings_checker/domain/services/savings_calculator_service.dart';

class SavingsRepositoryImpl implements SavingsRepository {
  SavingsRepositoryImpl({
    OpenAiSavingsClient? openAiClient,
    SavingsCalculatorService? calculator,
    CategoryMatcher? categoryMatcher,
    this.useMockData = false,
  })  : _openAiClient = openAiClient,
        _calculator = calculator ?? const SavingsCalculatorService(),
        _matcher = categoryMatcher ?? CategoryMatcher();

  final OpenAiSavingsClient? _openAiClient;
  final SavingsCalculatorService _calculator;
  final CategoryMatcher _matcher;
  final bool useMockData;

  @override
  Future<List<ProductAnalysis>> analyzeProducts({
    required String userPrompt,
  }) async {
    if (useMockData || _openAiClient == null) {
      return _buildMockProductsForPrompt(userPrompt);
    }

    try {
      final normalizedInput = _normalizeUserPrompt(userPrompt);
      final matchResult = await _matcher.match(normalizedInput);
      final parsedPayload = await _openAiClient.extractRawProductData(normalizedInput);
      final defaultCategory = matchResult.defaultCategory ??
          (matchResult.suggestedCategory != null
              ? await _findCategoryFromKey(matchResult.suggestedCategory!.categoryKey)
              : null);
      final benchmarkCategory = defaultCategory ?? await _findCategoryFromKey(parsedPayload['category_key'] as String?);

      final totalUnitsCount = _calculateTotalUnits(parsedPayload);
      final totalPrice = _asDouble(parsedPayload['total_price']);
      final brand = (parsedPayload['brand'] ?? 'Brand sconosciuto').toString();
      final primaryUnitName = (parsedPayload['primary_unit_name'] ?? benchmarkCategory?.primaryUnit ?? 'unità').toString();
      final category = _mapCategoryKeyToEnum(
        benchmarkCategory?.key ?? (parsedPayload['category_key'] ?? 'custom_category').toString(),
      );

      final product = ProductAnalysis(
        id: 'product_${DateTime.now().microsecondsSinceEpoch}',
        productName: _defaultProductNameForCategory(category),
        brand: brand,
        category: category,
        totalPrice: totalPrice,
        primaryUnitName: primaryUnitName,
        totalUnitsCount: totalUnitsCount,
        specificAttributes: _normalizeSpecificAttributes(parsedPayload['specific_attributes'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
        analysisSummary: _buildAnalysisSummary(primaryUnitName, totalPrice, totalUnitsCount, benchmarkCategory),
      );

      if (benchmarkCategory != null) {
        final comparison = _calculator.compareAgainstAverage(
          product: product,
          products: <ProductAnalysis>[product],
        );

        return <ProductAnalysis>[product.copyWith(analysisSummary: comparison.message)];
      }

      return <ProductAnalysis>[product];
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('SavingsRepositoryImpl analyzeProducts error: $error');
        rethrow;
      }
      return _buildMockProductsForPrompt(userPrompt);
    }
  }

  @override
  Future<ProductAnalysis> identifyBestValue({
    required ProductAnalysis currentProduct,
    required List<ProductAnalysis> alternatives,
  }) async {
    final allProducts = <ProductAnalysis>[currentProduct, ...alternatives];
    final comparison = _calculator.bestValueProduct(products: allProducts);

    return comparison;
  }

  String _normalizeUserPrompt(String userPrompt) {
    return CategoryMatcher.normalizeText(userPrompt);
  }

  ProductCategory _mapCategoryKeyToEnum(String categoryKey) {
    switch (categoryKey) {
      case 'toilet_paper':
        return ProductCategory.household;
      case 'laundry_detergent_liquid':
        return ProductCategory.household;
      case 'dishwasher_tabs':
        return ProductCategory.household;
      case 'sliced_bread':
        return ProductCategory.bakery;
      case 'uht_milk':
        return ProductCategory.beverage;
      default:
        return ProductCategory.other;
    }
  }

  String _defaultProductNameForCategory(ProductCategory category) {
    switch (category) {
      case ProductCategory.household:
        return 'Prodotto casa';
      case ProductCategory.bakery:
        return 'Pane';
      case ProductCategory.beverage:
        return 'Bevanda';
      default:
        return 'Prodotto';
    }
  }

  Future<CategoryReference?> _findCategoryFromKey(String? categoryKey) async {
    if (categoryKey == null || categoryKey.isEmpty) {
      return null;
    }

    final items = await const CategoryReferenceDataSource().loadDefaultCategories();
    for (final category in items) {
      if (category.key == categoryKey) {
        return category;
      }
    }

    return null;
  }

  double _calculateTotalUnits(Map<String, dynamic> payload) {
    final unitsPerPackage = _asDouble(payload['units_per_package'] ?? 1);
    final subUnits = payload['sub_units_per_package'];

    if (subUnits != null && subUnits.toString().trim().isNotEmpty) {
      return unitsPerPackage * _asDouble(subUnits);
    }

    return unitsPerPackage;
  }

  Map<String, dynamic> _normalizeSpecificAttributes(Map<String, dynamic> source) {
    final normalized = <String, dynamic>{};
    for (final entry in source.entries) {
      normalized[entry.key.toString()] = entry.value;
    }
    return normalized;
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  String _buildAnalysisSummary(String primaryUnitName, double totalPrice, double totalUnitsCount, CategoryReference? benchmarkCategory) {
    final benchmarkText = benchmarkCategory == null
        ? 'Benchmark non disponibile.'
        : 'Benchmark di riferimento: ${benchmarkCategory.averageUnitCost.toStringAsFixed(4)} €/ $primaryUnitName';

    return 'Prezzo totale: €$totalPrice; totale unità: $totalUnitsCount $primaryUnitName. $benchmarkText';
  }

  List<ProductAnalysis> _buildMockProductsForPrompt(String userPrompt) {
    final normalizedPrompt = _normalizeUserPrompt(userPrompt);

    final productA = ProductAnalysis(
      id: 'carta_igienica_1',
      productName: 'Carta igienica',
      brand: 'Migliore',
      category: ProductCategory.household,
      totalPrice: 5.99,
      primaryUnitName: 'strappo',
      totalUnitsCount: 6000,
      specificAttributes: <String, dynamic>{
        'rollsCount': 12,
        'sheetsPerRoll': 500,
        'material': 'cellulosa',
      },
      analysisSummary: 'Prezzo corretto espresso per strappo, con totale di 6000 unità.',
    );

    final productB = ProductAnalysis(
      id: 'detersivo_1',
      productName: 'Detersivo liquido',
      brand: 'EcoCare',
      category: ProductCategory.household,
      totalPrice: 5.99,
      primaryUnitName: 'litro',
      totalUnitsCount: 2.5,
      specificAttributes: <String, dynamic>{
        'liters': 2.5,
        'washes': 40,
        'ecoFriendly': true,
      },
      analysisSummary: 'Conveniente per litro e resa elevata.',
    );

    final productC = ProductAnalysis(
      id: 'pane_1',
      productName: 'Pane bianco',
      brand: 'Forno del Borgo',
      category: ProductCategory.bakery,
      totalPrice: 2.1,
      primaryUnitName: 'kg',
      totalUnitsCount: 1,
      specificAttributes: <String, dynamic>{
        'weightKg': 1.0,
        'freshnessHours': 12,
      },
      analysisSummary: 'Costo medio, ottimo per uso quotidiano.',
    );

    final fallbackProducts = <ProductAnalysis>[productA, productB, productC];

    if (normalizedPrompt.contains('carta') || normalizedPrompt.contains('igienica')) {
      return <ProductAnalysis>[productA];
    }

    if (normalizedPrompt.contains('detersivo')) {
      return <ProductAnalysis>[productB];
    }

    if (normalizedPrompt.contains('pane')) {
      return <ProductAnalysis>[productC];
    }

    return fallbackProducts;
  }
}
