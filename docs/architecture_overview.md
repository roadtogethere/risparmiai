# Overview Architettura del Progetto Risparmiai

## 1. Vision del Progetto & Architettura Generale

Il progetto segue un modello ispirato a Clean Architecture con una struttura feature-first: i concetti di business e le regole di dominio sono separati da data access, matcher e presentation layer. In pratica, la logica di dominio vive sotto `lib/savings_checker/domain`, i dati e le integrazioni esterne sotto `lib/savings_checker/data`, mentre la UI e lo stato dell'applicazione stanno sotto `lib/savings_checker/presentation`.

Questa separazione serve a mantenere la responsabilità chiara:

- Domain: entità, repository contracts, servizi di calcolo e regole di business.
- Data: datasource di risorse statiche, client AI, matcher, repository concrete, conversioni JSON.
- Presentation: state notifier, widget, chat UI.
- App bootstrap: in `lib/main.dart` si costruisce l'infrastruttura e il provider.

### Regola d'oro architetturale

L'AI NON deve diventare il motore di business del prodotto. Il suo compito è limitato a:

- classificare il prodotto in base al testo utente;
- estrarre dati grezzi e non elaborati;
- suggerire una categoria se non è determinata;
- ritorno JSON strutturato, coerente e leggibile da Dart.

Tutto ciò che riguarda:

- calcolo del costo unitario,
- confronto tra prodotti,
- benchmark e media,
- validazione matematica,
- persistenza locale,
- logica di business e decisione finale,

deve essere gestito da Dart nel dominio e nei servizi, non dall'AI.

Questo principio è coerente con il codice attuale: `openai_savings_client.dart` si occupa solo di interagire con OpenAI e validare il payload, mentre `SavingsCalculatorService` e `ProductAnalysis` gestiscono il confronto economico e i valori unitari.

---

## 2. Mappa e Analisi File per File

Di seguito la mappatura esatta dei file presenti oggi sotto `lib/` ed `assets/`.

### App bootstrap

#### [lib/main.dart](../lib/main.dart)
- Responsabilità/Ruolo: entry point dell'app Flutter, inizializza `flutter_dotenv`, verifica se è presente la chiave OpenAI e costruisce il provider `SavingsChatNotifier` con `SavingsRepositoryImpl`.
- Interazioni/Dipendenze: dipende da `provider`, `flutter_dotenv`, `SavingsRepositoryImpl`, `SavingsChatNotifier`, `SavingsCheckerPage`.
- Stato/Valutazione: Mantenere. È il punto di composizione dell'app, ma va eventualmente semplificato con una factory di dependency injection più esplicita.

### Data layer: datasource

#### [lib/savings_checker/data/datasources/category_reference_data_source.dart](../lib/savings_checker/data/datasources/category_reference_data_source.dart)
- Responsabilità/Ruolo: carica il dataset locale `default_categories.json` da `rootBundle` e lo converte in `CategoryReferenceModel`.
- Interazioni/Dipendenze: legge `assets/json/default_categories.json`; usa `CategoryReferenceModel`.
- Stato/Valutazione: Mantenere. È un datasource pulito e ben separato. Il nome e la responsabilità sono corretti.

#### [lib/savings_checker/data/datasources/openai_savings_client.dart](../lib/savings_checker/data/datasources/openai_savings_client.dart)
- Responsabilità/Ruolo: wrapper HTTP verso OpenAI Chat Completions; prepara il prompt di sistema; valida il JSON restituito dall'AI e ne rimuove campi business non ammessi.
- Interazioni/Dipendenze: comunica con OpenAI; usato da `SavingsRepositoryImpl`.
- Stato/Valutazione: Mantenere. È un client di integrazione chiaro. Deve restare il più stretto possibile: parse/classificazione, niente business logic.

### Data layer: matcher

#### [lib/savings_checker/data/matchers/category_matcher.dart](../lib/savings_checker/data/matchers/category_matcher.dart)
- Responsabilità/Ruolo: tenta di riconoscere la categoria del prodotto a partire dall'input utente, usando `default_categories.json` come dataset di riferimenti. In caso di non-match, genera una categoria suggerita.
- Interazioni/Dipendenze: usa `CategoryReferenceDataSource`, `CategoryMatchResult`, `SuggestedCategory`.
- Stato/Valutazione: Mantenere. È una componente utile, anche se la logica di suggestion potrebbe essere ulteriormente spostata in un servizio/domain facade se crescerà.

