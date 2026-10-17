import 'quantity_plan.dart';
import '../services/comparable_quantity_resolver.dart';

/// An unrounded, Dart-validated economic observation, not a purchase.
class ComparablePrice {
  ComparablePrice._(
    this.analysis,
    this.totalPrice,
    this.quantity,
    this.unitCost,
  );

  factory ComparablePrice.fromAnalysis(PlannerAnalysis analysis) {
    final resolved = const ComparableQuantityResolver().resolve(
      analysis.plan,
      analysis.schema,
    );
    final totalPrice = analysis.plan.facts['price']?.value;
    if (resolved.status != QuantityResolutionStatus.calculable ||
        totalPrice == null ||
        analysis.result.quantity != resolved.quantity ||
        analysis.result.canonicalMetric != resolved.canonicalMetric) {
      throw const FormatException(
        'Analysis is not a validated comparable quantity.',
      );
    }
    if (analysis.id.isEmpty || analysis.revision < 1) {
      throw const FormatException('Invalid local analysis identity.');
    }
    return ComparablePrice._(
      analysis,
      totalPrice,
      resolved.quantity!,
      totalPrice / resolved.quantity!,
    );
  }

  final PlannerAnalysis analysis;
  final double totalPrice;
  final double quantity;
  final double unitCost;
  String get categoryKey => analysis.schema.key;
  String get canonicalMetric => analysis.schema.canonicalMetric!;
  String get displayUnit => analysis.schema.primaryUnit;
  String get observationId => '${analysis.id}:${analysis.revision}';
  bool get canSave => totalPrice > 0;

  bool samePriceAs(ComparablePrice other) =>
      categoryKey == other.categoryKey &&
      canonicalMetric == other.canonicalMetric &&
      totalPrice == other.totalPrice &&
      quantity == other.quantity;
}

enum PricePosition {
  noHistory,
  potentialMinimum,
  tiedMinimum,
  belowAverage,
  tiedAverage,
  aboveAverage,
}

class PriceComparison {
  const PriceComparison({
    required this.price,
    required this.count,
    required this.position,
    this.previousMinimum,
    this.previousAverage,
    this.differenceFromMinimum,
    this.differenceFromAverage,
    this.percentFromMinimum,
    this.percentFromAverage,
  });
  final ComparablePrice price;
  final int count;
  final PricePosition position;
  final double? previousMinimum;
  final double? previousAverage;
  // Signed current - previous; negative means a lower current cost.
  final double? differenceFromMinimum;
  final double? differenceFromAverage;
  final double? percentFromMinimum;
  final double? percentFromAverage;
  bool get isPotentialNewMinimum => position == PricePosition.potentialMinimum;
}

class SavedPrice {
  const SavedPrice(this.price, this.savedAt);
  final ComparablePrice price;
  final DateTime savedAt;
}

class PriceHistorySummary {
  const PriceHistorySummary({required this.count, this.minimum, this.average});
  final int count;
  final double? minimum;
  final double? average;
}

class SavePriceResult {
  const SavePriceResult(this.observation, {required this.alreadySaved});
  final SavedPrice observation;
  final bool alreadySaved;
}
