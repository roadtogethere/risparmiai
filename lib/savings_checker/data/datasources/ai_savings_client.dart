/// Contratto comune per qualunque provider AI (OpenAI, Gemini, ecc.)
/// usato per estrarre dati grezzi del prodotto e proporre/confermare
/// la categoria di riferimento a partire da un catalogo fornito.
///
/// Il risultato restituito è sempre nella stessa forma normalizzata,
/// già validata da [AiResponseParser.parseModelResponse]:
/// {
///   "product": { ... },
///   "category_match": { "is_exact_match": bool, "needs_update": bool, "category": {...} }
/// }
abstract class AiSavingsClient {
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String userPrompt,
    String catalogJson,
  );
}
