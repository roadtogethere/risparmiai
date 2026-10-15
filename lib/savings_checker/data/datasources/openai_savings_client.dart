import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../domain/entities/savings_failure.dart';

import 'ai_response_parser.dart';
import 'ai_savings_client.dart';
import 'ai_http_request.dart';
import '../models/quantity_plan_parser.dart';

class OpenAiSavingsClient implements AiSavingsClient {
  OpenAiSavingsClient({
    this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
    this.requestTimeout = const Duration(seconds: 30),
    this.totalRequestTimeout = const Duration(seconds: 30),
    this.retryDelay = const Duration(milliseconds: 500),
    this.automaticRetry = true,
    http.Client Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new;

  final Duration requestTimeout;
  final Duration totalRequestTimeout;
  final Duration retryDelay;
  final bool automaticRetry;
  final http.Client Function() _httpClientFactory;

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
      throw const SavingsFailure(SavingsFailureKind.authenticationError);
    }

    final normalized = userPrompt.trim();
    if (normalized.isEmpty) {
      throw StateError('User prompt cannot be empty.');
    }

    final requestBody = buildRequestPayload(normalized, catalogJson);
    final response = await postAiRequest(
      Uri.parse('$baseUrl/chat/completions'),
      timeout: requestTimeout,
      totalTimeout: totalRequestTimeout,
      retryDelay: retryDelay,
      automaticRetry: automaticRetry,
      clientFactory: _httpClientFactory,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: json.encode(requestBody),
    );

    try {
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
    } catch (_) {
      throw const SavingsFailure(SavingsFailureKind.parseError);
    }
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
      'model': 'gpt-6-luna',
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': userText},
      ],
      'reasoning_effort': 'none',
    };
  }
}
