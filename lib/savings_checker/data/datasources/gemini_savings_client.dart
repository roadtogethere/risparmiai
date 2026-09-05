import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_response_parser.dart';
import 'ai_savings_client.dart';

/// Client per l'API Gemini (Google Generative Language API).
/// Usa lo stesso system prompt e lo stesso parser/validatore di
/// [OpenAiSavingsClient], così la logica di business resta identica
/// indipendentemente dal provider scelto.
class GeminiSavingsClient implements AiSavingsClient {
  GeminiSavingsClient({
    this.apiKey,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    this.model = 'gemini-3.6-flash',
  });

  final String? apiKey;
  final String baseUrl;
  final String model;

  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String userPrompt,
    String catalogJson,
  ) async {
    debugPrint('Gemini client: analyzeProductWithCatalog called');
    debugPrint('Gemini client: model=$model, baseUrl=$baseUrl');
    debugPrint('Gemini client: prompt="${userPrompt.trim()}"');

    if (apiKey == null || apiKey!.trim().isEmpty) {
      debugPrint('Gemini client: API key missing');
      throw StateError('Gemini API key is required to query the model.');
    }

    final normalized = userPrompt.trim();
    if (normalized.isEmpty) {
      debugPrint('Gemini client: empty prompt');
      throw StateError('User prompt cannot be empty.');
    }

    final requestBody = buildRequestPayload(normalized, catalogJson);
    final uri = Uri.parse('$baseUrl/models/$model:generateContent?key=$apiKey');

    debugPrint('Gemini client: request URI=$uri');
    debugPrint('Gemini client: request body=${json.encode(requestBody)}');

    final response = await http.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: json.encode(requestBody),
    );

    debugPrint('Gemini client: status=${response.statusCode}');
    debugPrint('Gemini client: raw response=${response.body}');

    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        debugPrint('Gemini client: model "$model" is unavailable for this API version. Try a supported model such as gemini-2.0-flash.');
      }
      throw StateError('Gemini request failed with status ${response.statusCode}: ${response.body}');
    }

    final responseBody = json.decode(response.body) as Map<String, dynamic>;
    final candidates = responseBody['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const FormatException('Gemini response has no candidates.');
    }

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw const FormatException('Gemini response has no content parts.');
    }

    final text = parts.first['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const FormatException('Gemini response text is empty.');
    }

    return AiResponseParser.parseModelResponse(text);
  }

  Map<String, dynamic> buildRequestPayload(String userPrompt, String? catalogJson) {
    final userText = buildUserPromptWithCatalog(userPrompt, catalogJson);

    return <String, dynamic>{
      'system_instruction': <String, dynamic>{
        'parts': <Map<String, String>>[
          <String, String>{'text': kSavingsSystemPrompt},
        ],
      },
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'parts': <Map<String, String>>[
            <String, String>{'text': userText},
          ],
        },
      ],
      'generationConfig': <String, dynamic>{
        'temperature': 0.1,
        'responseMimeType': 'application/json',
      },
    };
  }
}
