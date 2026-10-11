import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/category_reference_model.dart';

class CategoryReferenceDataSource {
  const CategoryReferenceDataSource();

  static Future<List<CategoryReferenceModel>>? _cachedCategories;

  Future<List<CategoryReferenceModel>> loadDefaultCategories() {
    return _cachedCategories ??= _loadDefaultCategories();
  }

  Future<List<CategoryReferenceModel>> _loadDefaultCategories() async {
    final raw = await rootBundle.loadString(
      'assets/json/default_categories.json',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entries = decoded['categories'];

    if (entries is! List) {
      return const <CategoryReferenceModel>[];
    }

    return entries
        .whereType<Map<String, dynamic>>()
        .map(CategoryReferenceModel.fromJson)
        .toList(growable: false);
  }
}
