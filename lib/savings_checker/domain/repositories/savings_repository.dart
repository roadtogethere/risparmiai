import '../entities/product_analysis.dart';

abstract class SavingsRepository {
  Future<List<ProductAnalysis>> analyzeProducts({
    required String userPrompt,
  });

  Future<ProductAnalysis> identifyBestValue({
    required ProductAnalysis currentProduct,
    required List<ProductAnalysis> alternatives,
  });
}