### Data layer: models

#### [lib/savings_checker/data/models/category_match_result.dart](../lib/savings_checker/data/models/category_match_result.dart)
- Responsabilità/Ruolo: payload di output del matcher. Tiene traccia di categoria esatta, suggerimento e input normalizzato.
- Interazioni/Dipendenze: dipende da `CategoryReference` e `SuggestedCategory`.
- Stato/Valutazione: Mantenere, ma la struttura potrebbe essere ridotta se il modello è usato solo come transitory DTO.

#### [lib/savings_checker/data/models/category_reference_model.dart](../lib/savings_checker/data/models/category_reference_model.dart)
- Responsabilità/Ruolo: modello dati dedicato alla conversione JSON del dataset di categorie.
- Interazioni/Dipendenze: estende `CategoryReference` e viene usato dal datasource.
- Stato/Valutazione: Da Ristrutturare. Questo file è quasi duplicato della `domain/entity` e introduce un livello di “model inheritance” che non aggiunge significativo valore rispetto al mapping diretto o a un mapper dedicato.

#### [lib/savings_checker/data/models/product_analysis_model.dart](../lib/savings_checker/data/models/product_analysis_model.dart)
- Responsabilità/Ruolo: normalizza e interpreta un prodotto in formato JSON, includendo inferenza di unità e categoria.
- Interazioni/Dipendenze: estende `ProductAnalysis`; usa `ProductCategory`.
- Stato/Valutazione: Da Ristrutturare / Da Eliminare in parte. In questo file si concentra molta logica di normalizzazione e inferenza che è più sensata in un mapper, service di parsing o factory del dominio. Il fatto che estenda una entity del dominio e faccia calcoli di inferenza è un segnale di design non ancora pulito.

### Data layer: repository

#### [lib/savings_checker/data/repositories/savings_repository_impl.dart](../lib/savings_checker/data/repositories/savings_repository_impl.dart)
- Responsabilità/Ruolo: implementazione concreta del repository. Coordina AI, matcher, dataset locale, normalizzazione, raggruppamento e ritorno di `ProductAnalysis`.
- Interazioni/Dipendenze: usa `OpenAiSavingsClient`, `CategoryMatcher`, `CategoryReferenceDataSource`, `SavingsCalculatorService`, le entity di dominio e i modelli di categoria.
- Stato/Valutazione: Mantenere, ma va ristrutturato. È il punto di orchestrazione più importante, ma oggi contiene troppo codice di normalizzazione e fallback; molti pezzi vanno spostati in mapper/servizi dedicati.

### Domain layer: entities

#### [lib/savings_checker/domain/entities/category_reference.dart](../lib/savings_checker/domain/entities/category_reference.dart)
- Responsabilità/Ruolo: rappresenta il benchmark di categoria di riferimento: chiave, nome visualizzato, unità principale, costo medio e attributi richiesti.
- Interazioni/Dipendenze: usata da `CategoryMatcher`, `CategoryReferenceDataSource`, `SavingsRepositoryImpl`.
- Stato/Valutazione: Mantenere.

#### [lib/savings_checker/domain/entities/product_analysis.dart](../lib/savings_checker/domain/entities/product_analysis.dart)
- Responsabilità/Ruolo: entità centrale del dominio. Rappresenta il prodotto analizzato, il prezzo totale, la quantità totale, l'unità principale e i metadati di attributi.
- Interazioni/Dipendenze: usata in `SavingsCalculatorService`, `SavingsRepositoryImpl`, UI e notifier.
- Stato/Valutazione: Mantenere. È la faccia più chiara del puro dominio.

#### [lib/savings_checker/domain/entities/product_category.dart](../lib/savings_checker/domain/entities/product_category.dart)
- Responsabilità/Ruolo: enum delle categorie supportate.
- Interazioni/Dipendenze: usata in `ProductAnalysis` e in conversioni/normalizzazione dei modelli.
- Stato/Valutazione: Mantenere.

#### [lib/savings_checker/domain/entities/savings_comparison.dart](../lib/savings_checker/domain/entities/savings_comparison.dart)
- Responsabilità/Ruolo: risultato del confronto di convenienza, con media, percentuale di risparmio e messaggio di sintesi.
- Interazioni/Dipendenze: usata da `SavingsCalculatorService`.
- Stato/Valutazione: Mantenere.

