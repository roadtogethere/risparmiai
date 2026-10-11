# M4A — Planner e quantità comparabile

Questo documento descrive M4A e, nella sezione finale, le estensioni M4B.
I limiti storici di M4A sulla sola quantità sono superati dal percorso M4B
descritto sotto; il contratto AI rimane invariato.

## Percorso attivo

`MainApp` collega i provider reali a `QuantityPlannerRepositoryImpl` tramite
`SavingsChatNotifier.planner`. Il percorso è:

```text
turni utente → AI → QuantityPlanParser → schema locale
→ ComparableQuantityResolver → PlannerAnalysis → chat
```

La modalità mock esplicita e i consumatori del vecchio contratto continuano a
usare `SavingsRepositoryImpl`. Non esiste fallback dal planner al protocollo
legacy. OpenAI e Gemini usano lo stesso prompt e parser M4A nelle chiamate live.

## Contratto effettivo

Sono ammessi soltanto `status`, `category`, `facts`, `operation`, `missing` e
`question`. `missing` e `question` sono facoltativi. `operation` è obbligatorio,
ma può essere null quando il piano non è ancora determinabile.

Ogni fatto richiede un valore JSON numerico, un codice unità e `source`.
`per` rappresenta una relazione quantitativa. Le origini rappresentabili sono
`user_input`, `user_confirmation`, `ai_suggestion`, `external_lookup`.
Solo le prime due sono utilizzabili dal resolver. `user_confirmation` non è
accettato nel primo turno. Non è implementato alcun lookup.

Le fonti sono dichiarazioni del planner: il validatore non prova da solo che
l'interpretazione del testo sia vera. Il prompt vieta di attribuire all'utente
valori dedotti dalla conoscenza del modello. Le proposte marcate come tali
richiedono informazioni/conferma e non diventano automaticamente fatti fidati.

### DIRECT

```json
{
  "status": "sufficient",
  "category": {"key": "dishwasher_tabs"},
  "facts": {
    "price": {"value": 12, "unit": "EUR", "source": "user_input"},
    "tablet_count": {"value": 85, "unit": "tablet", "source": "user_input"}
  },
  "operation": {"type": "direct", "operand": "tablet_count"}
}
```

Il default `dishwasher_tabs` usa ora `tablet`/`pastiglia`. Una categoria custom
già salvata con `capsule` prevale ancora sul default: nessuna migrazione o
equivalenza implicita capsule/tablet. Il planner deve rispettare quel catalogo.

### MULTIPLY

```json
{
  "status": "sufficient",
  "category": {"key": "toilet_paper"},
  "facts": {
    "price": {"value": 5, "unit": "EUR", "source": "user_input"},
    "rolls_count": {"value": 12, "unit": "roll", "source": "user_input"},
    "sheets_per_roll": {"value": 200, "unit": "sheet", "per": "roll", "source": "user_input"}
  },
  "operation": {"type": "multiply", "operands": ["rolls_count", "sheets_per_roll"]}
}
```

Il resolver richiede esattamente due riferimenti distinti e verifica
`roll × sheet/roll = sheet` prima di produrre `2400 sheet`. Non moltiplica
arbitrariamente due numeri, non usa il prezzo come operando e non contiene
rami per categoria.

### NEEDS_INFORMATION

```json
{
  "status": "needs_information",
  "category": {"key": "toilet_paper"},
  "facts": {
    "price": {"value": 5, "unit": "EUR", "source": "user_input"},
    "rolls_count": {"value": 12, "unit": "roll", "source": "user_input"}
  },
  "operation": {"type": "multiply", "operands": ["rolls_count", "sheets_per_roll"]},
  "missing": ["sheets_per_roll"],
  "question": "Quanti strappi contiene ciascun rotolo?"
}
```

Il notifier conserva l'analisi incompleta. Il turno `500` è inviato al planner
con i turni precedenti, i fatti, l'operazione e la domanda. Il nuovo piano viene
validato, i fatti precedenti omessi sono conservati e l'identità resta locale.
La categoria non può cambiare implicitamente nel completamento. Il pulsante
"Nuova analisi" abbandona esplicitamente il contesto corrente. Il doppio invio
durante una richiesta è bloccato. Anche dopo un risultato calcolabile, il
contesto rimane disponibile per correzioni: il nuovo valore della stessa chiave
sostituisce quello precedente e la quantità viene rivalidata e ricalcolata.
Per un prodotto diverso si usa "Nuova analisi", senza euristiche Dart sul testo.

