import '../entities/category_reference.dart';
import '../entities/quantity_plan.dart';

class ComparableQuantityResolver {
  const ComparableQuantityResolver();

  // Physical scale conversions only. No category-specific semantic aliases.
  static const _units = {
    'liter': ('volume', 1.0),
    'milliliter': ('volume', 0.001),
    'kilogram': ('mass', 1.0),
    'gram': ('mass', 0.001),
  };

  ComparableQuantityResult resolve(
    QuantityPlan plan,
    CategoryReference schema,
  ) {
    schema.validateSchema();
    if (schema.key != plan.categoryKey) {
      return const ComparableQuantityResult.rejected('category_mismatch');
    }
    final metric = schema.canonicalMetric;
    if (metric == null) {
      return const ComparableQuantityResult.rejected(
        'unverified_legacy_metric',
      );
    }
    final proposal = plan.proposal;
    if (proposal != null && proposal.canonicalMetric != metric) {
      return const ComparableQuantityResult.rejected(
        'category_schema_conflict',
      );
    }
    for (final entry in plan.facts.entries) {
      final value = entry.value.value;
      if (!value.isFinite || (entry.key == 'price' ? value < 0 : value <= 0)) {
        return const ComparableQuantityResult.rejected('invalid_fact_value');
      }
    }
    final price = plan.facts['price'];
    if (price != null && (price.unit != 'EUR' || price.per != null)) {
      return const ComparableQuantityResult.rejected('invalid_price_unit');
    }
    final op = plan.operation;
    if (op != null && !{'direct', 'convert', 'multiply'}.contains(op.type)) {
      return const ComparableQuantityResult.rejected('unsupported_operation');
    }
    if (op != null &&
        (op.operands.length != (op.type == 'multiply' ? 2 : 1) ||
            op.operands.toSet().length != op.operands.length ||
            op.operands.contains('price'))) {
      return const ComparableQuantityResult.rejected('invalid_operands');
    }
    final needed = {
      'price',
      if (op != null) ...op.operands,
      if (plan.status == PlannerStatus.needsInformation) ...plan.missing,
    };
    final missing = needed
        .where((key) => plan.facts[key]?.isConfirmed != true)
        .toList();
    if (missing.isNotEmpty) {
      return ComparableQuantityResult.needsInformation(missing);
    }
    if (op == null) {
      return ComparableQuantityResult.needsInformation(['operation']);
    }
    if (plan.status == PlannerStatus.needsInformation) {
      return ComparableQuantityResult.needsInformation(
        plan.missing.isEmpty ? ['clarification'] : plan.missing,
      );
    }
    final a = plan.facts[op.operands.first]!;
    double quantity;
    switch (op.type) {
      case 'direct':
        if (a.per != null || a.unit != metric) {
          return const ComparableQuantityResult.rejected('incompatible_metric');
        }
        quantity = a.value;
      case 'convert':
        final from = _units[a.unit];
        final to = _units[metric];
        if (a.per != null || from == null || to == null || from.$1 != to.$1) {
          return const ComparableQuantityResult.rejected(
            'unsupported_conversion',
          );
        }
        quantity = a.value * (from.$2 / to.$2);
      case 'multiply':
        final b = plan.facts[op.operands.last]!;
        final compatible =
            (a.per == null && b.per == a.unit && b.unit == metric) ||
            (b.per == null && a.per == b.unit && a.unit == metric);
        if (!compatible || a.unit == 'EUR' || b.unit == 'EUR') {
          return const ComparableQuantityResult.rejected(
            'incompatible_dimensions',
          );
        }
        quantity = a.value * b.value;
      default:
        return const ComparableQuantityResult.rejected('unsupported_operation');
    }
    if (!quantity.isFinite || quantity <= 0) {
      return const ComparableQuantityResult.rejected('invalid_quantity');
    }
    // Preserve M1.5 numerical guards without exposing a definitive M4B cost.
    final cost = price!.value / quantity;
    if (!cost.isFinite || (price.value > 0 && cost <= 0)) {
      return const ComparableQuantityResult.rejected('invalid_unit_cost');
    }
    return ComparableQuantityResult.calculable(quantity, metric);
  }
}
