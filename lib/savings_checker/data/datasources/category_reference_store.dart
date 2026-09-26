import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'category_reference_data_source.dart';
import '../models/category_reference_model.dart';

/// Gestisce la persistenza locale delle categorie "custom" (create o
/// aggiornate a runtime, es. dall'AI o da nuovi prodotti analizzati),
/// tenendo `default_categories.json` sempre come dataset read-only.
///
/// Il catalogo effettivo usato dall'app è sempre l'unione di:
/// - default_categories.json (statico, mai modificato)
/// - user_custom_categories (dinamico, salvato in SharedPreferences)
class CategoryReferenceStore {
  const CategoryReferenceStore({CategoryReferenceDataSource? defaultDataSource})
    : _defaultDataSource =
          defaultDataSource ?? const CategoryReferenceDataSource();

  static const String _prefsKey = 'user_custom_categories';

  final CategoryReferenceDataSource _defaultDataSource;

  // Shared by all instances in the app isolate, including ArchivePage.
  static Future<void> _pendingWrite = Future<void>.value();

  static Future<void> _serializeWrite(Future<void> Function() action) {
    final operation = _pendingWrite.then((_) => action());
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  /// Ritorna il catalogo unito: categorie custom sovrascrivono quelle di
  /// default con la stessa key (perché contengono dati più aggiornati).
  Future<List<CategoryReferenceModel>> loadCategories() async {
    final defaults = await _defaultDataSource.loadDefaultCategories();
    final custom = await loadCustomCategories();

    final merged = <String, CategoryReferenceModel>{
      for (final category in defaults) category.key: category,
    };

    for (final category in custom) {
      merged[category.key] = category;
    }

    return merged.values.toList(growable: false);
  }

  /// Ritorna solo le categorie custom salvate dall'utente/dall'AI,
  /// senza quelle di default — utile per la schermata Archivio.
  Future<List<CategoryReferenceModel>> loadCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    // Failed platform writes can leave uncommitted values in the plugin cache.
    await prefs.reload();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const <CategoryReferenceModel>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Category archive must be a list.');
    }
    final categories = <CategoryReferenceModel>[];
    final keys = <String>{};
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid category archive entry.');
      }
      for (final field in ['key', 'display_name', 'primary_unit']) {
        if (entry[field] is! String ||
            (entry[field] as String).trim().isEmpty) {
          throw FormatException('Invalid category archive field: $field.');
        }
      }
      // Legacy entries may omit sum/count. No migration is performed.
      for (final field in [
        'average_unit_cost',
        'sum_of_unit_costs',
        'entries_count',
      ]) {
        if (field != 'average_unit_cost' && !entry.containsKey(field)) continue;
        final value = num.tryParse(entry[field].toString());
        if (value == null ||
            !value.isFinite ||
            value < 0 ||
            (field == 'entries_count' &&
                (value != value.truncateToDouble() ||
                    (entry[field] is String &&
                        int.tryParse(entry[field]) == null)))) {
          throw FormatException('Invalid category archive field: $field.');
        }
      }
      final attributes = entry['required_attributes'];
      if (attributes is! List ||
          attributes.any(
            (attribute) =>
                attribute is! String &&
                (attribute is! Map ||
                    attribute['key'] is! String ||
                    attribute['label'] is! String),
          )) {
        throw const FormatException('Invalid category attributes.');
      }
      final category = CategoryReferenceModel.fromJson(entry);
      if (!keys.add(category.key)) {
        throw const FormatException('Duplicate category archive key.');
      }
      categories.add(category);
    }
    return categories;
  }

  /// Inserisce o aggiorna una categoria custom. Se esiste già una voce con
  /// la stessa key, applica [withNewObservedUnitCost] per aggiornare il
  /// prezzo più economico e la media storica, altrimenti la crea da zero.
  Future<void> upsertCategoryWithObservedUnitCost(
    CategoryReferenceModel incoming,
    double observedUnitCost,
  ) => _serializeWrite(() async {
    if (!observedUnitCost.isFinite ||
        observedUnitCost <= 0 ||
        incoming.key.trim().isEmpty ||
        incoming.displayName.trim().isEmpty ||
        incoming.primaryUnit.trim().isEmpty) {
      throw const FormatException('Invalid category observation.');
    }
    final custom = (await loadCustomCategories()).toList();
    final existingIndex = custom.indexWhere(
      (category) => category.key == incoming.key,
    );

    if (existingIndex >= 0) {
      custom[existingIndex] = custom[existingIndex].withNewObservedUnitCost(
        observedUnitCost,
      );
    } else {
      // Prima volta per questa key: si parte dai dati proposti (es. dall'AI)
      // e si registra subito il primo prezzo osservato.
      custom.add(incoming.withNewObservedUnitCost(observedUnitCost));
    }

    await _saveCustomCategories(custom);
  });

  /// Rimuove una categoria custom (non tocca mai i default).
  Future<void> removeCategory(String key) => _serializeWrite(() async {
    final custom = (await loadCustomCategories())
        .where((category) => category.key != key)
        .toList(growable: false);
    await _saveCustomCategories(custom);
  });

  Future<void> _saveCustomCategories(
    List<CategoryReferenceModel> categories,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      categories.map((category) => category.toJson()).toList(growable: false),
    );
    if (!await prefs.setString(_prefsKey, encoded)) {
      throw StateError('Unable to save category archive.');
    }
  }
}
