class OpenAiSavingsClient {
  OpenAiSavingsClient({
    this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
  });

  final String? apiKey;
  final String baseUrl;

  Future<List<Map<String, dynamic>>> analyzeShoppingPrompt(String userPrompt) async {
    if (apiKey == null || apiKey!.trim().isEmpty) {
      throw StateError('OpenAI API key is required to query the model.');
    }

    // Il layer Data si occupa della comunicazione esterna con OpenAI,
    // mentre il calcolo del costo unitario e del confronto di convenienza
    // avviene nel layer Domain / repository Dart, mai nell'LLM.
    throw UnimplementedError(
      'Implementare la chiamata HTTP a OpenAI con le credenziali e il formato delle risposta richiesti.',
    );
  }
}
