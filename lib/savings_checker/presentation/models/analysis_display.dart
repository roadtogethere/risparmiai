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
      if (attribute.key == key && label(attribute.label) != label(key)) {
        return label(attribute.label);
      }
    }
    final fact = analysis.plan.facts[key];
    if (fact != null && _singular.containsKey(fact.unit)) {
      if (fact.per != null) {
        return '${label(unit(fact.unit))} per ${singular(fact.per!)}';
      }
      if (key.endsWith('_count')) return 'Numero di ${unit(fact.unit)}';
    }
    return label(key);
  }

  // Grammatical unit forms only, independent of category and product.
  static const _singular = {
    'roll': 'rotolo',
    'sheet': 'strappo',
    'ply': 'velo',
    'tablet': 'pastiglia',
    'capsule': 'capsula',
    'bag': 'sacchetto',
    'label': 'etichetta',
    'slice': 'fetta',
    'wash': 'lavaggio',
  };
  static String singular(String code) => _singular[code] ?? unit(code);
  static String countedUnit(String code, double value, {String? fallback}) =>
      _singular.containsKey(code)
      ? (value == 1 ? singular(code) : unit(code))
      : (_units[code] ?? fallback ?? label(code).toLowerCase());

  // Format only the deterministic, revision-attributed quantity summary.
  // Never rewrite user messages or free-form provider questions/errors.
  static String quantitySummary(String text) {
    final match = RegExp(
      r'^Quantità comparabile: ([0-9.eE+\-]+) (.+)\.$',
    ).firstMatch(text);
    if (match == null) return text;
    final value = double.tryParse(match[1]!);
    if (value == null || !value.isFinite) return text;
    final display = match[2]!;
    final code = _singular.entries
        .where((e) => e.value == display || unit(e.key) == display)
        .map((e) => e.key)
        .firstOrNull;
    return 'Quantità comparabile: ${amount(value)} ${code == null ? display : countedUnit(code, value)}.';
  }

  // Unit labels, not product/category recognition or conversion rules.
  static const _units = {
    'EUR': '€',
    'liter': 'L',
    'milliliter': 'ml',
    'centiliter': 'cl',
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
      '${amount(fact.value)} ${countedUnit(fact.unit, fact.value)}${fact.per == null ? '' : ' per ${singular(fact.per!)}'}';

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
