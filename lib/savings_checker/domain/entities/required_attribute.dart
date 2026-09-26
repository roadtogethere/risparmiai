/// Un attributo richiesto per calcolare correttamente il costo unitario
/// di una categoria (es. "rolls_count" -> "Numero rotoli").
///
/// La [label] leggibile viene fornita direttamente dall'AI insieme alla
/// [key] tecnica, così qualunque nuova categoria arriva già con un testo
/// mostrabile in UI senza bisogno di dizionari statici lato Dart.
class RequiredAttribute {
  const RequiredAttribute({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;

  factory RequiredAttribute.fromJson(dynamic json) {
    if (json is Map) {
      final map = Map<String, dynamic>.from(json);
      final key = (map['key'] ?? '').toString();
      final label = (map['label'] ?? '').toString();
      return RequiredAttribute(key: key, label: label.isEmpty ? _humanize(key) : label);
    }

    // Retrocompatibilità: formati legacy con solo stringhe (es. il seed
    // iniziale di default_categories.json, o risposte AI non aggiornate).
    final key = json.toString();
    return RequiredAttribute(key: key, label: _humanize(key));
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'key': key, 'label': label};
  }

  static String _humanize(String key) {
    if (key.trim().isEmpty) {
      return key;
    }
    final withSpaces = key.replaceAll('_', ' ').trim();
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }
}