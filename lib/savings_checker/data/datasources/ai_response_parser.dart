import 'dart:convert';

/// System prompt condiviso da tutti i provider AI.
/// 
/// Fissa le regole di business e definisce lo schema JSON esatto che il modello
/// DEVE restituire per evitare risposte testuali extra o calcoli non autorizzati.
const String kSavingsSystemPrompt = '''
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

/// Costruisce il testo dell'utente unendo il prompt di input con il catalogo prodotti JSON.
///
/// * [userPrompt]: La stringa inserita dall'utente (es. "Carta igienica 12 rotoli 5.99€").
/// * [catalogJson]: Il catalogo di riferimento in formato stringa JSON (opzionale).
///
/// Restituisce la stringa formattata da inviare come contenuto `user` al modello.
String buildUserPromptWithCatalog(String userPrompt, String? catalogJson) {
  final catalogText = (catalogJson != null && catalogJson.trim().isNotEmpty)
      ? '\nCatalogo di riferimento JSON:\n$catalogJson'
      : '';
  return 'PROMPT UTENTE:\n$userPrompt$catalogText';
}

/// Utility class statica per il parsing, la pulizia e la validazione della risposta dell'AI.
///
/// Indipendente dal provider (Gemini, OpenAI, Anthropic), assicura che il JSON
/// restituito rispetti rigorosamente il contratto dati dell'applicazione.
class AiResponseParser {
  /// Costruttore privato per impedire l'istanziamento di questa utility class.
  const AiResponseParser._();

  /// Analizza e valida la stringa grezza [rawResponse] restituita da un modello AI.
  ///
  /// * Rimuove eventuali blocchi code fence (` ```json ... ``` `).
  /// * Converte il testo in un oggetto [Map].
  /// * Valida la presenza di `product`, `category_match` e `category`.
  /// * Verifica la presenza delle chiavi obbligatorie del prodotto.
  /// * Garantisce che l'AI non abbia inserito campi di business non autorizzati (`unitCost`, `savings`, ecc.).
  /// * Normalizza le unità di misura per la categoria `toilet_paper`.
  ///
  /// Lancia un [FormatException] se la risposta è vuota, non è un JSON valido o manca di campi obbligatori.
  static Map<String, dynamic> parseModelResponse(String rawResponse) {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response from AI provider.');
    }

    // Rimuove eventuali Markdown Code Fences se presenti nella risposta
    String jsonText = trimmed;
    final codeFenceMatch = RegExp(r'```(?:json)?\s*(.*?)\s*```', dotAll: true).firstMatch(trimmed);
    if (codeFenceMatch != null) {
      jsonText = codeFenceMatch.group(1) ?? trimmed;
    }

    // Decodifica della stringa JSON
    final decoded = json.decode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI response is not a JSON object.');
    }

    final product = decoded['product'];
    final categoryMatch = decoded['category_match'];

    // Validazione dei nodi principali del JSON
    if (product is! Map) {
      throw const FormatException('AI response is missing the product object.');
    }

    if (categoryMatch is! Map) {
      throw const FormatException('AI response is missing the category_match object.');
    }

    final productMap = Map<String, dynamic>.from(product as Map<dynamic, dynamic>);
    final categoryMatchMap = Map<String, dynamic>.from(categoryMatch as Map<dynamic, dynamic>);
    final categoryInfo = categoryMatchMap['category'];

    if (categoryInfo is! Map) {
      throw const FormatException('AI response is missing category_match.category.');
    }

    final categoryMap = Map<String, dynamic>.from(categoryInfo as Map<dynamic, dynamic>);

    // Validazione dei campi minimi richiesti per la mappa product
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
      throw FormatException('AI response is missing required product fields: ${missingProductKeys.join(', ')}');
    }

    // Controllo di sicurezza: scarta la risposta se il modello ha calcolato valori di business
    final businessFields = <String>{'unitCost', 'savings', 'averageUnitCost', 'comparison'};
    for (final businessField in businessFields) {
      if (productMap.containsKey(businessField)) {
        throw FormatException('AI response included business field: $businessField');
      }
    }

    // Sanificazione specifica per la categoria "toilet_paper"
    final categoryKey = (productMap['category_key'] ?? categoryMap['key'] ?? '').toString();
    if (categoryKey == 'toilet_paper' || categoryMap['key'] == 'toilet_paper') {
      productMap['primary_unit_name'] = 'strappo';
      categoryMap['primary_unit'] = 'strappo';
      categoryMap['key'] = 'toilet_paper';
    }

    categoryMatchMap['category'] = categoryMap;
    productMap['category_key'] = categoryKey.isEmpty ? (categoryMap['key'] ?? '').toString() : categoryKey;

    return <String, dynamic>{
      'product': productMap,
      'category_match': categoryMatchMap,
    };
  }
}