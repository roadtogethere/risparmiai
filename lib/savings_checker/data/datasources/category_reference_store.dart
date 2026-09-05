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
  const CategoryReferenceStore({
    CategoryReferenceDataSource? defaultDataSource,
  }) : _defaultDataSource = defaultDataSource ?? const CategoryReferenceDataSource();

  static const String _prefsKey = 'user_custom_categories';

  final CategoryReferenceDataSource _defaultDataSource;

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
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      return const <CategoryReferenceModel>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <CategoryReferenceModel>[];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CategoryReferenceModel.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <CategoryReferenceModel>[];
    }
  }

  /// Inserisce o aggiorna una categoria custom. Se esiste già una voce con
  /// la stessa key, applica [withNewObservedUnitCost] per aggiornare il
  /// prezzo più economico e la media storica, altrimenti la crea da zero.
  Future<void> upsertCategoryWithObservedUnitCost(
    CategoryReferenceModel incoming,
    double observedUnitCost,
  ) async {
    final custom = (await loadCustomCategories()).toList();
    final existingIndex = custom.indexWhere((category) => category.key == incoming.key);

    if (existingIndex >= 0) {
      custom[existingIndex] = custom[existingIndex].withNewObservedUnitCost(observedUnitCost);
    } else {
      // Prima volta per questa key: si parte dai dati proposti (es. dall'AI)
      // e si registra subito il primo prezzo osservato.
      custom.add(incoming.withNewObservedUnitCost(observedUnitCost));
    }

    await _saveCustomCategories(custom);
  }

  /// Rimuove una categoria custom (non tocca mai i default).
  Future<void> removeCategory(String key) async {
    final custom = (await loadCustomCategories()).where((category) => category.key != key).toList(growable: false);
    await _saveCustomCategories(custom);
  }

  Future<void> _saveCustomCategories(List<CategoryReferenceModel> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(categories.map((category) => category.toJson()).toList(growable: false));
    await prefs.setString(_prefsKey, encoded);
  }
}