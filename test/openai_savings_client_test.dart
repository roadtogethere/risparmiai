import 'package:flutter_test/flutter_test.dart';
import 'package:spesai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:spesai/savings_checker/data/models/product_analysis_model.dart';

void main() {
  group('OpenAiSavingsClient', () {
    test('parses raw extraction JSON and forbids business fields', () {
      const rawResponse = '''
      {
        "category_key": "toilet_paper",
        "brand": "Migliore",
        "total_price": 5.99,
        "units_per_package": 12,
        "sub_units_per_package": 500,
        "primary_unit_name": "strappo",
        "specific_attributes": {
          "rolls_count": 12,
          "sheets_per_roll": 500,
          "material": "cellulosa"
        }
      }
      ''';

      final parsed = OpenAiSavingsClient.parseModelResponse(rawResponse);

      expect(parsed['category_key'], 'toilet_paper');
      expect(parsed['primary_unit_name'], 'strappo');
      expect(parsed.containsKey('unitCost'), isFalse);
      expect(parsed.containsKey('savings'), isFalse);
      expect(parsed.containsKey('averageUnitCost'), isFalse);
    });

    test('does not force strappo for generic household products', () {
      final parsed = ProductAnalysisModel.fromJson({
        'id': 'detergent_1',
        'productName': 'Detersivo per lavatrice',
        'brand': 'EcoCare',
        'category': 'household',
        'totalPrice': 5.99,
        'primaryUnitName': 'litro',
        'totalUnitsCount': 2.5,
        'specificAttributes': {
          'total_liters': 2.5,
          'total_washes': 40,
        },
      });

      expect(parsed.primaryUnitName, 'litro');
      expect(parsed.category.name, 'household');
    });
  });
}
