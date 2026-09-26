import 'package:risparmiai/savings_checker/data/datasources/category_reference_data_source.dart';
import 'package:risparmiai/savings_checker/data/models/category_match_result.dart';
import 'package:risparmiai/savings_checker/domain/entities/suggested_category.dart';

class CategoryMatcher {
  CategoryMatcher({CategoryReferenceDataSource? dataSource})
    : _dataSource = dataSource ?? const CategoryReferenceDataSource();

  final CategoryReferenceDataSource _dataSource;

  static String normalizeText(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final replacements = <String, String>{
      'stramppi': 'strappi',
      'rotolii': 'rotoli',
      'litrii': 'litri',
      'igienicaa': 'igienica',
      'igieniciai': 'igienica',
      'igienicai': 'igienica',
      'cartaigienica': 'carta igienica',
      'cartaigienicai': 'carta igienica',
      'rotoli': 'rotoli',
    };

    var result = normalized;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    return result;
  }

  Future<CategoryMatchResult> match(String userInput) async {
    final normalizedInput = normalizeText(userInput);
    final categories = await _dataSource.loadDefaultCategories();

    for (final category in categories) {
      final aliases = <String>{
        category.key,
        category.displayName,
        category.primaryUnit,
        ...category.requiredAttributes.map((attribute) => attribute.key),
        ...category.requiredAttributes.map((attribute) => attribute.label),
      };

      final candidates = <String>{...aliases, ...aliases.map(normalizeText)};

      if (candidates.any(
        (value) =>
            normalizedInput.contains(value) || value.contains(normalizedInput),
      )) {
        return CategoryMatchResult(
          defaultCategory: category,
          isExactMatch: true,
          suggestedCategory: null,
          normalizedInput: normalizedInput,
        );
      }
    }

    final suggested = SuggestedCategory(
      categoryKey: _suggestCategoryKey(normalizedInput),
      displayName: _suggestDisplayName(normalizedInput),
      primaryUnitName: _guessPrimaryUnit(normalizedInput),
      averageUnitCost: 0,
      aliases: _buildAliasList(normalizedInput),
      requiredAttributes: _guessRequiredAttributes(normalizedInput),
    );

    return CategoryMatchResult(
      defaultCategory: null,
      isExactMatch: false,
      suggestedCategory: suggested,
      normalizedInput: normalizedInput,
    );
  }

  String _suggestCategoryKey(String normalizedInput) {
    if (normalizedInput.contains('carta') &&
        normalizedInput.contains('igienica')) {
      return 'toilet_paper';
    }
    if (normalizedInput.contains('detersivo') &&
        normalizedInput.contains('lavatrice')) {
      return 'laundry_detergent_liquid';
    }
    if (normalizedInput.contains('pane')) {
      return 'sliced_bread';
    }
    if (normalizedInput.contains('lavastoviglie')) {
      return 'dishwasher_tabs';
    }
    if (normalizedInput.contains('latte')) {
      return 'uht_milk';
    }
    return 'custom_category';
  }

  String _suggestDisplayName(String normalizedInput) {
    final key = _suggestCategoryKey(normalizedInput);
    switch (key) {
      case 'toilet_paper':
        return 'Carta Igienica';
      case 'laundry_detergent_liquid':
        return 'Detersivo Liquido Lavatrice';
      case 'sliced_bread':
        return 'Pane';
      case 'dishwasher_tabs':
        return 'Pastiglie Lavastoviglie';
      case 'uht_milk':
        return 'Latte UHT';
      default:
        return 'Categoria personalizzata';
    }
  }

  String _guessPrimaryUnit(String normalizedInput) {
    if (normalizedInput.contains('igienica')) {
      return 'strappo';
    }
    if (normalizedInput.contains('lavatrice') ||
        normalizedInput.contains('lavastoviglie')) {
      return 'lavaggio';
    }
    if (normalizedInput.contains('caffe') ||
        normalizedInput.contains('capsule')) {
      return 'capsula';
    }
    if (normalizedInput.contains('latte') || normalizedInput.contains('olio')) {
      return 'litro';
    }
    if (normalizedInput.contains('pane')) {
      return 'fetta';
    }
    return 'unità';
  }

  List<String> _guessRequiredAttributes(String normalizedInput) {
    if (normalizedInput.contains('igienica')) {
      return <String>['rolls_count', 'sheets_per_roll'];
    }
    if (normalizedInput.contains('lavatrice') ||
        normalizedInput.contains('lavastoviglie')) {
      return <String>['total_liters', 'total_washes'];
    }
    if (normalizedInput.contains('pane')) {
      return <String>['slices_count'];
    }
    if (normalizedInput.contains('latte') || normalizedInput.contains('olio')) {
      return <String>['total_liters'];
    }
    return <String>[];
  }

  List<String> _buildAliasList(String normalizedInput) {
    final key = _suggestCategoryKey(normalizedInput);
    switch (key) {
      case 'toilet_paper':
        return <String>['carta igienica', 'toilet paper', 'igienica'];
      case 'laundry_detergent_liquid':
        return <String>['detersivo lavatrice', 'lavatrice'];
      case 'sliced_bread':
        return <String>['pane', 'pan bauletto'];
      case 'dishwasher_tabs':
        return <String>['lavastoviglie', 'pastiglie'];
      case 'uht_milk':
        return <String>['latte', 'latte uht'];
      default:
        return <String>[normalizedInput];
    }
  }
}
