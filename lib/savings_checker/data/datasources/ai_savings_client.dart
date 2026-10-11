/// Contratto comune per qualunque provider AI (OpenAI, Gemini, ecc.)
/// usato per estrarre dati grezzi del prodotto e proporre/confermare
/// la categoria di riferimento a partire da un catalogo fornito.
///
/// I provider live restituiscono il protocollo M4A validato da QuantityPlanParser:
/// status/category/facts/operation/missing/question. Il parser del vecchio
/// protocollo product/category_match rimane un adapter legacy esplicito.
abstract class AiSavingsClient {
  Future<Map<String, dynamic>> analyzeProductWithCatalog(
    String userPrompt,
    String catalogJson,
  );
}
