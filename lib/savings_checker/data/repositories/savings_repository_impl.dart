import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:risparmiai/savings_checker/data/datasources/ai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/datasources/category_reference_store.dart';
import 'package:risparmiai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:risparmiai/savings_checker/data/models/category_reference_model.dart';
import 'package:risparmiai/savings_checker/domain/entities/product_analysis.dart';
import 'package:risparmiai/savings_checker/domain/entities/category_reference.dart';
import 'package:risparmiai/savings_checker/domain/entities/product_category.dart';
import 'package:risparmiai/savings_checker/domain/entities/required_attribute.dart';
import 'package:risparmiai/savings_checker/domain/repositories/savings_repository.dart';
import 'package:risparmiai/savings_checker/domain/services/savings_calculator_service.dart';

/// Legacy product/category_match and explicit demo path.
/// The live M4A application uses QuantityPlannerRepositoryImpl instead.
class SavingsRepositoryImpl implements SavingsRepository {
  SavingsRepositoryImpl({
    AiSavingsClient? aiClient,
    OpenAiSavingsClient? openAiClient,
    SavingsCalculatorService? calculator,
    CategoryReferenceStore? categoryStore,
    this.useMockData = false,
  }) : _aiClient = aiClient ?? openAiClient,
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

    if (useMockData) {
      debugPrint('Risparmiai repository: using mock data');
      return _buildMockProductsForPrompt(userPrompt);
    }

    debugPrint('Risparmiai repository: calling legacy AI adapter');

    final aiClient = _aiClient;
    if (aiClient == null) throw StateError('AI provider is not configured.');
    final normalizedInput = userPrompt.trim();
    final categories = await _categoryStore.loadCategories();
    final catalogJson = jsonEncode(<String, dynamic>{
      'categories': categories
          .map((category) => category.toJson())
          .toList(growable: false),
    });

