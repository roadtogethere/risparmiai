import 'dart:convert';

import 'package:http/http.dart' as http;

class OpenAiSavingsClient {
  OpenAiSavingsClient({
    this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
  });

  final String? apiKey;
  final String baseUrl;

  static const String systemPrompt = '''
Sei un classificatore e parser di prodotto di spesa.

Regole vincolanti:
1. Non calcolare mai il costo unitario, il risparmio o il confronto di convenienza.
2. Estrai SOLO i dati grezzi necessari per un parsing successivo in Dart.
3. Ritorna un JSON di questo formato ESATTAMENTE:
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
4. Se la categoria è carta igienica, `primary_unit_name` DEVE essere sempre "strappo".
5. Se l'utente indica rotoli e strappi per rotolo, usa `units_per_package` e `sub_units_per_package` e non inventare valori alternativi.
6. Non usare mai valori fallback inventati come `sheetsPerRoll: 200` se l'utente ha già fornito 500.
7. Sii tollerante ai refusi: `stramppi`, `rotolii`, `litrii`, `strappi`, `capsule`, `lavaggi`.
8. `specific_attributes` contiene solo attributi verificabili dal testo e non valori pre-calcolati.
9. Non includere `unitCost`, `savings`, `averageUnitCost`, `comparison` o altri campi di business.
10. Se la categoria non è nota, suggerisci una nuova `category_key` semplice, come `pet_food`, `cleaning_product`, `milk`, `bread`.
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

    final decoded = json.decode(jsonText) as Map<String, dynamic>;
    final requiredKeys = <String>{
      'category_key',
      'brand',
      'total_price',
      'units_per_package',
      'primary_unit_name',
      'specific_attributes',
    };

    final missingKeys = requiredKeys.difference(decoded.keys.toSet());
    if (missingKeys.isNotEmpty) {
      throw FormatException('OpenAI response is missing required fields: ${missingKeys.join(', ')}');
    }

    final businessFields = <String>{'unitCost', 'savings', 'averageUnitCost', 'comparison'};
    for (final businessField in businessFields) {
      if (decoded.containsKey(businessField)) {
        throw FormatException('OpenAI response included business field: $businessField');
      }
    }

    return decoded;
  }

  Future<List<Map<String, dynamic>>> analyzeShoppingPrompt(String userPrompt) async {
    final extraction = await extractRawProductData(userPrompt);
    return <Map<String, dynamic>>[extraction];
  }

  Future<Map<String, dynamic>> extractRawProductData(String userPrompt) async {
    if (apiKey == null || apiKey!.trim().isEmpty) {
      throw StateError('OpenAI API key is required to query the model.');
    }

    final normalized = userPrompt.trim();
    if (normalized.isEmpty) {
      throw StateError('User prompt cannot be empty.');
    }

    final requestBody = buildRequestPayload(normalized);
    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: json.encode(requestBody),
    );

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

  Map<String, dynamic> buildRequestPayload(String userPrompt) {
    return <String, dynamic>{
      'model': 'gpt-4o-mini',
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.1,
    };
  }
}
