import 'package:spesai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:spesai/savings_checker/data/models/product_analysis_model.dart';
import 'package:spesai/savings_checker/domain/entities/product_analysis.dart';
import 'package:spesai/savings_checker/domain/entities/product_category.dart';
import 'package:spesai/savings_checker/domain/repositories/savings_repository.dart';
import 'package:spesai/savings_checker/domain/services/savings_calculator_service.dart';

class SavingsRepositoryImpl implements SavingsRepository {
  SavingsRepositoryImpl({
    OpenAiSavingsClient? openAiClient,
    SavingsCalculatorService? calculator,
    this.useMockData = false,
  })  : _openAiClient = openAiClient,
        _calculator = calculator ?? const SavingsCalculatorService();

  final OpenAiSavingsClient? _openAiClient;
  final SavingsCalculatorService _calculator;
  final bool useMockData;

  @override
  Future<List<ProductAnalysis>> analyzeProducts({
    required String userPrompt,
  }) async {
    if (useMockData || _openAiClient == null) {
      return _buildMockProductsForPrompt(userPrompt);
    }

    try {
      final payload = await _openAiClient.analyzeShoppingPrompt(userPrompt);
      final models = payload
          .map((json) => ProductAnalysisModel.fromJson(json))
          .toList(growable: false);

      return models;
    } on Exception {
      // Fallback pratico per permettere il POC in ambiente offline o senza chiave API.
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

  List<ProductAnalysis> _buildMockProductsForPrompt(String userPrompt) {
    final normalizedPrompt = userPrompt.toLowerCase();

    final productA = ProductAnalysis(
      id: 'carta_igienica_1',
      productName: 'Carta igienica',
      brand: 'Migliore',
      category: ProductCategory.household,
      totalPrice: 3.49,
      primaryUnitName: 'rotolo',
      totalUnitsCount: 12,
      specificAttributes: <String, dynamic>{
        'sheetsPerRoll': 200,
        'material': 'cellulosa',
      },
      analysisSummary: 'Prezzo contenuto per rotolo, buona resa per famiglia.',
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

    if (normalizedPrompt.contains('carta')) {
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
