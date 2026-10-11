import '../entities/product_analysis.dart';
import '../entities/savings_comparison.dart';

class SavingsCalculatorService {
  const SavingsCalculatorService();

  SavingsComparison compareAgainstAverage({
    required ProductAnalysis product,
    required List<ProductAnalysis> products,
  }) {
    if (products.isEmpty) {
      return SavingsComparison(
        product: product,
        averageUnitCost: product.unitCost,
        savingsPercentage: 0,
        savedAmount: 0,
        isBetterValue: true,
        message:
            'Nessun confronto disponibile: il prodotto è il riferimento attuale.',
      );
    }

    final averageUnitCost =
        (products
                    .map((item) => item.unitCost)
                    .reduce((sum, value) => sum + value) /
                products.length)
            .toDouble();

    final savingsPercentage = averageUnitCost > 0
        ? ((averageUnitCost - product.unitCost) / averageUnitCost) * 100
        : 0.0;

    final savedAmount =
        (averageUnitCost - product.unitCost) *
        product.totalUnitsCount.toDouble();

    return SavingsComparison(
      product: product,
      averageUnitCost: averageUnitCost,
      savingsPercentage: savingsPercentage,
      savedAmount: savedAmount,
      isBetterValue: product.unitCost <= averageUnitCost,
      message: product.unitCost <= averageUnitCost
          ? 'Il prodotto è sotto la media di convenienza.'
          : 'Il prodotto è sopra la media di convenienza.',
    );
  }

  double calculateSavingsPercentage({
    required double referencePrice,
    required double comparisonPrice,
  }) {
    if (referencePrice <= 0) {
      return 0;
    }

    final diff = referencePrice - comparisonPrice;
    return (diff / referencePrice) * 100;
  }

  ProductAnalysis bestValueProduct({required List<ProductAnalysis> products}) {
    if (products.isEmpty) {
      throw StateError(
        'Non è possibile trovare il prodotto migliore senza dati.',
      );
    }

    return products.reduce((currentBest, candidate) {
      return candidate.unitCost < currentBest.unitCost
          ? candidate
          : currentBest;
    });
  }
}
