import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_response_parser.dart';
import 'ai_savings_client.dart';
import '../models/quantity_plan_parser.dart';

class OpenAiSavingsClient implements AiSavingsClient {
  OpenAiSavingsClient({
    this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
  });

  final String? apiKey;
  final String baseUrl;

  static const String systemPrompt = kSavingsSystemPrompt;

  static Map<String, dynamic> parseModelResponse(String rawResponse) {
    return AiResponseParser.parseModelResponse(rawResponse);
  }

  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String userPrompt,
    String catalogJson,
  ) async {
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
      throw StateError(
        'OpenAI request failed with status ${response.statusCode}: ${response.body}',
      );
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

    return QuantityPlanParser.decode(content);
  }

  Future<List<Map<String, dynamic>>> analyzeShoppingPrompt(
    String userPrompt,
  ) async {
    final extraction = await extractRawProductData(userPrompt);
    return <Map<String, dynamic>>[extraction];
  }

  Future<Map<String, dynamic>> extractRawProductData(
    String userPrompt, [
    String? catalogJson,
  ]) async {
    final safeCatalogJson =
        (catalogJson != null && catalogJson.trim().isNotEmpty)
        ? catalogJson
        : jsonEncode(<String, dynamic>{'categories': <Map<String, dynamic>>[]});
    return analyzeProductWithCatalog(userPrompt, safeCatalogJson);
  }

  Map<String, dynamic> buildRequestPayload(
    String userPrompt, [
    String? catalogJson,
  ]) {
    final userText = buildUserPromptWithCatalog(userPrompt, catalogJson);

    return <String, dynamic>{
      'model': 'gpt-4o-mini',
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': userText},
      ],
      'temperature': 0.1,
    };
  }
}
