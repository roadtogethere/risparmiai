import 'product_analysis.dart';

class SavingsComparison {
  const SavingsComparison({
    required this.product,
    required this.averageUnitCost,
    required this.savingsPercentage,
    required this.savedAmount,
    required this.isBetterValue,
    required this.message,
  });

  final ProductAnalysis product;
  final double averageUnitCost;
  final double savingsPercentage;
  final double savedAmount;
  final bool isBetterValue;
  final String message;
}
