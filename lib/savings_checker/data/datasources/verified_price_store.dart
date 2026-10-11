import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/price_analysis.dart';
import '../../domain/entities/quantity_plan.dart';
import '../../domain/repositories/verified_price_history.dart';
import '../../domain/services/comparable_quantity_resolver.dart';
import '../models/quantity_plan_parser.dart';
import 'category_reference_store.dart';

/// Separate from M1-M3 aggregates. One serialized write stores an immutable
/// observation and its schema/facts together; no legacy data is migrated.
class VerifiedPriceStore implements VerifiedPriceHistory {
  const VerifiedPriceStore();
  static const storageKey = 'verified_price_observations_v1';
  static Future<void> _pending = Future<void>.value();

  @override
  Future<List<SavedPrice>> read() async {
    await _pending;
    return List.unmodifiable(await _read());
  }

  Future<List<SavedPrice>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    final root = jsonDecode(raw);
    if (root is! Map<String, dynamic> ||
        root['version'] != 1 ||
        root['observations'] is! List) {
      throw const FormatException('Invalid verified history.');
    }
    final records = <SavedPrice>[];
    final ids = <String>{};
    final metrics = <String, String>{};
    for (final rawRecord in root['observations'] as List) {
      if (rawRecord is! Map<String, dynamic>) {
        throw const FormatException('Invalid observation.');
      }
      final id = rawRecord['analysis_id'];
      final revision = rawRecord['revision'];
      final savedAt = rawRecord['saved_at'];
      if (id is! String ||
          id.isEmpty ||
          revision is! int ||
          revision < 1 ||
          savedAt is! String) {
        throw const FormatException('Invalid observation identity.');
      }
      final timestamp = DateTime.tryParse(savedAt);
      final payload = rawRecord['plan'];
      if (timestamp == null || payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid observation payload.');
      }
      final plan = QuantityPlanParser.parse(payload);
      final schema = plan.proposal;
      if (schema == null) throw const FormatException('Missing saved schema.');
      final result = const ComparableQuantityResolver().resolve(plan, schema);
      final analysis = PlannerAnalysis(
        id: id,
        revision: revision,
        plan: plan,
        schema: schema,
        result: result,
        userTurns: const [],
      );
      final price = ComparablePrice.fromAnalysis(analysis);
      if (!price.canSave ||
          rawRecord['quantity'] != price.quantity ||
          rawRecord['unit_cost'] != price.unitCost ||
          !ids.add(price.observationId)) {
        throw const FormatException('Unverified observation.');
      }
      final previousMetric = metrics[price.categoryKey];
      if (previousMetric != null && previousMetric != price.canonicalMetric) {
        throw const FormatException('Conflicting historical metric.');
      }
      metrics[price.categoryKey] = price.canonicalMetric;
      records.add(SavedPrice(price, timestamp));
    }
    return records;
  }

  @override
  Future<SavePriceResult> save(ComparablePrice requested) {
    final operation = _pending.then((_) async {
      // Never trust a caller's cached calculation at the persistence boundary.
      var price = ComparablePrice.fromAnalysis(requested.analysis);
      if (!price.canSave) {
        throw const FormatException('Zero price is not saveable.');
      }
      final records = await _read();
      // Resolve authority again under the write queue, including concurrent saves.
      final catalog = await const CategoryReferenceStore().loadCategories();
      final matching = catalog.where(
        (category) => category.key == price.categoryKey,
      );
      final historical = records.where(
        (record) => record.price.categoryKey == price.categoryKey,
      );
      final reference = matching.isNotEmpty
          ? matching.first
          : historical.isNotEmpty
          ? historical.first.price.analysis.schema
          : price.analysis.schema;
      if (reference.canonicalMetric != price.canonicalMetric) {
        throw const FormatException('Saved category schema is incompatible.');
      }
      final original = price.analysis;
      price = ComparablePrice.fromAnalysis(
        PlannerAnalysis(
          id: original.id,
          revision: original.revision,
          plan: original.plan,
          schema: reference,
          result: original.result,
          userTurns: original.userTurns,
        ),
      );
      for (final existing in records) {
        final old = existing.price;
        if (old.categoryKey == price.categoryKey &&
            old.canonicalMetric != price.canonicalMetric) {
          throw const FormatException('Category metric cannot change.');
        }
        if (old.observationId == price.observationId) {
          if (!old.samePriceAs(price)) {
            throw StateError('Saved revision is immutable.');
          }
          return SavePriceResult(existing, alreadySaved: true);
        }
        if (old.analysis.id == price.analysis.id && old.samePriceAs(price)) {
          return SavePriceResult(existing, alreadySaved: true);
        }
      }
      // One document write persists schema, facts and observation together.
      final saved = SavedPrice(price, DateTime.now().toUtc());
      final encoded = jsonEncode({
        'version': 1,
        'observations': [...records, saved].map(_encode).toList(),
      });
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, encoded)) {
        throw StateError('Unable to save price.');
      }
      return SavePriceResult(saved, alreadySaved: false);
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace trace) {},
    );
    return operation;
  }

  static Map<String, dynamic> _encode(SavedPrice observation) {
    final price = observation.price;
    final schema = price.analysis.schema;
    return {
      'analysis_id': price.analysis.id,
      'revision': price.analysis.revision,
      'saved_at': observation.savedAt.toIso8601String(),
      'quantity': price.quantity,
      'unit_cost': price.unitCost,
      'plan': {
        'status': 'sufficient',
        'category': {
          'key': schema.key,
          'proposal': {
            'display_name': schema.displayName,
            'canonical_metric': schema.canonicalMetric,
            'primary_unit': schema.primaryUnit,
            'required_attributes': schema.requiredAttributes
                .map((a) => a.toJson())
                .toList(),
          },
        },
        'facts': price.analysis.plan.facts.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'operation': price.analysis.plan.operation!.toJson(),
      },
    };
  }
}