#### [lib/savings_checker/domain/entities/suggested_category.dart](../lib/savings_checker/domain/entities/suggested_category.dart)
- Responsabilità/Ruolo: rappresenta una categoria suggerita quando l'input non trova un match esatto.
- Interazioni/Dipendenze: usata da `CategoryMatcher` e dal repository per fornire una proposta.
- Stato/Valutazione: Mantenere.

### Domain layer: repositories

#### [lib/savings_checker/domain/repositories/savings_repository.dart](../lib/savings_checker/domain/repositories/savings_repository.dart)
- Responsabilità/Ruolo: contratto del repository del dominio.
- Interazioni/Dipendenze: implementato da `SavingsRepositoryImpl` e consumato da `SavingsChatNotifier`.
- Stato/Valutazione: Mantenere.

### Domain layer: services

#### [lib/savings_checker/domain/services/savings_calculator_service.dart](../lib/savings_checker/domain/services/savings_calculator_service.dart)
- Responsabilità/Ruolo: esegue il confronto economico, la media e la scelta del miglior prodotto. È il punto in cui il calcolo di business deve essere centralizzato.
- Interazioni/Dipendenze: usa `ProductAnalysis` e `SavingsComparison`.
- Stato/Valutazione: Mantenere. È il punto giusto per la logica di benchmark e risparmio.

### Presentation layer

#### [lib/savings_checker/presentation/models/chat_message.dart](../lib/savings_checker/presentation/models/chat_message.dart)
- Responsabilità/Ruolo: definisce il messaggio di chat per l'interfaccia di analisi.
- Interazioni/Dipendenze: usato da `SavingsChatNotifier`.
- Stato/Valutazione: Mantenere. È minimale e chiaro.

#### [lib/savings_checker/presentation/notifiers/savings_chat_notifier.dart](../lib/savings_checker/presentation/notifiers/savings_chat_notifier.dart)
- Responsabilità/Ruolo: gestisce lo stato della chat e richiama il repository per l'analisi del prompt.
- Interazioni/Dipendenze: usa `SavingsRepository`, `ProductAnalysis`, `ChatMessage`.
- Stato/Valutazione: Mantenere. È un notifier pulito ma la costruzione del summary va tenuta semplice e non troppo “business-aware”.

#### [lib/savings_checker/presentation/pages/savings_checker_page.dart](../lib/savings_checker/presentation/pages/savings_checker_page.dart)
- Responsabilità/Ruolo: UI principale che mostra la chat e gli insight migliori.
- Interazioni/Dipendenze: dipende da `SavingsChatNotifier` e `ProductAnalysis`.
- Stato/Valutazione: Mantenere. È il layer di presentazione dell'app; abbastanza semplice da essere mantenuto.

### Asset dataset locale

#### [assets/json/default_categories.json](../assets/json/default_categories.json)
- Responsabilità/Ruolo: dataset locale read-only di categorie di benchmark, unità di misura e attributi richiesti.
- Interazioni/Dipendenze: letto da `CategoryReferenceDataSource`, usato dal matcher e dal repository per confrontare categorie e benchmark.
- Stato/Valutazione: Mantenere. È il dataset di riferimento corretto e dovrebbe restare read-only.

---

## 3. Integrazione del Flusso Dati (Dataset Locale + AI)

Il flusso di dati oggi è coerente con la visione architetturale:

1. L'utente inserisce un prompt in UI (`SavingsCheckerPage`).
2. Il notifier richiama il repository (`SavingsRepositoryImpl`).
3. Il repository normalizza il prompt e tenta un match con il dataset locale (`default_categories.json`).
4. Se il dataset riconosce la categoria, usa il benchmark e la categoria di riferimento;
5. Se il prompt non è chiaramente riconducibile, il matcher propone una categoria suggerita;
6. L'AI client (`OpenAiSavingsClient`) riceve il prompt e ritorna solo una struttura grezza, come:
   - `category_key`
   - `brand`
   - `total_price`
   - `units_per_package`
   - `sub_units_per_package`
   - `primary_unit_name`
   - `specific_attributes`
