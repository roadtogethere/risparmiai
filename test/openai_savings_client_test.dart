import 'package:flutter_test/flutter_test.dart';
import 'package:spesai/savings_checker/data/datasources/openai_savings_client.dart';
import 'package:spesai/savings_checker/data/models/product_analysis_model.dart';
import 'package:spesai/savings_checker/presentation/notifiers/savings_chat_notifier.dart';

void main() {
  group('OpenAiSavingsClient', () {
    test('parses nested product and category_match JSON and forbids business fields', () {
      const rawResponse = '''
      {
        "product": {
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
        },
        "category_match": {
          "is_exact_match": true,
          "needs_update": false,
          "category": {
            "key": "toilet_paper",
            "display_name": "Carta Igienica",
            "primary_unit": "strappo",
            "average_unit_cost": 0.00185,
            "required_attributes": ["rolls_count", "sheets_per_roll"]
          }
        }
      }
      ''';

      final parsed = OpenAiSavingsClient.parseModelResponse(rawResponse);

      expect(parsed['product']['category_key'], 'toilet_paper');
      expect(parsed['product']['primary_unit_name'], 'strappo');
      expect(parsed['category_match']['category']['key'], 'toilet_paper');
      expect(parsed['category_match']['needs_update'], isFalse);
      expect(parsed['product'].containsKey('unitCost'), isFalse);
      expect(parsed['product'].containsKey('savings'), isFalse);
      expect(parsed['product'].containsKey('averageUnitCost'), isFalse);
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

    test('formats tiny costs with more than two decimals without trailing zeros', () {
      expect(SavingsChatNotifier.formatUnitCost(0.00185), '0.00185');
      expect(SavingsChatNotifier.formatUnitCost(5.99), '5.99');
      expect(SavingsChatNotifier.formatUnitCost(12), '12');
    });
  });
}
