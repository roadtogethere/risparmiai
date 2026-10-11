import '../entities/price_analysis.dart';

abstract class VerifiedPriceHistory {
  Future<List<SavedPrice>> read();
  Future<SavePriceResult> save(ComparablePrice price);
}
