import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/category_reference_model.dart';
import 'category_reference_data_source.dart';

class CategoryReferenceStore {
  const CategoryReferenceStore();

  static const String _prefsKey = 'risparmiai_category_reference_store_v1';

  Future<List<CategoryReferenceModel>> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_prefsKey);

    if (rawJson == null || rawJson.trim().isEmpty) {
      final seeded = await const CategoryReferenceDataSource().loadDefaultCategories();
      await saveCategories(seeded);
      return seeded;
    }

    try {
      final decoded = jsonDecode(rawJson);
      final entries = decoded is Map<String, dynamic> ? decoded['categories'] : decoded;

      if (entries is! List) {
        throw const FormatException('Stored categories are invalid.');
      }

      final categories = entries
          .whereType<Map<String, dynamic>>()
          .map(CategoryReferenceModel.fromJson)
          .toList(growable: false);

      if (categories.isNotEmpty) {
        return categories;
      }
    } catch (_) {
      // Fall back to the asset seed when stored data is missing or corrupted.
    }

    final seeded = await const CategoryReferenceDataSource().loadDefaultCategories();
    await saveCategories(seeded);
    return seeded;
  }

  Future<void> saveCategories(List<CategoryReferenceModel> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'categories': categories.map((category) => category.toJson()).toList(growable: false),
    };
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }

  Future<void> upsertCategory(CategoryReferenceModel category) async {
    final categories = await loadCategories();
    final index = categories.indexWhere((item) => item.key == category.key);

    if (index >= 0) {
      categories[index] = category;
    } else {
      categories.add(category);
    }

    await saveCategories(categories);
  }
}
