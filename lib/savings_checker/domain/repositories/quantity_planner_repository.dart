import '../entities/quantity_plan.dart';

abstract class QuantityPlannerRepository {
  Future<PlannerAnalysis> analyzeTurn(
    String input, {
    PlannerAnalysis? previous,
    List<Map<String, String>> clarificationTurns = const [],
  });
}