Il prompt richiede tutti i fatti numerici dichiarati, non soltanto gli operandi:
prezzo e caratteristiche descrittive come il numero di veli devono restare in
`facts` anche durante `needs_information`. I fatti omessi in un turno successivo
restano disponibili dal turno precedente. Con `operation: null`, il resolver
mantiene anche le chiavi `missing` dichiarate dal planner, oltre ai requisiti
deterministici come il prezzo. Non ricostruisce dal linguaggio naturale un fatto
che il planner non ha mai estratto; i turni originali restano nel contesto AI.

### CONVERT e categorie nuove

`{"type":"convert","operand":"volume"}` usa esclusivamente il registro
Dart milliliter/liter e gram/kilogram. Il target viene dallo schema. Fattori
forniti dall'AI sono rifiutati.

Per categorie sconosciute `category.proposal` deve contenere:

```json
{
  "display_name": "Acqua",
  "canonical_metric": "liter",
  "primary_unit": "litro",
  "required_attributes": []
}
```

Lo schema viene validato con M3 e mantenuto in memoria per la sessione del
repository. Gli schemi salvati su disco restano autoritativi. Le nuove proposte
non vengono ancora persistite: il riavvio perde questi schemi e le conversazioni.

## Invarianti

- `sufficient` non autorizza il calcolo: Dart ricontrolla dati e piano.
- `needs_information` non produce quantità, anche se i fatti sembrano completi.
- Prezzo assente richiede informazioni; prezzo zero è valido e distinto.
- Valori non finiti, quantità non positive e overflow/underflow sono rifiutati.
- Campi business, risultati precalcolati e campi del vecchio protocollo non
  sono ammessi come campi aggiuntivi del contratto.
- La metrica finale deve coincidere con quella locale; una metrica legacy null
  non viene ricostruita da etichette o proposte AI.
- Gli operandi definiscono i dati richiesti dalla singola via. DIRECT può usare
  `6000 sheet` senza attributi della ricetta. La validazione M3 del percorso
  legacy resta invariata.

## Compatibilità e scope M4B

`ProductAnalysisModel` è un adapter legacy, usato dai test esistenti. I suoi
fallback e normalizzatori non partecipano al planner. Il vecchio parser e il
vecchio repository restano separati per compatibilità/demo.

M4A espone solo la quantità comparabile, senza card di convenienza. Controlla
numericamente anche la divisione prezzo/quantità per conservare le protezioni
M1.5, ma non espone ancora un nuovo contratto definitivo del costo.

Il repository M4A legge lo store ma non effettua scritture, né con risultati
incompleti né completi. Non registra quindi due volte un completamento. Non
introduce garanzie di idempotenza di una futura persistenza M4B.

Restano a M4B il costo definitivo, lo snapshot precedente, il confronto,
l'atomicità/idempotenza della registrazione e la politica per gli aggregati
legacy e M3 senza provenienza del calcolo. Il problema dell'autoriferimento
del vecchio riepilogo non è risolto da questa milestone.

## Verifica

`test/quantity_planner_test.dart` copre A–G, completamento conversazionale e UI,
schema locale/sessione, assenza di scritture, provenienza, conversioni,
dimensioni, numeri invalidi e rifiuto di campi autoritativi AI. Le risposte AI
sono simulate: questi test provano parser, resolver e integrazione, non la
precisione semantica di un modello remoto su input naturali.

`test/live_planner_test.dart` è opt-in (`RUN_LIVE_PLANNER=1`) e usa i client
reali, con credenziali locali da ambiente o `.env`. Verifica il dialogo
"carta igienica 12 rotolo 5 euro 3 veli" → "500" → correzione del prezzo,
conservando tutti i fatti e senza scritture economiche. I provider privi di
credenziali vengono saltati; nessuna credenziale o risposta grezza viene stampata.

## Estensione M4B — costo, confronto e salvataggio esplicito

Il notifier costruisce `ComparablePrice` dalla quantità rivalidata in Dart.
Il costo è `totalPrice / quantity`, mantenuto come double non arrotondato;
soltanto la presentazione formatta i numeri. Il prezzo zero resta analizzabile
ma non salvabile. Prezzo e operandi devono avere provenienza ammessa da M4A.

`PriceComparisonService` usa uno snapshot dei soli prezzi salvati in
`verified_price_observations_v1`, con stessa categoria e metrica. Gli aggregati
legacy e M3 non partecipano e non vengono migrati. La prima analisi ha costo
disponibile e giudizio assente. Il confronto distingue nuovo minimo potenziale,
pareggio col minimo, prezzo sotto/pari/sopra la media. Le differenze sono
`corrente - riferimento`, quelle percentuali dividono per il riferimento
positivo. Si usano valori interni, senza soglie commerciali o arrotondamenti
per decidere il pareggio. La media dà lo stesso peso a ogni osservazione.
Percentuali non rappresentabili come double finito restano indisponibili.

