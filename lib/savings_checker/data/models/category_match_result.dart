import 'package:spesai/savings_checker/domain/entities/category_reference.dart';
import 'package:spesai/savings_checker/domain/entities/suggested_category.dart';

class CategoryMatchResult {
  const CategoryMatchResult({
    required this.defaultCategory,
    required this.isExactMatch,
    required this.suggestedCategory,
    required this.normalizedInput,
  });

  final CategoryReference? defaultCategory;
  final bool isExactMatch;
  final SuggestedCategory? suggestedCategory;
  final String normalizedInput;
}
