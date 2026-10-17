# TODO di Risparmiai

Aggiornato il 17 ottobre 2026. Riferimento verificato: HEAD `ae37a83`.
Questo documento raccoglie attività future: non descrive funzionalità già disponibili.
I requisiti e i criteri sotto sono da implementare e verificare.

Riferimenti: [principi del prodotto](SAVINGS_CHECKER_PRINCIPLES.md),
[architettura corrente](architecture_overview.md) e
[contratto del planner ed estensioni M4B](M4A_PLANNER_CONTRACT.md).

## TODO 1 — Proxy AI e monitoraggio dei costi

**Priorità:** alta — prima della distribuzione beta agli amici.

**Stato:** TODO / NON IMPLEMENTATO.

### Obiettivo

Introdurre un proxy backend leggero fra Flutter e le API OpenAI, mantenendo
l'architettura AI-first: l'AI interpreta i prodotti, Dart valida i dati e svolge
i calcoli economici. La gestione di accessi e consumi non appartiene al dominio
economico né al contratto JSON del planner.

### Requisiti

- Conservare la chiave OpenAI esclusivamente sul backend, mai nell'APK,
  negli asset o nelle configurazioni distribuite con l'app.
- Mantenere compatibilità con `AiSavingsClient` e il contratto del planner,
  rispettando la separazione `domain/data/presentation` e la composizione
  delle dipendenze in `main.dart`.
- Applicare rate limiting e quote per installazione o codice d'invito,
  senza richiedere necessariamente un login.
- Introdurre un budget globale che blocchi nuove richieste al raggiungimento
  del limite; definire come gestire richieste concorrenti e consumi ancora in corso.
- Registrare numero di chiamate, modello, token di input/output, eventuali token
  di ragionamento, costo stimato, latenza ed errori. Distinguere la richiesta
  logica dai tentativi effettivi verso il provider.
- Non conservare di default testi delle conversazioni o dati dei prodotti;
  evitare che finiscano nei log applicativi o di hosting.
- Configurare il modello lato server; non permettere al client di scegliere
  arbitrariamente modelli o parametri che aggirino i limiti di consumo.
- Valutare protezioni contro abusi, codici condivisi e identificatori falsificati:
  un identificatore dichiarato dal client non dimostra l'identità dell'installazione.
- Considerare i consumi aggiuntivi dei retry, anche dopo timeout o conferme perse;
  coordinare retry del client e del proxy per evitare tentativi moltiplicati.
- Consentire una consultazione minima delle statistiche, per esempio tramite
  report o endpoint amministrativo protetto, senza una dashboard complessa iniziale.

### Dipendenze e verifiche preliminari

