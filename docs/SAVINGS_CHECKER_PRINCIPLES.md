# Principi di Risparmiai

> Che cosa deve essere Risparmiai anche se tra sei mesi cambiamo completamente l'implementazione?

Questo documento definisce l'identità del prodotto e i principi che devono guidarne l'evoluzione. Vale anche quando cambiano architettura, provider AI, persistenza o interfaccia. Esprime il comportamento da perseguire, senza attestare che ogni principio sia già interamente realizzato nell'implementazione corrente.

## 1. Scopo dell'app

Una persona al supermercato descrive liberamente un prodotto. Risparmiai cerca di determinarne il costo realmente comparabile e, quando esiste un riferimento valido, ne valuta la convenienza.

## 2. Open-world

L'app deve poter analizzare prodotti e categorie non previsti durante lo sviluppo. Le categorie predefinite sono conoscenza iniziale, non un limite funzionale.

## 3. AI per comprensione, Dart per matematica

L'AI identifica prodotto e categoria, estrae dati verificabili e può proporre uno schema per una categoria sconosciuta. Non calcola costo unitario, risparmio, media, minimo o convenienza.

Questi calcoli spettano alla logica deterministica dell'app, oggi in Dart. La separazione tra comprensione e calcolo deve restare valida anche se cambia la tecnologia utilizzata.

## 4. Schema locale autoritativo

Una categoria sconosciuta può essere proposta dall'AI. Una volta validata e persistita, `categoryKey`, `canonicalMetric` e `requiredAttributes` diventano autoritativi. L'AI non può ridefinirli implicitamente nelle richieste successive.

Il nome visualizzato e le etichette leggibili non determinano l'identità della categoria o la sua metrica canonica.

## 5. Categorie semplici e complesse sono entrambe valide

`requiredAttributes: []` è perfettamente valido. Una categoria può non richiedere attributi aggiuntivi quando la quantità è già espressa nella metrica canonica. Restano necessari prezzo e quantità validi per calcolare il costo comparabile.

Acqua:

```text
canonicalMetric = liter
requiredAttributes = []
```

Carta igienica:

```text
canonicalMetric = sheet
requiredAttributes =
  rolls_count
  sheets_per_roll
```

## 6. Generalizzazione prima delle eccezioni

Il sistema deve preferire meccanismi generali: quantità già nella metrica canonica, conversioni deterministiche e quantità derivate da attributi. Le regole specifiche per categoria devono esistere soltanto quando realmente necessarie.

## 7. Mai inventare informazioni mancanti

Se per sapere il costo per strappo mancano gli strappi per rotolo, l'app non deve stimarli. Deve rendere esplicito ciò che manca, senza presentare un costo comparabile non dimostrabile.

## 8. Costo comparabile e convenienza sono concetti distinti

`0,50 €/L` può essere determinato anche alla prima osservazione. Dire «è conveniente» richiede invece un riferimento valido e comparabile. L'assenza di un riferimento non impedisce di mostrare un costo comparabile calcolato correttamente.

## 9. Confronto prima della persistenza

La nuova osservazione viene confrontata con lo snapshot storico precedente. Solo successivamente può aggiornare lo storico. Non deve diventare il proprio riferimento per stabilire la convenienza.

## 10. Integrità prima della risposta

Se non possiamo dimostrare che due valori rappresentano la stessa grandezza, non li confrontiamo e non li aggreghiamo. Una risposta incompleta ma corretta è preferibile a una conclusione basata su dati incompatibili o inventati.

## Esempi non normativi

Questi sono esempi del modello generale, non l'elenco dei prodotti supportati. Illustrano il comportamento desiderato, senza imporre regole speciali per le categorie citate.

```text
Acqua
1,5 L a 0,75 €
→ 0,50 €/L

Pastiglie lavastoviglie
40 pastiglie a 8 €
→ 0,20 €/pastiglia

Carta igienica
12 rotoli × 500 strappi a 5,99 €
→ 6000 strappi
→ circa 0,000998 €/strappo

Prodotto sconosciuto
→ AI propone categoria e metrica
→ Dart valida dati e schema
→ se calcolabile: costo comparabile
→ schema validato e persistito riutilizzabile in futuro
```

In ciascun esempio, la valutazione della convenienza richiede un riferimento valido distinto dalla nuova osservazione.
