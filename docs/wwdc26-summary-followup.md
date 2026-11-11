# Riassunti: passaggi originali e verifica della selezione

Seconda tranche WWDC26, dalla baseline `4471d2d7`. Il problema iniziale e le
misure precedenti sono in [prima adozione](wwdc26-first-adoption.md).

## Problema riprodotto

Il generatore libero poteva sostituire una proroga con un cambio aula e
riassumere avvisi inglesi in italiano. Prima della modifica, il nuovo test
sulla proroga inglese è fallito su lingua, mese, giorno e ora (4 asserzioni,
3,86 secondi, modello reale). Un controllo rapido di sei avvisi tramite
`NoticeSummary.summarise` ha riprodotto lingua errata e fatti inventati.

Cambiare soltanto la lingua delle istruzioni ha migliorato i casi inglesi,
ma un avviso sulla revisione degli elaborati ha ancora prodotto data, ora e
aula inesistenti. Il prompt da solo non era una protezione sufficiente.

## Comportamento finale

Il modello propone da tre a otto parole chiave, con una risposta limitata a
64 token. L'app usa soltanto le parole che compaiono nell'avviso per trovare
un breve passaggio originale: i termini rari pesano più di quelli ripetuti e
la densità delle corrispondenze evita di privilegiare il testo generico.
Servono almeno due corrispondenze. A parità di punteggio viene preferito il
passaggio più corto.

Il passaggio iniziale comprende fino a tre frasi consecutive. L'app aggiunge
contesto fino a due frasi per lato, privilegiando le frasi adiacenti e mantenendo
l'intero risultato entro 320 caratteri. Non taglia una frase per farla rientrare
nel limite. Le parole chiave generate non vengono mostrate: ogni parola del
risultato proviene dall'avviso, nello stesso ordine, con spazi normalizzati.

Le occorrenze delle frasi restano distinte; non si cerca soltanto la prima
occorrenza di un testo duplicato. Se non esiste un passaggio breve con
corrispondenze sufficienti, l'app conserva soltanto l'originale. Un saluto
breve non viene imposto come risposta quando il fatto principale è una frase
troppo lunga. Anche indisponibilità del modello ed errori mantengono questo
comportamento.

Il limite è di 4.000 caratteri normalizzati: le frasi che attraversano il
confine restano nel testo originale, senza entrare nella selezione. Una frase
che termina esattamente al confine viene conservata, anche se il tokenizer
include spazi successivi. Il modello riceve il testo una sola volta, senza
elenchi di citazioni sovrapposte né schemi contenenti altre copie dell'avviso.

Il pulsante, la scheda «In breve» e la consultazione dell'originale mantengono
il flusso esistente. Il risultato è ora un estratto, anziché una parafrasi:
può essere meno elegante e includere contesto generico. La citazione impedisce
l'aggiunta di parole inventate; **non garantisce che la selezione sia la più
utile o semanticamente completa**. Le parole chiave possono essere sbagliate;
una precisazione può trovarsi oltre la finestra selezionata. Il corpus verifica
italiano, inglese e avvisi misti; non dimostra la qualità in tutte le lingue.

La generazione usa greedy sampling per rendere più ripetibile il controllo
sullo stesso modello. Gli aggiornamenti del modello e del sistema richiedono
nuove verifiche; non si promette identità dei risultati tra versioni o dispositivi.
[Apple — GenerationOptions](https://developer.apple.com/documentation/foundationmodels/generationoptions/samplingmode-swift.struct/greedy).

## Valutazione

Il corpus sintetico originale di 25 avvisi e i suoi riferimenti restano invariati.
La metrica **Grounded** verifica che ogni risultato sia una citazione dell'avviso;
la sua soglia è 100%. Lingua, concisione, media e minimo Fidelity mantengono le
soglie precedenti. Gli errori di generazione o valutazione continuano a fallire
il test, senza venire esclusi dal risultato positivo.

Undici casi di regressione verificano con stringhe attese indipendenti date, orari,
aule, negazioni e distinzione individuale/gruppo. Altri controlli coprono testo
vuoto, frase troncata, astensione quando il solo testo breve è un saluto e
avviso di oltre 4.000 caratteri con la proroga completa al confine. Questi controlli non dipendono dal giudice generativo.

Il giudice Fidelity usa una sessione nuova per avviso e una risposta strutturata
con il solo voto 0–4, limitata a 64 token. Evita così motivazioni potenzialmente
molto lunghe. Confronta l'effettivo passaggio con l'avviso originale;
il riferimento atteso resta nel report e nel controllo della lingua, senza essere
ripetuto al giudice come possibile risposta. Questo riduce l'ambiguità osservata,
ma non rende il giudice indipendente o infallibile. Le metriche della versione
`grounded/bounded-judge-v4` non sono direttamente confrontabili con quelle precedenti.

```sh
./scripts/run-notice-evaluations.sh
```

Le verifiche sul modello restano esplicite; la suite ordinaria esegue i controlli
compatibili senza richiedere Apple Intelligence. Nessun dato degli studenti è
incluso nel corpus o nei report di prova. Nessun beneficio di CPU, memoria o
fluidità dell'app è dedotto da questi test sintetici.

## Risultati del 3 novembre 2026

Esecuzione sul MacBook Pro con macOS 27.2 e modello disponibile. Il benchmark
completo è passato in **78,5 secondi** (durata di `Evaluation.run`, senza build):

| Controllo sui 25 avvisi | Risultato |
| --- | --- |
| Risposte prodotte | 25/25 |
| Citazione dell'originale (Grounded) | 25/25 |
| Formato e lunghezza (Concise) | 25/25 |
| Riconoscimento della lingua (Language) | 24/25 |
| Fidelity, giudice sul dispositivo | media 3,56/4; minimo 3/4 |
| Errori di generazione o valutazione | nessuno |

Il mancato accordo della lingua riguarda un avviso bilingue: il risultato cita
parole delle due lingue presenti nella fonte. La metrica confronta la lingua
riconosciuta con quella del riferimento e resta euristica. Gli undici casi con
fatti attesi, il caso al confine e il rifiuto del solo saluto sono passati. Il
test del modello indisponibile è saltato sul Mac, dove il modello era disponibile.

La suite ordinaria completa, con tutte le risorse e le icone, è passata su
iPhone 18 Pro simulato con iOS 27.2: **1.336 test superati, 9 saltati, nessun
fallimento**. I casi parametrizzati generano ulteriori esecuzioni. Per questa
verifica è stato usato un simulatore nuovo dopo un precedente tentativo fermo
nel runner; non sono stati esclusi test o risorse dalla verifica finale.

Le risposte del report sono state esaminate insieme ai riferimenti, oltre alle
asserzioni automatiche. I voti non sono una percentuale di affidabilità del
prodotto; il giudice usa la stessa famiglia di modello e non è una verifica
indipendente. Questa esecuzione non prova affidabilità generale del giudice né
parità prestazionale su dispositivi fisici.

Report Evaluations: `NoticeSummaryEvaluation`, risultato
`ACFFD8EC-9DE3-4909-9DCC-83CFC7AC3513`, allegato al bundle di risultati.
Revisione Standards e Spec: nessun rilievo aperto nella versione finale.
