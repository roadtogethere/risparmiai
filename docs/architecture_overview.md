# Architettura di Risparmiai

## Informativa privacy

`lib/privacy/` separa il contratto `PrivacyRepository` nel domain, il caricamento
degli asset e SharedPreferences in data, e le schermate in presentation.
`PrivacyNoticeGate` mostra un riepilogo al primo avvio e quando cambia
`privacyNoticeVersion`. La chiave `privacy.viewed_notice_version` registra solo
la presa visione, mai il consenso pubblicitario. Un errore di lettura ripropone
il riepilogo; un errore di scrittura permette di riprovare senza avviare AdMob.
`main.dart` inietta il repository e collega l'avvio AdMob al callback del gate,
dopo il frame della pagina principale. La chat non e montata prima di proseguire.
I test possono omettere il repository; l'entry point reale lo fornisce sempre.

L'icona privacy nella chat riapre `PrivacyPolicyPage`. I testi IT/EN in
`assets/privacy_policy/` vengono caricati offline e renderizzati come Markdown;
i link HTTPS/email si aprono soltanto su azione dell'utente. La lingua iniziale
segue le lingue supportate IT/EN, con selezione manuale nel documento completo.
L'informativa descrive dati locali, API OpenAI/Gemini e AdMob/UMP. Non dichiara
che AdMob sia l'unico destinatario o che i dati locali siano cifrati dall'app.
Il contatto email e confermato; l'identita del titolare e ancora da completare
prima della pubblicazione, per scelta dell'autore di non inserirla in questa fase.
Incrementare la versione nel domain e nei documenti quando cambia l'informativa.

## Integrazione pubblicitaria

`lib/advertising/` mantiene separati domain, data e presentation dal dominio economico.
Il domain contiene soltanto il contratto interstitial e la politica: 5 nuovi
salvataggi e almeno 2 minuti fra annunci. Data integra Google Mobile Ads,
consenso UMP, ID demo ufficiali e contatori in `advertising.interstitial.v1`;
riusa SharedPreferences senza accedere allo storico prezzi o al planner.
Presentation possiede il banner e coordina gli interstitial dopo un salvataggio.
`saveCurrentPrice()` restituisce true soltanto per una nuova osservazione persistita.
Errori e duplicati non generano opportunita pubblicitarie. Gli annunci non pronti
vengono saltati; non compaiono successivamente durante un'altra interazione.
Il coordinatore controlla pagina corrente e app in primo piano prima di mostrare.
Il banner compare soltanto in fondo alla pagina Prezzi salvati, fuori dall'elenco.

`main.dart` inietta il servizio concreto; MainApp permette di ometterlo nei test.
L'inizializzazione SDK e il consenso partono dopo la presa visione dell'informativa,
senza bloccare l'avvio dell'app. Le preferenze privacy sono accessibili quando UMP
le richiede. In assenza di consenso valido o in caso di errore l'app resta usabile
senza annunci. Le piattaforme diverse da Android/iOS non inizializzano l'SDK.

Configurazione attuale: annunci di test in debug/profile, Android minimo API 24.
In release si usano le quattro costanti production in `advertising/data/admob_ids.dart`;
se manca uno dei due ID della piattaforma, gli annunci restano disattivati.
Per la produzione compilare queste costanti e sostituire l'app ID nel
manifest Android e GADApplicationIdentifier in Info.plist, e configurare i messaggi
privacy nel proprio account AdMob. Non inserire ID pubblicitari nel planner o in .env.
Rigenerare e verificare l'app su dispositivo; i test Dart non verificano le UI native
di consenso o la consegna degli annunci.

Riferimenti: [integrazione SDK](https://developers.google.com/admob/flutter/quick-start),
[consenso UMP](https://developers.google.com/admob/flutter/privacy),
[annunci di test](https://developers.google.com/admob/flutter/test-ads).

Stato: M5B.3 con estensione quantità M4C. Riferimenti normativi: [principi](SAVINGS_CHECKER_PRINCIPLES.md) e [contratto del planner](M4A_PLANNER_CONTRACT.md).

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

Una correzione mantiene l'identità corrente e aggiorna la revisione. Le osservazioni già salvate sono immutabili: salvare una revisione successiva richiede un'altra azione esplicita. Il planner propone `continue`, `correct`, `new_product` o `clarify` nella stessa risposta JSON. Dart assegna un nuovo ID e isola i fatti per `new_product`, anche nella stessa categoria; `clarify` chiede conferma senza cambiare l'analisi corrente. **Nuova analisi** resta disponibile e azzera il contesto corrente e lo stato di salvataggio, conservando i prezzi persistiti.

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
