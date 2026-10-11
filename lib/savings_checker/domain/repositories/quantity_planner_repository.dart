import '../entities/quantity_plan.dart';

abstract class QuantityPlannerRepository {
  Future<PlannerAnalysis> analyzeTurn(
    String input, {
    PlannerAnalysis? previous,
  });
}
