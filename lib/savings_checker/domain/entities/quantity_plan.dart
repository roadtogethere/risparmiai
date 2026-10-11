import 'category_reference.dart';

enum PlannerStatus { sufficient, needsInformation }

enum FactSource { userInput, userConfirmation, aiSuggestion, externalLookup }

class QuantityFact {
  const QuantityFact({
    required this.value,
    required this.unit,
    required this.source,
    this.per,
  });
  final double value;
  final String unit;
  final String? per;
  final FactSource source;
  bool get isConfirmed =>
      source == FactSource.userInput || source == FactSource.userConfirmation;

  Map<String, dynamic> toJson() => {
    'value': value,
    'unit': unit,
    if (per != null) 'per': per,
    'source': switch (source) {
      FactSource.userInput => 'user_input',
      FactSource.userConfirmation => 'user_confirmation',
      FactSource.aiSuggestion => 'ai_suggestion',
      FactSource.externalLookup => 'external_lookup',
    },
  };
}

class QuantityOperation {
  QuantityOperation(this.type, List<String> operands)
    : operands = List.unmodifiable(operands);
  final String type;
  final List<String> operands;
  Map<String, dynamic> toJson() => {
    'type': type,
    if (type == 'multiply')
      'operands': operands
    else
      'operand': operands.single,
  };
}

/// A proposal, never an authoritative calculated result.
class QuantityPlan {
  QuantityPlan({
    required this.status,
    required this.categoryKey,
    required Map<String, QuantityFact> facts,
    required this.operation,
    this.proposal,
    List<String> missing = const [],
    this.question,
  }) : facts = Map.unmodifiable(facts),
       missing = List.unmodifiable(missing);
  final PlannerStatus status;
  final String categoryKey;
  final CategoryReference? proposal;
  final Map<String, QuantityFact> facts;
  final QuantityOperation? operation;
  final List<String> missing;
  final String? question;
}

enum QuantityResolutionStatus { calculable, needsInformation, rejected }

class ComparableQuantityResult {
  const ComparableQuantityResult.calculable(double value, String metric)
    : status = QuantityResolutionStatus.calculable,
      quantity = value,
      canonicalMetric = metric,
      reason = null,
      missing = const [];
  ComparableQuantityResult.needsInformation(List<String> keys)
    : status = QuantityResolutionStatus.needsInformation,
      quantity = null,
      canonicalMetric = null,
      reason = 'missing_or_unconfirmed_facts',
      missing = List.unmodifiable(keys);
  const ComparableQuantityResult.rejected(this.reason)
    : status = QuantityResolutionStatus.rejected,
      quantity = null,
      canonicalMetric = null,
      missing = const [];
  final QuantityResolutionStatus status;
  final double? quantity;
  final String? canonicalMetric;
  final String? reason;
  final List<String> missing;
}

/// Local conversational identity. M4A never writes economic aggregates.
class PlannerAnalysis {
  PlannerAnalysis({
    required this.id,
    required this.plan,
    required this.schema,
    required this.result,
    required List<String> userTurns,
  }) : userTurns = List.unmodifiable(userTurns);
  final String id;
  final QuantityPlan plan;
  final CategoryReference schema;
  final ComparableQuantityResult result;
  final List<String> userTurns;
  bool get needsInformation =>
      result.status == QuantityResolutionStatus.needsInformation;
  String get message {
    if (result.status == QuantityResolutionStatus.calculable) {
      return 'Quantità comparabile: ${result.quantity} ${schema.primaryUnit}.';
    }
    if (needsInformation) {
      // Only use the planner question when it refers to the actual missing facts.
      if (plan.question != null &&
          result.missing.length == plan.missing.length &&
          result.missing.every(plan.missing.contains)) {
        return plan.question!;
      }
      String label(String key) {
        if (key == 'price') return 'prezzo';
        if (key == 'operation' || key == 'clarification') {
          return 'quantità del prodotto e unità di misura';
        }
        for (final attribute in schema.requiredAttributes) {
          if (attribute.key == key) return attribute.label;
        }
        return key.replaceAll('_', ' ');
      }

      return 'Per completare il calcolo servono dati confermati: ${result.missing.map(label).join(', ')}.';
    }
    final explanation = switch (result.reason) {
      'unverified_legacy_metric' =>
        'La metrica dello storico non è verificata.',
      'category_schema_conflict' =>
        'La proposta non rispetta la metrica della categoria salvata.',
      'incompatible_metric' || 'incompatible_dimensions' =>
        'Le unità indicate non consentono questo calcolo.',
      'unsupported_conversion' => 'La conversione richiesta non è disponibile.',
      'unsupported_operation' => 'Il calcolo richiesto non è supportato.',
      _ => 'I dati indicati non consentono un calcolo valido.',
    };
    return 'Quantità comparabile non calcolabile. $explanation';
  }
}
