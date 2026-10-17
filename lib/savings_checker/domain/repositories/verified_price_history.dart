import '../entities/price_analysis.dart';

abstract class VerifiedPriceHistory {
  Future<List<SavedPrice>> read();
  Future<SavePriceResult> save(ComparablePrice price);
  Future<SavedPrice?> delete(String observationId);
  Future<void> restore(SavedPrice observation);
}