- Coordinare le metriche e il calcolatore dei costi con
  [AI Cost Optimization — Prompt Caching & Usage Metrics](#todo-3--ai-cost-optimization--prompt-caching--usage-metrics).
  Le metriche raccolte saranno successivamente utilizzate dal proxy per budget,
  quote e monitoraggio server-side; i controlli del proxy dovranno basarsi su dati
  verificati lato server, senza fidarsi di conteggi dichiarati dall'app.
- Prima dell'implementazione, audit di `OpenAiSavingsClient`, costruzione dei
  payload, gestione della chiave, errori, timeout e retry; includere il trasporto
  HTTP condiviso e il bootstrap delle dipendenze.
- Valutazione dell'hosting: costi, gestione dei segreti, persistenza dei contatori,
  concorrenza, limiti, log, operatività e protezione dell'accesso amministrativo.
- Definizione delle quote, del budget, del periodo di riferimento, della stima dei
  costi e del comportamento quando l'usage del provider non è disponibile.
- Valutazione dell'impatto su informativa privacy e configurazione di distribuzione.
  Il perimetro iniziale riguarda OpenAI; un eventuale proxy Gemini va valutato
  esplicitamente, senza considerarlo già incluso o implementato.

### Criteri di completamento

- Audit e scelta dell'hosting documentati; chiave esclusivamente sul backend
  e assente dall'artefatto distribuito.
- Analisi e continuazioni del planner funzionanti tramite un client compatibile
  con `AiSavingsClient`, senza cambiare il contratto o spostare i calcoli economici.
- Verifiche di rate limit, quote, budget globale, concorrenza e tentativi di aggiramento;
  nessuna nuova richiesta ammessa dopo il limite secondo la politica definita.
- Retry, errori e timeout coperti da verifiche, con conteggio dei tentativi e
  stima dei consumi aggiuntivi, senza promettere che un timeout annulli il costo remoto.
- Statistiche consultabili in modo protetto con tutte le metriche previste;
  verificata l'assenza di prompt e dati prodotto nei log predefiniti.

## TODO 2 — Modifica dei prezzi salvati

**Priorità:** media.

**Stato:** TODO / NON IMPLEMENTATO.

### Obiettivo

Consentire la correzione esplicita di un'osservazione economica già salvata
nell'Archivio, nella vista **Prezzi salvati** (`VerifiedPricesPage`).
Non si tratta dell'archivio degli aggregati legacy (`ArchivePage`).
L'eliminazione con annullamento è già implementata e non deve essere rifatta.

### Requisiti

- Consentire la modifica del prezzo totale.
- Valutare la modifica della quantità comparabile e degli attributi originali,
  se effettivamente disponibili e rivalidabili; non inventare fatti mancanti.
- Ricalcolare il costo unitario esclusivamente tramite Dart, dai fatti validati,
  senza usare risultati economici forniti dall'AI o valori arrotondati della UI.
- Conservare l'identificatore dell'osservazione senza creare duplicati;
  definire il rapporto fra identità e revisione prima di cambiare la persistenza.
- Aggiornare minimo, media e conteggio dalle osservazioni risultanti, anche nei
  confronti già visualizzati. Una modifica non aumenta il numero di osservazioni
  e l'osservazione corrente non deve diventare il proprio riferimento.
- Mantenere categoria e metrica canonica immutabili durante la modifica,
  rispettando l'autorità dello schema locale.
- Validare prezzo, quantità, attributi, operazione, unità e provenienza prima
  della scrittura, riusando le regole di dominio applicabili.
- Evitare aggiornamenti parziali e perdita di dati in caso di errore;
  coordinare la modifica con save, delete e restore esistenti.
- Non modificare gli aggregati legacy e mantenere il principio **analisi ≠ acquisto**.
- Rispettare `domain/data/presentation`: regole e contratti nel domain,
  persistenza in data, editor e gestione dello stato UI in presentation.

### Dipendenze e verifiche preliminari

- Prima dell'implementazione, verificare quali fatti originali siano effettivamente
  conservati nello storico M4B, compresi schema, operazione, provenienza e identità;
  distinguere dati persistiti, ricostruibili e disponibili soltanto nella sessione.
- Esaminare `VerifiedPriceHistory`, `VerifiedPriceStore`,
  `ComparablePrice.fromAnalysis`, `ComparableQuantityResolver` e
  `PriceComparisonService`, riusando le astrazioni esistenti.
- Definire compatibilità con l'attuale immutabilità del contenuto delle revisioni
  salvate, gestione della data e necessità di eventuali modifiche al formato storico.
  La correzione conversazionale del planner oggi non modifica un record già salvato.

### Criteri di completamento

- Fatti persistiti verificati e perimetro dell'editor documentato; eventuali campi
  non ricostruibili non vengono stimati o resi modificabili senza validazione.
- Correzione del prezzo totale persistita dopo riavvio sulla stessa osservazione,
  senza duplicati e con categoria e metrica invariate.
- Costo unitario ricalcolato in Dart; minimo, media e conteggio aggiornati
  correttamente, anche modificando l'unica osservazione o il minimo precedente.
- Verifiche per valori non validi, salvataggio fallito, retry e operazioni concorrenti:
  in caso di errore i dati precedenti restano recuperabili senza aggiornamenti parziali.
- Verificate compatibilità con eliminazione/annullamento, esclusione degli aggregati
  legacy e assenza di scritture economiche implicite da analisi o risposte AI.

Questa attività resta indipendente dall'ottimizzazione dei costi AI descritta
nel TODO 3 e non ne richiede il completamento.

## TODO 3 — AI Cost Optimization — Prompt Caching & Usage Metrics

**Priorità:** alta — prima della beta pubblica.

**Stato:** TODO / NON IMPLEMENTATO.

### Obiettivo

Ridurre e misurare i costi delle richieste a OpenAI GPT-6 Luna senza modificare
il comportamento funzionale del planner. Questa attività approfondisce il formato
del prefisso e la misurazione dei consumi; il
[TODO 1 — Proxy AI e monitoraggio dei costi](#todo-1--proxy-ai-e-monitoraggio-dei-costi)
mantiene la responsabilità di segreti, protezioni e limiti server-side.

### Requisiti

1. Stabilizzare l'ordine delle categorie e la serializzazione del catalogo inviato
   all'AI, mantenendo la precedenza autoritativa degli schemi locali.
2. Spostare il catalogo prima dei contenuti conversazionali variabili per favorire
   il prompt caching, senza cambiare contenuti, contratto o regole del planner.
3. Rilevare `prompt_tokens`, `cached_tokens`, `completion_tokens` ed eventuali
   `reasoning_tokens` dai campi dell'endpoint utilizzato. Distinguere input normale
   e cached input; evitare di conteggiare due volte i token di ragionamento già
   inclusi nel totale di output. Segnalare metriche mancanti senza inventare valori.
4. Registrare modello effettivo, latenza, numero di tentativi e risultato della
   richiesta, senza conservare conversazioni o dati dei prodotti. Distinguere
   richieste logiche, tentativi verso il provider e analisi completa su più turni.
5. Preparare un calcolatore di costo stimato con tariffe configurabili per modello,
   input normale, cached input e output, senza prezzi hardcoded; includere i retry
   e rendere espliciti eventuali consumi non misurabili.
6. Verificare tramite chiamate reali cache hit rate e costo medio per analisi
   completa, confrontando una baseline con il prefisso ottimizzato. Le chiamate
   reali fanno parte della futura implementazione, non di questo aggiornamento.
7. Garantire compatibilità con continuazioni, correzioni, retry e categorie
   open-world; stabilizzare la rappresentazione senza eliminare contesto necessario
   o alterare l'autorità del catalogo.
8. Non modificare matematica Dart, storico o salvataggio dei prezzi; rispettare
   la separazione `domain/data/presentation` e il contratto `AiSavingsClient`.

### Dipendenze e verifiche preliminari

- Riprendere l'audit locale del percorso OpenAI e verificare endpoint, modello,
  composizione dei messaggi e ordine del catalogo prima di apportare modifiche.
- Verificare documentazione e tariffe applicabili a GPT-6 Luna, supporto del caching,
  campi usage e condizioni delle misure; non assumere un cache hit garantito.
- Concordare con il TODO 1 un formato di metriche e un calcolo dei costi riutilizzabili:
  il proxy userà successivamente queste metriche per budget, quote e monitoraggio
  server-side, senza duplicare sistemi di contabilizzazione o log sensibili.
- Definire casi riproducibili, credenziali di test e un budget per le future chiamate
  reali, usando contenuti di prova senza dati personali o prodotti degli utenti.
- Nessuna dipendenza dal TODO 2 «Modifica dei prezzi salvati»: le due attività
  rimangono separate e possono procedere indipendentemente.

### Criteri di completamento

- Catalogo serializzato in modo stabile a parità di contenuto e prefisso stabile
  prima dei dati conversazionali variabili, senza regressioni funzionali del planner.
- Metriche previste rilevate e consultabili, distinguendo dati mancanti, modello
  effettivo, tentativi e analisi completa; nessun testo di conversazione o dato
  prodotto nei log delle metriche.
- Calcolatore verificato con tariffe configurabili e casi di input normale,
  cached input, output, ragionamento e retry, senza doppi conteggi.
- Misure reali documentate di cache hit rate e costo medio per analisi completa,
  con baseline, condizioni di prova e limiti della stima; nessun risparmio dichiarato
  sulla sola base della disposizione del prompt.
- Verificate continuazioni, correzioni, retry e categorie nuove; matematica Dart,
  storico e salvataggio invariati. Riutilizzo delle metriche da parte del futuro
  proxy documentato, senza segnare il TODO 1 come implementato.
