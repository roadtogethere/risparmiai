import 'dart:convert';

/// System prompt condiviso da tutti i provider AI.
/// Descrive il formato JSON che il modello deve restituire.
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
6. primary_unit_name deve descrivere il denominatore effettivamente estratto. Non cambiare unità per adeguarla al catalogo: se sono disponibili solo rotoli, mantieni rotolo; non inventare fogli per rotolo.
7. Generalizza in modo aggressivo per prodotti dello stesso tipo di uso quotidiano: prodotti equivalenti vanno nella stessa categoria.
8. Se non esiste una categoria plausibile, crea una nuova categoria con key semplice in snake_case, ad esempio pet_food, cleaning_product, milk, bread.
9. I campi di categoria in category_match possono includere average_unit_cost ma non calcoli di business nel prodotto.
10. Ogni voce di required_attributes DEVE essere un oggetto con "key" (snake_case tecnico, es. "sheets_per_roll") e "label" (nome leggibile in italiano per l'utente finale, es. "Fogli per rotolo"). Non restituire mai required_attributes come semplici stringhe.
11. Rispondi sempre in JSON valido senza testo extra, senza code fence.

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
      "required_attributes": [
        {"key": "rolls_count", "label": "Numero rotoli"},
        {"key": "sheets_per_roll", "label": "Fogli per rotolo"}
      ]
    }
  }
}
''';

/// Costruisce il testo utente da inviare al modello, includendo
/// il catalogo di riferimento (default + custom, uniti lato Dart).
String buildUserPromptWithCatalog(String userPrompt, String? catalogJson) {
  final catalogText = (catalogJson != null && catalogJson.trim().isNotEmpty)
      ? '\nCatalogo di riferimento JSON:\n$catalogJson'
      : '';
  return 'PROMPT UTENTE:\n$userPrompt$catalogText';
}

/// Normalizza una singola voce di required_attributes, accettando sia il
/// nuovo formato {key,label} sia stringhe semplici (retrocompatibilità con
/// risposte AI vecchie o dataset legacy).
Map<String, dynamic> _normalizeRequiredAttributeEntry(dynamic entry) {
  if (entry is Map) {
    final map = Map<String, dynamic>.from(entry);
    final key = (map['key'] ?? '').toString();
    final label = (map['label'] ?? '').toString();
    return <String, dynamic>{'key': key, 'label': label.isEmpty ? key : label};
  }

  final key = entry.toString();
  return <String, dynamic>{'key': key, 'label': key};
}

/// Parsing e validazione della risposta testuale del modello (qualunque
/// provider), condivisa da tutti i client AI in modo che la logica di
/// business/validazione non venga duplicata per ogni integrazione.
class AiResponseParser {
  const AiResponseParser._();

  static Map<String, dynamic> parseModelResponse(String rawResponse) {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response from AI provider.');
    }

    String jsonText = trimmed;
    final codeFenceMatch = RegExp(
      r'```(?:json)?\s*(.*?)\s*```',
      dotAll: true,
    ).firstMatch(trimmed);
    if (codeFenceMatch != null) {
      jsonText = codeFenceMatch.group(1) ?? trimmed;
    }

    final decoded = json.decode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI response is not a JSON object.');
    }

    final product = decoded['product'];
    final categoryMatch = decoded['category_match'];

    if (product is! Map) {
      throw const FormatException('AI response is missing the product object.');
    }

    if (categoryMatch is! Map) {
      throw const FormatException(
        'AI response is missing the category_match object.',
      );
    }

    final productMap = Map<String, dynamic>.from(
      product as Map<dynamic, dynamic>,
    );
    final categoryMatchMap = Map<String, dynamic>.from(
      categoryMatch as Map<dynamic, dynamic>,
    );
    final categoryInfo = categoryMatchMap['category'];

    if (categoryInfo is! Map) {
      throw const FormatException(
        'AI response is missing category_match.category.',
      );
    }

    final categoryMap = Map<String, dynamic>.from(
      categoryInfo as Map<dynamic, dynamic>,
    );

    final requiredProductKeys = <String>{
      'category_key',
      'brand',
      'total_price',
      'units_per_package',
      'primary_unit_name',
      'specific_attributes',
    };
    final missingProductKeys = requiredProductKeys.difference(
      productMap.keys.toSet(),
    );
    if (missingProductKeys.isNotEmpty) {
      throw FormatException(
        'AI response is missing required product fields: ${missingProductKeys.join(', ')}',
      );
    }

    final businessFields = <String>{
      'unitCost',
      'savings',
      'averageUnitCost',
      'comparison',
    };
    for (final businessField in businessFields) {
      if (productMap.containsKey(businessField)) {
        throw FormatException(
          'AI response included business field: $businessField',
        );
      }
    }

    // Normalizza required_attributes al formato {key,label}, accettando
    // anche stringhe semplici per retrocompatibilità.
    final rawRequiredAttributes = categoryMap['required_attributes'];
    if (rawRequiredAttributes is List) {
      categoryMap['required_attributes'] = rawRequiredAttributes
          .map(_normalizeRequiredAttributeEntry)
          .toList(growable: false);
    } else {
      categoryMap['required_attributes'] = const <Map<String, dynamic>>[];
    }

    final categoryKey = (productMap['category_key'] ?? categoryMap['key'] ?? '')
        .toString();
    categoryMatchMap['category'] = categoryMap;
    productMap['category_key'] = categoryKey.isEmpty
        ? (categoryMap['key'] ?? '').toString()
        : categoryKey;

    return <String, dynamic>{
      'product': productMap,
      'category_match': categoryMatchMap,
    };
  }
}
