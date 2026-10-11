import '../entities/price_analysis.dart';

class PriceComparisonService {
  const PriceComparisonService();

  PriceComparison compare(ComparablePrice price, List<SavedPrice> history) {
    final entries = history
        .where(
          (entry) =>
              entry.price.categoryKey == price.categoryKey &&
              entry.price.canonicalMetric == price.canonicalMetric &&
              entry.price.observationId != price.observationId &&
              !(entry.price.analysis.id == price.analysis.id &&
                  entry.price.samePriceAs(price)),
        )
        .toList();
    if (entries.isEmpty) {
      return PriceComparison(
        price: price,
        count: 0,
        position: PricePosition.noHistory,
      );
    }
    var minimum = entries.first.price.unitCost;
    // Equal weight per observation, without an overflowing sum or premature
    // division that would erase very small positive costs.
    var average = entries.first.price.unitCost;
    for (var index = 0; index < entries.length; index++) {
      final cost = entries[index].price.unitCost;
      if (cost < minimum) minimum = cost;
      if (index > 0) average += (cost - average) / (index + 1);
    }
    if (!average.isFinite || average <= 0) {
      throw const FormatException('Invalid historical average.');
    }
    final current = price.unitCost;
    final position = current < minimum
        ? PricePosition.potentialMinimum
        : current == minimum
        ? PricePosition.tiedMinimum
        : current < average
        ? PricePosition.belowAverage
        : current == average
        ? PricePosition.tiedAverage
        : PricePosition.aboveAverage;
    double? percent(double reference) {
      final value = ((current - reference) / reference) * 100;
      return value.isFinite ? value : null;
    }

    return PriceComparison(
      price: price,
      count: entries.length,
      position: position,
      previousMinimum: minimum,
      previousAverage: average,
      differenceFromMinimum: current - minimum,
      differenceFromAverage: current - average,
      percentFromMinimum: percent(minimum),
      percentFromAverage: percent(average),
    );
  }
}
