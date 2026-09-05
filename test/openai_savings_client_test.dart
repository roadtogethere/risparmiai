import 'package:flutter_test/flutter_test.dart';
import 'package:spesai/savings_checker/data/datasources/openai_savings_client.dart';

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
  });
}