    final parsedPayload = await aiClient.analyzeProductWithCatalog(
      normalizedInput,
      catalogJson,
    );
    final productData =
        parsedPayload['product'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final categoryMatch =
        parsedPayload['category_match'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final matchedCategory = categoryMatch['category'] as Map<String, dynamic>?;

    final categoryKey = _requiredText(
      productData['category_key'],
      'category_key',
    );
    final totalUnitsCount = _calculateTotalUnits(productData);
    final totalPrice = _requiredNumber(
      productData['total_price'],
      'total_price',
      allowZero: true,
    );
    final brand = (productData['brand'] ?? 'Brand sconosciuto').toString();
    final primaryUnitName = _requiredText(
      productData['primary_unit_name'],
      'primary_unit_name',
    );
    final category = _mapCategoryKeyToEnum(categoryKey);
    final attributes = _normalizeSpecificAttributes(
      productData['specific_attributes'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );

    if (matchedCategory == null || matchedCategory['key'] != categoryKey) {
      throw const CategorySchemaMismatch('Unresolved category identity.');
    }
    final knownCategory = categories
        .where((item) => item.key == categoryKey)
        .firstOrNull;
    final proposedCategory = CategoryReferenceModel(
      key: categoryKey,
      displayName: _requiredText(
        matchedCategory['display_name'],
        'display_name',
      ),
      primaryUnit: _requiredText(
        matchedCategory['primary_unit'],
        'primary_unit',
      ),
      canonicalMetric: matchedCategory['canonical_metric'] as String?,
      averageUnitCost: 0,
      requiredAttributes: _readRequiredAttributes(
        matchedCategory['required_attributes'],
      ),
    );
    final schema = knownCategory ?? proposedCategory;
    schema.validateSchema(requireCanonicalMetric: knownCategory == null);
    final observationCanonicalMetric =
        productData['canonical_metric'] as String?;
    schema.validateObservation(
      unit: primaryUnitName,
      metric: observationCanonicalMetric,
      attributes: attributes,
    );
    if (schema.canonicalMetric != null &&
        proposedCategory.canonicalMetric != schema.canonicalMetric) {
      throw const CategorySchemaMismatch(
        'Conflicting category canonical metric.',
      );
    }
    final localKeys = schema.requiredAttributes.map((a) => a.key).toSet();
    final proposedKeys = proposedCategory.requiredAttributes
        .map((a) => a.key)
        .toSet();
    final schemaDiverged =
        knownCategory != null &&
        (schema.displayName != proposedCategory.displayName ||
            schema.primaryUnit != proposedCategory.primaryUnit ||
            localKeys.length != proposedKeys.length ||
            !localKeys.containsAll(proposedKeys) ||
            schema.requiredAttributes.any(
              (local) => !proposedCategory.requiredAttributes.any(
                (proposed) =>
                    proposed.key == local.key && proposed.label == local.label,
              ),
            ));

    final currentUnitCost = totalPrice / totalUnitsCount;
    if (!currentUnitCost.isFinite || (totalPrice > 0 && currentUnitCost <= 0)) {
      throw const FormatException('Invalid unit cost.');
    }

    final product = ProductAnalysis(
      id: 'product_${DateTime.now().microsecondsSinceEpoch}',
      productName: schema.displayName,
      brand: brand,
      category: category,
      totalPrice: totalPrice,
      primaryUnitName: schema.primaryUnit,
      categoryKey: schema.key,
      canonicalMetric: schema.canonicalMetric,
      totalUnitsCount: totalUnitsCount,
      specificAttributes: attributes,
    );

    // Aggiorna sempre lo store (cheapest + media) ad ogni analisi valida,
    // indipendentemente da is_exact_match/needs_update: ogni prezzo
    // osservato contribuisce alla storia della categoria.
    CategoryReferenceModel? updatedCategory;
    if (categoryKey.isNotEmpty && currentUnitCost > 0) {
      await _categoryStore.upsertCategoryWithObservedUnitCost(
        proposedCategory,
        currentUnitCost,
        observationMetric: primaryUnitName,
        observationCanonicalMetric: observationCanonicalMetric,
        observedAttributes: attributes,
      );
      final refreshed = await _categoryStore.loadCustomCategories();
      updatedCategory = refreshed
          .where((item) => item.key == categoryKey)
          .cast<CategoryReferenceModel?>()
          .firstOrNull;
    }

    return <ProductAnalysis>[
      product.copyWith(
        productName: updatedCategory?.displayName ?? schema.displayName,
        primaryUnitName: updatedCategory?.primaryUnit ?? schema.primaryUnit,
        analysisSummary:
            _buildAnalysisSummary(
              updatedCategory?.primaryUnit ?? schema.primaryUnit,
              currentUnitCost,
              updatedCategory,
            ) +
            (schemaDiverged
                ? ' La proposta AI differisce: è stato mantenuto lo schema locale.'
                : '') +
            (schema.canonicalMetric == null
                ? ' Storico legacy: metrica canonica non verificata.'
                : ''),
      ),
    ];
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

  bool _looksLikeRealProductPrompt(String prompt) {
    if (prompt.isEmpty || prompt.length < 6) {
      return false;
    }

    final lowered = prompt.toLowerCase();
    final hasLetters = RegExp(r'[a-zà-ù]').hasMatch(lowered);
    final hasNumber = RegExp(r'\d').hasMatch(lowered);
    final hasMeaningfulWords = RegExp(
      r'\b(carta|igienica|detergente|lavastoviglie|pasta|latte|pane|acqua|cibo|biscotti|sapone|shampoo|pastiglie|rotoli|strappi|euro|€|prezzo|kg|litro|ml|gr|g)\b',
    ).hasMatch(lowered);

    return hasLetters && (hasNumber || hasMeaningfulWords);
  }

  double _calculateTotalUnits(Map<String, dynamic> payload) {
    final unitsPerPackage = _requiredNumber(
      payload['units_per_package'],
      'units_per_package',
    );
    final subUnits = payload['sub_units_per_package'];
    // Null/absent means direct quantity. A supplied factor must be valid.
    final quantity = subUnits == null
        ? unitsPerPackage
        : unitsPerPackage * _requiredNumber(subUnits, 'sub_units_per_package');
    if (!quantity.isFinite || quantity <= 0) {
      throw const FormatException('Invalid total quantity.');
    }
    return quantity;
  }

  Map<String, dynamic> _normalizeSpecificAttributes(
    Map<String, dynamic> source,
  ) {
    final normalized = <String, dynamic>{};
    for (final entry in source.entries) {
      normalized[entry.key.toString()] = entry.value;
    }
    return normalized;
  }

  /// Legge required_attributes nel formato {key,label} normalizzato dal parser.
  List<RequiredAttribute> _readRequiredAttributes(dynamic value) {
    if (value is! List) {
      throw const FormatException('Missing required_attributes list.');
    }
    for (final entry in value) {
      if (entry is! Map ||
          entry['key'] is! String ||
          entry['label'] is! String ||
          (entry['key'] as String).trim().isEmpty ||
          (entry['label'] as String).trim().isEmpty) {
        throw const FormatException('Invalid required attribute definition.');
      }
    }
    return value.map(RequiredAttribute.fromJson).toList(growable: false);
  }

  double _requiredNumber(
    dynamic value,
    String field, {
    bool allowZero = false,
  }) {
    final number = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value.replaceAll(',', '.'))
        : null;
    if (number == null ||
        !number.isFinite ||
        (allowZero ? number < 0 : number <= 0)) {
      throw FormatException('Missing or invalid $field.');
    }
    return number;
  }

  String _requiredText(dynamic value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing or invalid $field.');
    }
    return value.trim();
  }

  String _buildAnalysisSummary(
    String primaryUnitName,
    double currentUnitCost,
    CategoryReferenceModel? updatedCategory,
  ) {
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
        analysisSummary:
            'Prezzo corretto espresso per strappo, con totale di 6000 unità.',
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

    final matched = mockProducts
        .where((product) {
          final haystack =
              '${product.productName} ${product.brand} ${product.primaryUnitName}'
                  .toLowerCase();
          final promptContains = <String>[
            'carta',
            'igienica',
            'detersivo',
            'pane',
            'pastiglie',
            'lavastoviglie',
            'capsule',
            'milk',
            'latte',
            'olio',
            'spazzatura',
            'bag',
            'sacchetto',
          ];

          for (final keyword in promptContains) {
            if (normalizedPrompt.contains(keyword) &&
                haystack.contains(keyword)) {
              return true;
            }
          }

          if (normalizedPrompt.contains('lavastoviglie') &&
              haystack.contains('lavastoviglie')) {
            return true;
          }

          return false;
        })
        .toList(growable: false);

    if (matched.isNotEmpty) {
      return matched;
    }

    return <ProductAnalysis>[mockProducts.first];
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
