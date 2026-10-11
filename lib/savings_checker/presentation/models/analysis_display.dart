import '../../domain/entities/quantity_plan.dart';
import '../notifiers/savings_chat_notifier.dart';

/// Presentation only: never used as input to validation, comparisons or storage.
class AnalysisDisplay {
  static String label(String value) {
    final text = value
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .trim();
    return text.isEmpty
        ? 'Caratteristica'
        : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  static String factLabel(PlannerAnalysis analysis, String key) {
    if (key == 'price') return 'Prezzo totale';
    for (final attribute in analysis.schema.requiredAttributes) {
      if (attribute.key == key) return label(attribute.label);
    }
    return label(key);
  }

  // Unit labels, not product/category recognition or conversion rules.
  static const _units = {
    'EUR': '€',
    'liter': 'L',
    'milliliter': 'ml',
    'kilogram': 'kg',
    'gram': 'g',
    'roll': 'rotoli',
    'sheet': 'strappi',
    'ply': 'veli',
    'tablet': 'pastiglie',
    'capsule': 'capsule',
    'bag': 'sacchetti',
    'label': 'etichette',
    'slice': 'fette',
    'wash': 'lavaggi',
  };
  static String unit(String code) => _units[code] ?? label(code).toLowerCase();

  static String amount(double value) {
    final raw = value != 0 && value.abs() < 0.000001
        ? value.toStringAsPrecision(4)
        : SavingsChatNotifier.formatUnitCost(value);
    if (raw.contains('e')) return raw.replaceAll('.', ',');
    final parts = raw.split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return parts.length == 1 ? integer : '$integer,${parts[1]}';
  }

  static String factValue(QuantityFact fact) =>
      '${amount(fact.value)} ${unit(fact.unit)}${fact.per == null ? '' : ' per ${unit(fact.per!)}'}';

  static String? scaledCost(double cost, String metric) {
    // Only known discrete count units; never scale physical or unknown metrics.
    const counts = {
      'sheet',
      'tablet',
      'capsule',
      'bag',
      'label',
      'slice',
      'wash',
    };
    if (cost <= 0 || cost >= 0.01 || !counts.contains(metric)) return null;
    final scaled = cost * 1000;
    final formatted = scaled >= 0.01
        ? scaled.toStringAsFixed(2).replaceAll('.', ',')
        : amount(scaled);
    return 'Circa $formatted € ogni 1.000 ${unit(metric)}';
  }
}
