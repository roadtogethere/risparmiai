# Architettura di Risparmiai

Stato: M5B.3. Riferimenti normativi: [principi](SAVINGS_CHECKER_PRINCIPLES.md) e [contratto del planner](M4A_PLANNER_CONTRACT.md).

## Responsabilità

Il progetto Flutter segue una struttura feature-first ispirata alla Clean Architecture:

- `domain`: entità, contratti, validazione delle quantità e calcoli economici.
- `data`: client AI, parser JSON, repository e persistenza locale.
- `presentation`: notifier, chat, card e pagine archivio.
- `lib/main.dart`: selezione del provider e composizione delle dipendenze.

L'AI interpreta il linguaggio, raccoglie fatti, propone operazioni e richiede informazioni mancanti. Dart valida fatti e provenienza, risolve le quantità, calcola il costo e confronta osservazioni verificate. L'AI non è autorità per calcoli, convenienza o persistenza.

## Percorso live OpenAI/Gemini

1. `SavingsCheckerPage` invia il testo a `SavingsChatNotifier`.
2. Il notifier usa `QuantityPlannerRepositoryImpl`, passando l'analisi precedente per continuazioni e correzioni.
3. Il repository carica il catalogo attraverso `CategoryReferenceStore` e chiama `OpenAiSavingsClient` o `GeminiSavingsClient` con il contratto M4A e il contesto conversazionale.
4. `QuantityPlanParser` valida il JSON `status/category/facts/operation/missing/question`. I fatti numerici conservano unità e provenienza; non sono istruzioni di scrittura.
5. `ComparableQuantityResolver` esegue in Dart `direct`, `convert` o `multiply`, rispettando metrica canonica, schema e provenienza. Un'analisi incompleta conserva i fatti senza produrre un costo salvabile.
6. `ComparablePrice.fromAnalysis` ricontrolla la quantità e calcola `totalPrice / quantity`, senza arrotondare il valore interno.
7. `PriceComparisonService` confronta il costo con le osservazioni già presenti in `VerifiedPriceStore`, per categoria/metrica. Nessuno storico significa convenienza non valutabile; l'osservazione corrente non è inclusa.
8. Soltanto **Salva questo prezzo** chiama `saveCurrentPrice`: il salvataggio è idempotente per identità/revisione. Non registra acquisti. Il prezzo zero non è salvabile.

Una correzione mantiene l'identità corrente e aggiorna la revisione. Le osservazioni già salvate sono immutabili: salvare una revisione successiva richiede un'altra azione esplicita. **Nuova analisi** azzera il contesto corrente e lo stato di salvataggio, conservando i prezzi persistiti.

## Errori e recupero

I provider hanno un timeout configurabile, inizialmente 30 secondi per tentativo. Il timeout del Future non garantisce la cancellazione fisica della richiesta HTTP. La politica M5B.2 consente al massimo un retry automatico per HTTP 429 e 500/502/503/504, entro un budget complessivo HTTP di 30 secondi che include tentativi e attesa. `Retry-After` viene rispettato se l'attesa rientra nel budget; altrimenti viene restituito l'errore senza anticipare il retry. Il retry manuale tramite **Riprova** resta disponibile.

`SavingsFailure` distingue gli errori. Il notifier conserva il testo esatto e il contesto del turno fallito: **Riprova** reinvia quel tentativo, senza aggiungere il testo “Riprova” ai fatti o duplicare il messaggio utente. Identità/generazione proteggono dalle risposte tardive dopo reset. Le risposte non valide non sostituiscono l'ultima analisi valida.

I log diagnostici riportano soltanto informazioni tecniche di configurazione/percorso, non prompt, risposte grezze o valori delle chiavi API.

## Presentazione M5B.3

I messaggi del planner mantengono gruppo di analisi e richiesta nella sessione; dopo una risposta elaborata riportano anche identità e revisione del planner. Gli errori conservano il riferimento al contesto precedente senza diventare revisioni elaborate. Le card riportano analisi/revisione e, dopo un fallimento, distinguono esplicitamente i fatti precedenti dalla richiesta fallita. Questi metadati non modificano la persistenza economica.

Il default `tabs_count` usa la label `Numero di pastiglie`, conservando chiave e metrica `tablet`. Le categorie custom persistite continuano a prevalere: eventuali label legacy come `Tabs count` restano invariate, senza migrazioni o sovrascritture. `primary_unit` è solo presentazione; il prompt richiede la metrica canonica esatta negli operandi `direct`, senza alias nel resolver.

`RecognizedFacts` mostra categoria, prezzo, fatti quantitativi e descrittivi. Riusa le label dello schema e separa visivamente parole di chiavi sconosciute; non riconosce prodotti e non inventa attributi. Il contratto live attuale non contiene un nome prodotto o una marca strutturati, quindi non li ricava dal testo libero.

`PriceResultCard` separa costo comparabile, confronto con lo storico personale e salvataggio. `AnalysisDisplay` applica solo formattazione italiana: ad esempio `0,000833 €/strappo`, accompagnato da `Circa 0,83 € ogni 1.000 strappi`. L'equivalente è limitato a unità conteggiabili note e non entra nei calcoli o nella persistenza; unità fisiche o sconosciute mantengono la scala originale.

Chat e card condividono lo scorrimento, con input e azione **Nuova analisi** esterni alla lista. Un separatore indica l'inizio di ogni nuovo prodotto nella sessione della pagina. Le correzioni mostrano **Dati aggiornati** e un suggerimento spiega come correggere in chat.

## Catalogo e storico

- `assets/json/default_categories.json`: catalogo statico, read-only. Gli aggregati eventualmente presenti non sono osservazioni economiche verificate.
- `CategoryReferenceStore`: catalogo effettivo e schemi personalizzati in `user_custom_categories`, gestiti da Dart con le regole M3.
- `VerifiedPriceStore`: osservazioni verificate separate in `verified_price_observations_v1`, con fatti/schema, identità/revisione, quantità, costo non arrotondato e data.
- `VerifiedPricesPage`: prezzi salvati esplicitamente e usati nei confronti.
- `ArchivePage`: aggregati precedenti non verificati, esclusi dai confronti live. M5B.3 corregge i testi, senza migrare o modificare dati.

## Percorso legacy e demo, separato

`SavingsRepositoryImpl`, `ProductAnalysisModel`, `ProductAnalysis`, `CategoryMatcher` e `SavingsCalculatorService` appartengono al percorso precedente. Restano disponibili per compatibilità e test; non costituiscono il percorso live del planner M4A.

Con `AI_PROVIDER=mock`, `MainApp` non inietta il planner e usa il repository demo. La pagina mostra sempre **Modalità demo — dati simulati**. Il comportamento dei dati simulati rimane invariato; i nomi eventualmente presenti nei `ProductAnalysis` sono visualizzati dalla card legacy. Un errore di configurazione live non attiva implicitamente la demo.

## Verifiche

`test/conversational_ux_test.dart` copre fatti/label, correzioni, reset tra prodotti della stessa categoria, conservazione dei prezzi salvati, demo, costi piccoli e layout mobile con testo ingrandito e tastiera simulata. Le suite M1.5–M5B.2 restano responsabili delle regressioni di dominio, provenienza, storico, timeout e retry. I test live dei provider restano opt-in e richiedono autorizzazione e configurazione dedicate.

Le prove widget non sostituiscono il controllo su dispositivo reale di tastiera, scorrimento, lettore di schermo e leggibilità durante la spesa.
