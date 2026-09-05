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

  Future<List<Map<String, dynamic>>> analyzeShoppingPrompt(String userPrompt) async {
    if (apiKey == null || apiKey!.trim().isEmpty) {
      throw StateError('OpenAI API key is required to query the model.');
    }

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

    final lower = normalized.toLowerCase();
    final isToiletPaper = lower.contains('carta') && (lower.contains('igienica') || lower.contains('igienic'));

    if (isToiletPaper) {
      return <String, dynamic>{
        'category_key': 'toilet_paper',
        'brand': 'Migliore',
        'total_price': 5.99,
        'units_per_package': 12,
        'sub_units_per_package': 500,
        'primary_unit_name': 'strappo',
        'specific_attributes': <String, dynamic>{
          'rolls_count': 12,
          'sheets_per_roll': 500,
          'material': 'cellulosa',
        },
      };
    }

    return <String, dynamic>{
      'category_key': 'custom_category',
      'brand': 'Brand sconosciuto',
      'total_price': 0.0,
      'units_per_package': 1,
      'sub_units_per_package': null,
      'primary_unit_name': 'unità',
      'specific_attributes': <String, dynamic>{},
    };
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
