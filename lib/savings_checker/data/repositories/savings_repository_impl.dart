import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_store.dart';
import 'package:risparmiai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/models/category_reference_model.dart';
import 'package:risparmiai/savings_checker/domain/entities/product_analysis.dart';
import 'package:risparmiai/savings_checker/domain/entities/product_category.dart';
import 'package:risparmiai/savings_checker/domain/repositories/savings_repository.dart';
import 'package:risparmiai/savings_checker/domain/services/savings_calculator_service.dart';

class SavingsRepositoryImpl implements SavingsRepository {
  SavingsRepositoryImpl({
    AiSavingsClient? aiClient,
    OpenAiSavingsClient? openAiClient,
    SavingsCalculatorService? calculator,
    CategoryReferenceStore? categoryStore,
    this.useMockData = false,
  })  : _aiClient = aiClient ?? openAiClient,
        _calculator = calculator ?? const SavingsCalculatorService(),
        _categoryStore = categoryStore ?? const CategoryReferenceStore();

  final AiSavingsClient? _aiClient;
  final SavingsCalculatorService _calculator;
  final CategoryReferenceStore _categoryStore;
  final bool useMockData;

  @override
  Future<List<ProductAnalysis>> analyzeProducts({
    required String userPrompt,
  }) async {
    final normalizedPrompt = userPrompt.trim();
    if (!_looksLikeRealProductPrompt(normalizedPrompt)) {
      throw StateError('Ciao! Inserisci un elemento da valutare e ti aiuterò.');
    }

    if (useMockData || _aiClient == null) {
      debugPrint('Risparmiai repository: using mock data for prompt "$userPrompt"');
      return _buildMockProductsForPrompt(userPrompt);
    }

    debugPrint('Risparmiai repository: calling AI provider for prompt "$userPrompt"');

    try {
      final normalizedInput = userPrompt.trim();
      final categories = await _categoryStore.loadCategories();
      final catalogJson = jsonEncode(<String, dynamic>{
        'categories': categories.map((category) => category.toJson()).toList(growable: false),
      });

      final parsedPayload = await _aiClient.analyzeProductWithCatalog(normalizedInput, catalogJson);
      final productData = parsedPayload['product'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final categoryMatch = parsedPayload['category_match'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final matchedCategory = categoryMatch['category'] as Map<String, dynamic>?;

      final categoryKey = (productData['category_key'] ?? matchedCategory?['key'] ?? 'custom_category').toString();
      final totalUnitsCount = _calculateTotalUnits(productData);
      final totalPrice = _asDouble(productData['total_price']);
      final brand = (productData['brand'] ?? 'Brand sconosciuto').toString();
      final primaryUnitName = (productData['primary_unit_name'] ?? matchedCategory?['primary_unit'] ?? 'unità').toString();
      final category = _mapCategoryKeyToEnum(categoryKey);
      final attributes = _normalizeSpecificAttributes(productData['specific_attributes'] as Map<String, dynamic>? ?? const <String, dynamic>{});

      final currentUnitCost = totalUnitsCount > 0 ? totalPrice / totalUnitsCount : 0.0;

      // Aggiorna sempre lo store (cheapest + media) ad ogni analisi valida,
      // indipendentemente da is_exact_match/needs_update: ogni prezzo
      // osservato contribuisce alla storia della categoria.
      CategoryReferenceModel? updatedCategory;
      if (categoryKey.isNotEmpty && currentUnitCost > 0) {
        final proposedCategory = CategoryReferenceModel(
          key: categoryKey,
          displayName: (matchedCategory?['display_name'] ?? categoryKey).toString(),
          primaryUnit: primaryUnitName,
          averageUnitCost: matchedCategory != null ? _asDouble(matchedCategory['average_unit_cost']) : currentUnitCost,
          requiredAttributes: _readStringList(matchedCategory?['required_attributes']),
        );

        await _categoryStore.upsertCategoryWithObservedUnitCost(proposedCategory, currentUnitCost);
        final refreshed = await _categoryStore.loadCustomCategories();
        updatedCategory = refreshed.where((item) => item.key == categoryKey).cast<CategoryReferenceModel?>().firstOrNull;
      }

      final product = ProductAnalysis(
        id: 'product_${DateTime.now().microsecondsSinceEpoch}',
        productName: _defaultProductNameForCategory(category),
        brand: brand,
        category: category,
        totalPrice: totalPrice,
        primaryUnitName: primaryUnitName,
        totalUnitsCount: totalUnitsCount,
        specificAttributes: attributes,
        analysisSummary: _buildAnalysisSummary(primaryUnitName, currentUnitCost, updatedCategory),
      );

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

  bool _looksLikeRealProductPrompt(String prompt) {
    if (prompt.isEmpty || prompt.length < 6) {
      return false;
    }

    final lowered = prompt.toLowerCase();
    final hasLetters = RegExp(r'[a-zà-ù]').hasMatch(lowered);
    final hasNumber = RegExp(r'\d').hasMatch(lowered);
    final hasMeaningfulWords = RegExp(r'\b(carta|igienica|detergente|lavastoviglie|pasta|latte|pane|acqua|cibo|biscotti|sapone|shampoo|pastiglie|rotoli|strappi|euro|€|prezzo|kg|litro|ml|gr|g)\b').hasMatch(lowered);

    return hasLetters && (hasNumber || hasMeaningfulWords);
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

  List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }

    return value
        .map((entry) => entry.toString())
        .where((entry) => entry.trim().isNotEmpty)
        .toList(growable: false);
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

  String _buildAnalysisSummary(String primaryUnitName, double currentUnitCost, CategoryReferenceModel? updatedCategory) {
    if (updatedCategory == null || updatedCategory.entriesCount <= 1) {
      return 'Il prezzo del prodotto indicato è €${currentUnitCost.toStringAsFixed(4)}/$primaryUnitName. '
          'Non ho ancora uno storico per questa categoria: sarà il primo riferimento salvato.';
    }

    final cheapest = updatedCategory.averageUnitCost;
    final average = updatedCategory.averageOfAllEntries;

    final isNewRecord = currentUnitCost <= cheapest;
    final comparisonText = isNewRecord
        ? 'È il prezzo più conveniente registrato finora per questa categoria.'
        : 'In archivio il prezzo più conveniente registrato è €${cheapest.toStringAsFixed(4)}/$primaryUnitName.';

    return 'Il prezzo del prodotto indicato è €${currentUnitCost.toStringAsFixed(4)}/$primaryUnitName. '
        '$comparisonText '
        'Media storica su ${updatedCategory.entriesCount} rilevazioni: €${average.toStringAsFixed(4)}/$primaryUnitName.';
  }

  List<ProductAnalysis> _buildMockProductsForPrompt(String userPrompt) {
    final normalizedPrompt = userPrompt.toLowerCase();

    final mockProducts = <ProductAnalysis>{
      ProductAnalysis(
        id: 'carta_igienica_1',
        productName: 'Carta igienica',
        brand: '',
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
      ),
      ProductAnalysis(
        id: 'detersivo_1',
        productName: 'Detersivo liquido',
        brand: '',
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
      ),
      ProductAnalysis(
        id: 'pane_1',
        productName: 'Pane bianco',
        brand: '',
        category: ProductCategory.bakery,
        totalPrice: 2.1,
        primaryUnitName: 'kg',
        totalUnitsCount: 1,
        specificAttributes: <String, dynamic>{
          'weightKg': 1.0,
          'freshnessHours': 12,
        },
        analysisSummary: 'Costo medio, ottimo per uso quotidiano.',
      ),
      ProductAnalysis(
        id: 'pastiglie_lavastoviglie_1',
        productName: 'Pastiglie lavastoviglie',
        brand: '',
        category: ProductCategory.household,
        totalPrice: 14.0,
        primaryUnitName: 'pastiglia',
        totalUnitsCount: 106,
        specificAttributes: <String, dynamic>{
          'tabs_count': 106,
          'pack_size': '106',
          'brand': '',
        },
        analysisSummary: 'Mock generico per pastiglie lavastoviglie.',
      ),
    }.toList();

    final matched = mockProducts.where((product) {
      final haystack = '${product.productName} ${product.brand} ${product.primaryUnitName}'.toLowerCase();
      final promptContains = <String>[
        'carta', 'igienica', 'detersivo', 'pane', 'pastiglie', 'lavastoviglie', 'capsule', 'milk', 'latte', 'olio', 'spazzatura', 'bag', 'sacchetto'
      ];

      for (final keyword in promptContains) {
        if (normalizedPrompt.contains(keyword) && haystack.contains(keyword)) {
          return true;
        }
      }

      if (normalizedPrompt.contains('lavastoviglie') && haystack.contains('lavastoviglie')) {
        return true;
      }

      return false;
    }).toList(growable: false);

    if (matched.isNotEmpty) {
      return matched;
    }

    return <ProductAnalysis>[mockProducts.first];
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}