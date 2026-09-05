import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OpenAiSavingsClient {
  OpenAiSavingsClient({
    this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
  });

  final String? apiKey;
  final String baseUrl;

  static const String systemPrompt = '''
Sei un classificatore e parser di prodotti di spesa.

Ruolo:
- Estrai dati grezzi dal testo dell'utente.
- Concorda la categoria del prodotto con il catalogo di riferimento fornito.
- Non calcolare mai costo unitario, risparmio, medie, benchmark o confronto.
- Restituisci SOLO un JSON valido con la struttura richiesta.

Regole vincolanti:
1. Non calcolare mai costo unitario, risparmio, medie, benchmark o confronti.
2. Non includere mai i campi: unitCost, savings, averageUnitCost, comparison nei campi del prodotto.
3. specific_attributes contiene solo valori verificabili dal testo, mai valori inventati o precalcolati.
4. Se l'utente fornisce dati specifici (ad esempio sheets_per_roll: 500), non sostituirli mai con valori inventati.
5. Sii tollerante a refusi comuni: stramppi, rotolii, litrii, igenicaa, ecc.
6. Se la categoria è "toilet_paper" (o equivalente), primary_unit_name DEVE essere sempre "strappo".
7. Generalizza in modo aggressivo per prodotti dello stesso tipo di uso quotidiano: prodotti equivalenti vanno nella stessa categoria.
8. Se non esiste una categoria plausibile, crea una nuova categoria con key semplice in snake_case, ad esempio pet_food, cleaning_product, milk, bread.
9. I campi di categoria in category_match possono includere average_unit_cost ma non calcoli di business nel prodotto.
10. Rispondi sempre in JSON valido senza testo extra, senza code fence.

Formato richiesto:
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

  static Map<String, dynamic> parseModelResponse(String rawResponse) {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response from OpenAI.');
    }

    String jsonText = trimmed;
    final codeFenceMatch = RegExp(r'```(?:json)?\s*(.*?)\s*```', dotAll: true).firstMatch(trimmed);
    if (codeFenceMatch != null) {
      jsonText = codeFenceMatch.group(1) ?? trimmed;
    }

    final decoded = json.decode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('OpenAI response is not a JSON object.');
    }

    final product = decoded['product'];
    final categoryMatch = decoded['category_match'];

    if (product is! Map) {
      throw const FormatException('OpenAI response is missing the product object.');
    }

    if (categoryMatch is! Map) {
      throw const FormatException('OpenAI response is missing the category_match object.');
    }

    final productMap = Map<String, dynamic>.from(product as Map<dynamic, dynamic>);
    final categoryMatchMap = Map<String, dynamic>.from(categoryMatch as Map<dynamic, dynamic>);
    final categoryInfo = categoryMatchMap['category'];

    if (categoryInfo is! Map) {
      throw const FormatException('OpenAI response is missing category_match.category.');
    }

    final categoryMap = Map<String, dynamic>.from(categoryInfo as Map<dynamic, dynamic>);

    final requiredProductKeys = <String>{
      'category_key',
      'brand',
      'total_price',
      'units_per_package',
      'primary_unit_name',
      'specific_attributes',
    };
    final missingProductKeys = requiredProductKeys.difference(productMap.keys.toSet());
    if (missingProductKeys.isNotEmpty) {
      throw FormatException('OpenAI response is missing required product fields: ${missingProductKeys.join(', ')}');
    }

    final businessFields = <String>{'unitCost', 'savings', 'averageUnitCost', 'comparison'};
    for (final businessField in businessFields) {
      if (productMap.containsKey(businessField)) {
        throw FormatException('OpenAI response included business field: $businessField');
      }
    }

    final categoryKey = (productMap['category_key'] ?? categoryMap['key'] ?? '').toString();
    if (categoryKey == 'toilet_paper' || categoryMap['key'] == 'toilet_paper') {
      productMap['primary_unit_name'] = 'strappo';
      categoryMap['primary_unit'] = 'strappo';
      categoryMap['key'] = 'toilet_paper';
    }

    categoryMatchMap['category'] = categoryMap;
    productMap['category_key'] = categoryKey.isEmpty ? (categoryMap['key'] ?? '').toString() : categoryKey;

    final normalized = <String, dynamic>{
      'product': productMap,
      'category_match': categoryMatchMap,
    };

    return normalized;
  }

  Future<List<Map<String, dynamic>>> analyzeShoppingPrompt(String userPrompt) async {
    final extraction = await extractRawProductData(userPrompt);
    return <Map<String, dynamic>>[extraction];
  }

  Future<Map<String, dynamic>> analyzeProductWithCatalog(String userPrompt, String catalogJson) async {
    if (apiKey == null || apiKey!.trim().isEmpty) {
      throw StateError('OpenAI API key is required to query the model.');
    }

    final normalized = userPrompt.trim();
    if (normalized.isEmpty) {
      throw StateError('User prompt cannot be empty.');
    }

    final requestBody = buildRequestPayload(normalized, catalogJson);
    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: json.encode(requestBody),
    );

    debugPrint('OpenAI status=${response.statusCode}');
    debugPrint('OpenAI raw response=${response.body}');

    if (response.statusCode != 200) {
      throw StateError('OpenAI request failed with status ${response.statusCode}: ${response.body}');
    }

    final responseBody = json.decode(response.body) as Map<String, dynamic>;
    final choices = responseBody['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('OpenAI response has no choices.');
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('OpenAI response content is empty.');
    }

    return parseModelResponse(content);
  }

  Future<Map<String, dynamic>> extractRawProductData(String userPrompt, [String? catalogJson]) async {
    final safeCatalogJson = (catalogJson != null && catalogJson.trim().isNotEmpty)
        ? catalogJson
        : jsonEncode(<String, dynamic>{'categories': <Map<String, dynamic>>[]});
    return analyzeProductWithCatalog(userPrompt, safeCatalogJson);
  }

  Map<String, dynamic> buildRequestPayload(String userPrompt, [String? catalogJson]) {
    final catalogText = (catalogJson != null && catalogJson.trim().isNotEmpty)
        ? '\nCatalogo di riferimento JSON:\n$catalogJson'
        : '';

    return <String, dynamic>{
      'model': 'gpt-4o-mini',
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': 'PROMPT UTENTE:\n$userPrompt$catalogText'},
      ],
      'temperature': 0.1,
    };
  }
}
