import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_response_parser.dart';
import 'ai_savings_client.dart';
import '../models/quantity_plan_parser.dart';

/// Client HTTP per l'integrazione con l'API Gemini di Google Generative AI.
///
/// Implementa [AiSavingsClient] garantendo la stessa interfaccia e logica
/// di parsing utilizzata da altri provider (es. OpenAI).
class GeminiSavingsClient implements AiSavingsClient {
  /// Crea un'istanza di [GeminiSavingsClient].
  ///
  /// * [apiKey]: Chiave API di Google AI Studio (obbligatoria per le chiamate).
  /// * [baseUrl]: Endpoint base dell'API (default v1beta).
  /// * [model]: Identificatore del modello Gemini da invocare.
  GeminiSavingsClient({
    this.apiKey,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    this.model = 'gemini-3.6-flash',
  });

  /// Chiave API usata per autenticare le richieste su Google AI Studio.
  final String? apiKey;

  /// URL base dell'API Generative Language di Google.
  final String baseUrl;

  /// Il modello Gemini target per la generazione dei contenuti.
  final String model;

  /// Analizza il prompt dell'utente e il catalogo prodotti tramite l'API Gemini.
  ///
  /// Processa l'input, invia una richiesta POST HTTP all'endpoint di generazione
  /// ed estrae la risposta JSON validandola tramite [AiResponseParser].
  ///
  /// Lancia un [StateError] se la API key manca, se il prompt è vuoto o non valido,
  /// oppure se il server risponde con un codice di errore HTTP.
  /// Lancia un [FormatException] se la struttura della risposta JSON non è valida.
  @override
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String userPrompt,
    String catalogJson,
  ) async {
    debugPrint('Gemini client: analyzeProductWithCatalog called');
    debugPrint('Gemini client: model=$model, baseUrl=$baseUrl');
    debugPrint('Gemini client: prompt="${userPrompt.trim()}"');

    // Controllo la presenza della chiave API
    if (apiKey == null || apiKey!.trim().isEmpty) {
      debugPrint('Gemini client: API key missing');
      throw StateError('Gemini API key is required to query the model.');
    }

    // Normalizzazione e validazione base del prompt utente
    final normalized = userPrompt.trim();
    if (normalized.isEmpty) {
      debugPrint('Gemini client: empty prompt');
      throw StateError('User prompt cannot be empty.');
    }

    // Costruzione e preparazione del payload HTTP
    final requestBody = buildRequestPayload(normalized, catalogJson);
    final uri = Uri.parse('$baseUrl/models/$model:generateContent?key=$apiKey');

    debugPrint('Gemini client: request body=${json.encode(requestBody)}');

    // Esecuzione della chiamata API verso Google
    final response = await http.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: json.encode(requestBody),
    );

    debugPrint('Gemini client: status=${response.statusCode}');
    debugPrint('Gemini client: raw response=${response.body}');

    // Gestione dei codici di errore HTTP
    if (response.statusCode != 200) {
      if (response.statusCode == 404 || response.statusCode == 400) {
        debugPrint(
          'Gemini client: model "$model" is unavailable or rejected by this API version. Try a supported model such as gemini-2.0-flash.',
        );
      }
      throw StateError(
        'Gemini request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    // Parsing della risposta JSON dell'API Gemini
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

    // Conversione del testo restituito dal modello in una mappa strutturata
    return QuantityPlanParser.decode(text);
  }

  /// Costruisce la struttura dati della mappa JSON da inviare nel corpo della richiesta REST a Gemini.
  ///
  /// Configura:
  /// * `system_instruction`: Il prompt di sistema [kSavingsSystemPrompt].
  /// * `contents`: L'input combinato dell'utente e del catalogo.
  /// * `generationConfig`: Parametri di generazione (bassa temperatura, output JSON e disattivazione del budget di ragionamento).
  Map<String, dynamic> buildRequestPayload(
    String userPrompt,
    String? catalogJson,
  ) {
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