Solo «Salva questo prezzo» chiama lo store. Il risultato e lo snapshot
precedente rimangono visibili dopo il salvataggio, senza autoriferimento.
Il pulsante non registra acquisti. I prezzi si consultano nella nuova vista
«Prezzi salvati»; l'archivio precedente resta separato e accessibile.

L'identità locale usa 128 bit casuali e ogni turno incrementa una revisione.
Prima del salvataggio le correzioni non scrivono dati. Dopo il salvataggio
producono una revisione non salvata della stessa analisi: il record precedente
rimane immutato. L'utente può salvare la nuova osservazione esplicitamente.
Una revisione ripetuta è idempotente; stessa analisi, prezzo, quantità, categoria
e metrica già salvati non generano un duplicato nemmeno con revisione diversa.
Queste ripetizioni sono escluse anche dal proprio confronto. Una nuova analisi
può invece registrare deliberatamente un'altra osservazione dello stesso prezzo.

Lo store salva schema, fatti, operazione e risultato in un unico documento
SharedPreferences. Le scritture sono serializzate fra istanze nello stesso
isolate; rilettura da disco, controllo schema e deduplicazione avvengono nella
coda. Ogni lettura rivalida fatti e calcolo, senza fidarsi di un costo serializzato.
Errori o dati corrotti non azzerano l'archivio; un retry non duplica una scrittura
la cui conferma sia andata persa. Non è una transazione multiprocesso né una
garanzia di durabilità in caso di crash fornita da un database.

Gli schemi allegati alle osservazioni esplicitamente salvate vengono riutilizzati
anche dopo il riavvio; l'autorità del catalogo locale resta invariata.
Il percorso legacy/demo e i suoi aggregati non sono stati modificati.

Copertura: `price_history_test.dart` per matematica, snapshot, provenienza,
correzioni e UI; `verified_price_persistence_test.dart` per scritture fallite,
cache e conferme perse. I test live AI restano opt-in.

## M5B.1 — timeout e recupero manuale del turno

OpenAI e Gemini accettano `requestTimeout`, inizialmente 30 secondi per
tentativo HTTP, comprensivo della lettura del corpo della risposta. Non è un
timeout globale delle letture locali del repository. Un `TimeoutException`
produce in chat: «Il servizio sta impiegando troppo tempo a rispondere.
Puoi riprovare.» Il caricamento viene liberato; non esistono retry automatici.

Ogni tentativo possiede un client HTTP dedicato, creato tramite una factory
iniettabile e chiuso in `finally`, anche al timeout. Le implementazioni IO e
browser della dipendenza `http` già presente consentono il rilascio/aborto del
trasporto tramite `close()`. Il solo timeout di un Future non interrompe
fisicamente la richiesta sottostante; neppure la chiusura del client garantisce
che il provider interrompa l'elaborazione sul server. Client alternativi possono
ignorare la chiusura: la loro risposta tardiva non supera comunque il Future
scaduto e non arriva a parser, repository o stato conversazionale.

Il notifier conserva in memoria il testo effettivamente inviato (dopo il trim
già previsto dall'input UI) e il riferimento immutabile all'analisi precedente:
ID, revisione, fatti, domanda e turni. Questa richiesta fallita non è un fatto
validato. «Riprova» reinvia quel testo con lo stesso contesto, senza aggiungere
un secondo messaggio utente. Un primo turno fallito non ha ancora un'identità
di analisi validata: l'ID viene creato alla prima risposta accettata, come prima.
Le continuazioni conservano invece l'ID e incrementano la revisione soltanto
quando il repository restituisce l'analisi. Il catalogo locale viene riletto e
rimane autoritativo anche durante il retry.

Durante il retry sono bloccati altri invii e salvataggi. Un nuovo errore lascia
disponibile la stessa azione; il successo elimina lo stato recuperabile.
«Nuova analisi», disponibile dopo l'errore, azzera il tentativo; un nuovo testo
inviato normalmente lo sostituisce. I vecchi messaggi rimangono nella cronologia.
Il notifier verifica inoltre la generazione locale delle operazioni asincrone
prima di applicarne gli esiti, invalidandola al reset e alla distruzione.
Nessun retry salva osservazioni economiche o modifica revisioni già persistite.
Il recupero è solo in memoria e non sopravvive alla chiusura dell'app.

`test/planner_retry_test.dart` usa esclusivamente trasporti HTTP simulati per
timeout di entrambi i provider, retry iniziale e del completamento `500`, errori
ripetuti, identità/revisioni, doppio tap, reset, risposte/errori tardivi, UI e
assenza di scritture economiche.