7. Il repository converte e normalizza i dati in `ProductAnalysis`.
8. Il dominio calcola o confronta i valori tramite `SavingsCalculatorService`.

### Dataset locale read-only

`default_categories.json` è il dataset di riferimento deterministico. È read-only e va trattato come catalogo di benchmark. Non deve essere modificato dall'AI e non dovrebbe diventare un luogo per calcoli di business.

### `user_custom_categories` (conceptuale)

Nel codice attuale non esiste ancora un file o un datasource dedicato a `user_custom_categories`. Se poi verrà introdotto, deve essere gestito in Dart come un layer di persistenza locale (ad esempio in shared preferences, Hive, Isar o SQLite), non come output dell'AI.

La regola corretta sarebbe:

- `default_categories.json`: dataset standard, read-only, benchmark iniziale.
- `user_custom_categories`: dataset personalizzato, read/write in Dart, prodotto dall'utente o dall'app.
- AI: solo parser/classifier dei dati grezzi, mai fonte di persistenza o di logica di calcolo.

Questo mantiene il flusso: AI produce struttura grezza, Dart valida, normalizza e salva in modo deterministico.

---

## 4. Elenco delle cose da eliminare o semplificare

Sono già emersi alcuni segnali di pulizia necessari prima di proseguire con nuove feature.

### 1) Duplicazioni tra entity e model
- `category_reference.dart` e `category_reference_model.dart` sono quasi ridondanti.
- `product_analysis.dart` e `product_analysis_model.dart` fanno la stessa cosa a livelli diversi: l'entity definisce il dominio, il model aggiunge conversioni JSON e inferenze di business.

Raccomandazione: lasciare solo la domain entity come fonte di verità e spostare il mapping JSON in mapper/factory specifici. Se serve, il model può essere eliminato o ridotto a un DTO puro senza inheritance.

### 2) Logica di normalizzazione/calcolo nei model invece che nel dominio
- In `product_analysis_model.dart` ci sono logiche di:
  - inferenza di unità,
  - normalizzazione di `totalUnitsCount`,
  - parse di category.

Questa logica è molto vicino al dominio e dovrebbe risiedere in una factory/domain mapper, non in un modello che estende la entity.

### 3) Fallback logic e orchestrazione troppo dense in `SavingsRepositoryImpl`
- Il repository oggi coordina molte responsabilità: AI, matcher, normalizzazione, benchmark, fallback, mappatura categoria, summary.

Raccomandazione: separare in:

- un `ProductParserService` o `RawProductMapper`;
- un `CategoryResolverService`;
- un `FallbackProductFactory`;
- un `ProductAnalysisAssembler`.

Questo rende la repository più leggera e aderente a Clean Architecture.

### 4) File non più necessari o da rivalutare
- `category_match_result.dart` è funzionale ma potrebbe essere sostituito da una semplice tupla/record oppure da un risultato interno del matcher, a seconda della complessità futura.
- `suggested_category.dart` è utile ma andrà mantenuto solo se il processo di suggestion resta centrale nella UX.
- `chat_message.dart` è semplice, non è ridondante ma va valutato con l'evoluzione della UI.

### 5) Principio da tenere sempre fermo
- AI: parsing e classificazione.
- Dart: persistenza, validazione, benchmark, confronto, calcoli, decisioni.

Se un file inizia a contenere logica di business o di convenienza economica, è un campanello d'allarme: è il segno che quel codice va spostato nel dominio o nel service layer.

---

## Conclusione

La struttura attuale è già vicino a una buona architettura Clean + feature-first, ma ci sono alcuni punti di debolezza tipici della fase iniziale del progetto: duplicazioni fra entity e model, logica di normalizzazione spostata troppo in basso e repository che fa troppo. La pulizia da fare non è di tipo “riprogettazione”, ma di riordino funzionale: separare il parsing AI dal calcolo business, ridurre i DTO duplicati e lasciare il dominio come unica fonte di verità.

Le azioni più urgenti da intraprendere prima di proseguire sono:

1. eliminare o ridurre i model duplicati;
2. spostare la trasformazione di `ProductAnalysisModel` in un mapper/assembler;
3. mantenere `default_categories.json` come dataset read-only;
4. introduzione futura di `user_custom_categories` solo in Dart persistenza locale;
5. tenere OpenAI fuori dalla logica di benchmarking e convenienza.
