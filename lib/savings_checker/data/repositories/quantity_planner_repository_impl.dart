import 'dart:convert';
import 'dart:math';

import '../../domain/entities/category_reference.dart';
import '../../domain/entities/quantity_plan.dart';
import '../../domain/repositories/quantity_planner_repository.dart';
import '../../domain/services/comparable_quantity_resolver.dart';
import '../datasources/ai_savings_client.dart';
import '../datasources/category_reference_store.dart';
import '../models/quantity_plan_parser.dart';
import '../datasources/verified_price_store.dart';

/// Analysis only reads storage. Economic observations require an explicit save.
class QuantityPlannerRepositoryImpl implements QuantityPlannerRepository {
  QuantityPlannerRepositoryImpl({
    required this.aiClient,
    CategoryReferenceStore? categoryStore,
  }) : _store = categoryStore ?? const CategoryReferenceStore();
  final AiSavingsClient? aiClient;
  final CategoryReferenceStore _store;
  final Map<String, CategoryReference> _sessionSchemas = {};
  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Future<PlannerAnalysis> analyzeTurn(
    String input, {
    PlannerAnalysis? previous,
  }) async {
    if (input.trim().isEmpty) throw const FormatException('Empty user input.');
    final client = aiClient;
    if (client == null) throw StateError('AI provider is not configured.');
    final categories = <String, CategoryReference>{
      ..._sessionSchemas,
      for (final category in await _store.loadCategories())
        category.key: category,
    };
    // Reuse schemas attached to explicitly saved verified observations after restart.
    for (final saved in await const VerifiedPriceStore().read()) {
      categories.putIfAbsent(
        saved.price.categoryKey,
        () => saved.price.analysis.schema,
      );
    }
    final turns = [...?previous?.userTurns, input.trim()];
    final request = jsonEncode({
      'user_turns': turns,
      if (previous != null)
        'current_analysis': {
          'category_key': previous.schema.key,
          'facts': previous.plan.facts.map(
            (key, fact) => MapEntry(key, fact.toJson()),
          ),
          'operation': previous.plan.operation?.toJson(),
          'missing': previous.result.missing,
          'question': previous.message,
        },
    });
    final catalog = jsonEncode({
      'categories': categories.values
          .map(
            (category) => {
              'key': category.key,
              'display_name': category.displayName,
              'primary_unit': category.primaryUnit,
              'canonical_metric': category.canonicalMetric,
              'required_attributes': category.requiredAttributes
                  .map((a) => a.toJson())
                  .toList(),
            },
          )
          .toList(),
    });
    final parsed = QuantityPlanParser.parse(
      await client.analyzeProductWithCatalog(request, catalog),
    );
    if (previous != null && parsed.categoryKey != previous.schema.key) {
      throw const CategorySchemaMismatch(
        'A continuation cannot silently change category.',
      );
    }
    if (previous == null &&
        parsed.facts.values.any(
          (f) => f.source == FactSource.userConfirmation,
        )) {
      throw const FormatException(
        'Confirmation requires an existing analysis.',
      );
    }
    final schema = categories[parsed.categoryKey] ?? parsed.proposal;
    if (schema == null) {
      throw const CategorySchemaMismatch(
        'Unknown category requires a schema proposal.',
      );
    }
    schema.validateSchema(
      requireCanonicalMetric: !categories.containsKey(parsed.categoryKey),
    );
    final plan = QuantityPlan(
      status: parsed.status,
      categoryKey: parsed.categoryKey,
      facts: {...?previous?.plan.facts, ...parsed.facts},
      proposal: parsed.proposal,
      operation: parsed.operation,
      missing: parsed.missing,
      question: parsed.question,
    );
    final result = const ComparableQuantityResolver().resolve(plan, schema);
    if (result.status != QuantityResolutionStatus.rejected) {
      _sessionSchemas[schema.key] = schema;
    }
    return PlannerAnalysis(
      id: previous?.id ?? _newId(),
      revision: (previous?.revision ?? 0) + 1,
      plan: plan,
      schema: schema,
      result: result,
      userTurns: turns,
    );
  }
}
