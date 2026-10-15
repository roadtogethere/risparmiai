import 'dart:convert';

import '../../domain/entities/category_reference.dart';
import '../../domain/entities/quantity_plan.dart';
import '../../domain/entities/required_attribute.dart';

/// Strict M4A protocol. Legacy product JSON is deliberately not accepted here.
class QuantityPlanParser {
  static Map<String, dynamic> decode(String text) {
    final decoded = jsonDecode(text);
    final map = _map(decoded);
    if (intent(map) == ConversationIntent.clarify) {
      clarificationQuestion(map);
    } else {
      parse(map);
    }
    return map;
  }

  static QuantityPlan parse(Map<String, dynamic> json) {
    intent(json);
    _keys(json, {
      'intent',
      'status',
      'category',
      'facts',
      'operation',
      'missing',
      'question',
    });
    final status = switch (json['status']) {
      'sufficient' => PlannerStatus.sufficient,
      'needs_information' => PlannerStatus.needsInformation,
      _ => throw const FormatException('Invalid planner status.'),
    };
    final category = _map(json['category']);
    _keys(category, {'key', 'proposal'});
    final key = _text(category['key']);
    CategoryReference? proposal;
    if (category['proposal'] != null) {
      final schema = _map(category['proposal']);
      _keys(schema, {
        'display_name',
        'canonical_metric',
        'primary_unit',
        'required_attributes',
      });
      final attributes = schema['required_attributes'];
      if (attributes is! List) {
        throw const FormatException('Missing required_attributes.');
      }
      proposal = CategoryReference(
        key: key,
        displayName: _text(schema['display_name']),
        primaryUnit: _text(schema['primary_unit']),
        canonicalMetric: _code(schema['canonical_metric']),
        averageUnitCost: 0,
        requiredAttributes: attributes
            .map((raw) {
              final attribute = _map(raw);
              _keys(attribute, {'key', 'label'});
              return RequiredAttribute(
                key: _text(attribute['key']),
                label: _text(attribute['label']),
              );
            })
            .toList(growable: false),
      );
      proposal.validateSchema(requireCanonicalMetric: true);
    }
    final facts = <String, QuantityFact>{};
    for (final entry in _map(json['facts']).entries) {
      _code(entry.key);
      final fact = _map(entry.value);
      _keys(fact, {'value', 'unit', 'per', 'source'});
      if (fact['value'] is! num) {
        throw const FormatException('Fact value must be numeric.');
      }
      final unit = _text(fact['unit']);
      if (unit != 'EUR') _code(unit);
      facts[entry.key] = QuantityFact(
        value: (fact['value'] as num).toDouble(),
        unit: unit,
        per: fact['per'] == null ? null : _code(fact['per']),
        source: switch (fact['source']) {
          'user_input' => FactSource.userInput,
          'user_confirmation' => FactSource.userConfirmation,
          'ai_suggestion' => FactSource.aiSuggestion,
          'external_lookup' => FactSource.externalLookup,
          _ => throw const FormatException('Fact source is required.'),
        },
      );
    }
    QuantityOperation? operation;
    if (!json.containsKey('operation')) {
      throw const FormatException('Missing operation.');
    }
    if (json['operation'] != null) {
      final op = _map(json['operation']);
      final type = _text(op['type']);
      if (type == 'multiply') {
        _keys(op, {'type', 'operands'});
        final operands = op['operands'];
        if (operands is! List || operands.length != 2) {
          throw const FormatException('Multiply needs two operands.');
        }
        operation = QuantityOperation(type, operands.map(_text).toList());
      } else {
        _keys(op, {'type', 'operand'});
        operation = QuantityOperation(type, [_text(op['operand'])]);
      }
    }
    final rawMissing = json['missing'] ?? <dynamic>[];
    if (rawMissing is! List) {
      throw const FormatException('Invalid missing list.');
    }
    return QuantityPlan(
      status: status,
      categoryKey: key,
      facts: facts,
      proposal: proposal,
      operation: operation,
      missing: rawMissing.map(_text).toSet().toList(),
      question: json['question'] == null ? null : _text(json['question']),
    );
  }

  // Omission preserves old stored plans and existing integrations; it never
  // authorizes a category change or an automatic new product.
  static ConversationIntent intent(Map<String, dynamic> json) =>
      switch (json['intent']) {
        null when !json.containsKey('intent') =>
          ConversationIntent.continueProduct,
        'continue' => ConversationIntent.continueProduct,
        'correct' => ConversationIntent.correct,
        'new_product' => ConversationIntent.newProduct,
        'clarify' => ConversationIntent.clarify,
        _ => throw const FormatException('Invalid conversation intent.'),
      };

  static String clarificationQuestion(Map<String, dynamic> json) {
    _keys(json, {'intent', 'question'});
    return _text(json['question']);
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object.');
    }
    return value;
  }

  static String _text(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Expected nonempty text.');
    }
    return value.trim();
  }

  static String _code(dynamic value) {
    final text = _text(value);
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(text)) {
      throw const FormatException('Invalid metric or fact key.');
    }
    return text;
  }

  static void _keys(Map<String, dynamic> json, Set<String> allowed) {
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unexpected planner field.');
    }
  }
}
