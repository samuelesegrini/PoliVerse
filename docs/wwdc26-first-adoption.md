# WWDC26: prima adozione delle priorità alte

Implementazione iniziata il 3 novembre 2026, dalla ricerca
[WWDC26: opportunità](wwdc26-opportunities.md), baseline `89f35328`.

## App Intents: integrazione attraverso il sistema

La scheme **PoliVerseSystemIntegrations** usa Debug e seleziona
`SystemIntentsTests` nel bundle UI esistente. I test importano AppIntentsTesting,
non il modulo dell’app. App e runner usano lo stesso development team.

Tre percorsi verificati sul simulatore iPhone iOS 27.2:

- Corso risolto per parte del nome, codice e identità; query senza corrispondenze.
- Appelli suggeriti: esclusione del passato, ordine temporale e passaggio
  dell’entità al vero `ExamDateIntent`, che restituisce la stessa identità.
- Aula risolta e passata al vero `RoomFreeIntent`. Questo controllo verifica
  risoluzione e dispatch, **non il testo della risposta pronunciata**.

`SystemIntegrationFixturesIntent` segue il modello di intent per i test mostrato
nella sessione Apple: `#if DEBUG`, `isDiscoverable = false`, avvio esplicito
`-SystemIntegrationTests` e dati di esempio obbligatori. I record sono scritti
soltanto nell’account sintetico `__system-integration-tests__`; il teardown
ripristina l’account precedente e rimuove questi record. Le azioni non sono
compilate in Release. Non vengono cambiate iscrizioni, voti o dati universitari.

```sh
xcodebuild -project PoliVerse.xcodeproj -scheme PoliVerseSystemIntegrations \
  -destination 'platform=iOS Simulator,id=ID_DEL_SIMULATORE' test
```

Per i test di sviluppo le risorse `.icon` possono essere escluse separatamente,
come nelle altre verifiche del progetto. Questo non è un controllo delle icone.

Fonte: [WWDC26 — AppIntentsTesting](https://developer.apple.com/videos/play/wwdc2026/295/).

## Riassunti: valutazione del generatore realmente usato dal forum

`NoticeSummaryEvaluation` chiama `NoticeSummary.summarise`, conserva il risultato
in un report Evaluations e lo allega al risultato dei test prima di applicare
le soglie. Il corpus contiene 25 avvisi sintetici, con riferimenti scritti a mano:
date, cambi aula, proroghe, negazioni, esiti, informazioni non ancora disponibili,
inglese e messaggi bilingui. Le informazioni importanti occupano posizioni
diverse nell’avviso. Il corpus non contiene dati degli studenti.

Le metriche sono:

- **Concise**: testo non vuoto, su una riga e lungo al massimo 320 caratteri.
- **Fidelity**: giudizio da 0 a 4 sulla conservazione di fatti, date, aule e
  negazioni rispetto ad avviso originale e riferimento umano.
- **Language**: confronto tra la lingua riconosciuta nel risultato e nel riferimento
  tramite `NLLanguageRecognizer`, senza restringere le lingue possibili.

La generazione e il giudice di fedeltà usano il modello sul dispositivo. Il giudice della
stessa famiglia non è una verifica indipendente della verità: i suoi giudizi sono
probabilistici e vanno accompagnati dall’esame delle risposte. La metrica sulla
lunghezza, invece, è un controllo deterministico. Il riconoscimento della lingua
è una misura statistica, particolarmente incerta su testi brevi; non misura
la correttezza della traduzione.

Le soglie iniziali sono 100% per il formato conciso, media Fidelity almeno 3/4,
Language almeno 0,9 e **minimo Fidelity almeno 2/4**. L’ultimo criterio impedisce
che un errore grave venga nascosto da una buona media. Sono criteri di questo
benchmark, non garanzie di correttezza per tutti gli avvisi degli utenti.

Esecuzione esplicita su Mac con Apple Intelligence abilitata e modello scaricato:

```sh
./scripts/run-notice-evaluations.sh
```

Il runner isola i file del benchmark sul Mac, perché altri test del target sono
specifici di iOS; mantiene i report in un bundle `.xcresult` temporaneo. Controlla
anche che `NoticeSummaryTests/quality()` sia stato eseguito e passato: zero test
o un test saltato non sono un successo. La scheme **PoliVerseNoticeEvaluations**
abilita `RUN_NOTICE_EVALUATIONS=1`; non filtra gli altri test del target, quindi
su un dispositivo può essere eseguita con le normali prove compatibili.

Nella scheme ordinaria la prova di qualità è disabilitata. Quando è richiesta
esplicitamente, l’assenza del modello è una precondizione fallita, non un risultato
positivo. Il test ordinario del fallback viene eseguito soltanto quando il
modello non è disponibile.

### Prima misura e controllo dei singoli risultati

La prima esecuzione completa ha impiegato 233,8 secondi su questo Mac:
Concise 1,0; Fidelity media 3,24/4; Language 1,0. Distribuzione Fidelity:
8 risultati con voto 4, 16 con voto 3, uno con voto 1.

Il risultato con voto 1 è stato controllato anche manualmente: per un avviso di
proroga della consegna al 22 novembre, il generatore ha scritto «È stato cambiato
l’aula». È un errore sul fatto principale, non una differenza di formulazione.
Per questo il gate comprende ora anche il minimo, oltre alla media. Il primo
report sarebbe stato respinto da questo criterio. Nessuna modifica al prompt o
alla funzione di generazione è presentata come correzione di questo problema.

Una seconda esecuzione con il criterio sul minimo ha impiegato 250,3 secondi
ed è stata respinta: media Fidelity 2,958/4 sui 24 giudizi disponibili, minimo 1;
un giudizio è fallito per contesto troppo lungo. Tre risposte hanno inventato
un cambio aula. Inoltre, il giudice della lingua ha prodotto giudizi incoerenti
con la propria motivazione. La versione `native-language/fidelity-v2` sostituisce
quel giudizio con il riconoscitore nativo e usa istruzioni più brevi per il solo
giudice di fedeltà, mantenendo avviso originale e riferimento. Le misure delle
due versioni non sono direttamente confrontabili.

L’esecuzione finale `native-language/fidelity-v2` ha impiegato 124,3 secondi:

| Controllo | Risultato |
| --- | --- |
| Risposte generate | 25/25 |
| Concise | 1,0 |
| Language | 0,88 — soglia non superata |
| Fidelity | media 3,833/4 e minimo 3, su 24 giudizi |
| Errori del giudice | 1 rifiuto |
| Esito complessivo | **Fallito** |

I tre avvisi interamente inglesi sono stati riassunti in italiano. Un caso di
proroga al 6 dicembre alle 18:00 è diventato «È stata comunicata una modifica
dell'orario». Il giudice gli ha assegnato erroneamente 4, descrivendo nella
motivazione i fatti del riferimento invece della risposta reale. Una verifica
separata di `judgePrompt(for:output:)` con valori sentinella conferma che il
framework inserisce il candidato effettivo nella sezione Response: non è stata
rilevata una sostituzione del candidato con il riferimento nella costruzione
del prompt. Il giudice della stessa famiglia può comunque confonderli.

**Il punteggio Fidelity non basta per approvare il prodotto.** Il report conserva
risposte e riferimenti per la revisione umana; l’esito complessivo resta rosso.
Questo lavoro non corregge il generatore preesistente né dimostra che il nuovo
valutatore possa intercettare ogni errore. Non si devono confrontare i tempi
delle tre esecuzioni come prova di miglioramento delle prestazioni dell’app.

I punteggi non sono una stima dell’accuratezza su tutti gli avvisi e non devono
essere convertiti in una percentuale di affidabilità del prodotto.

Fonte: [WWDC26 — Evaluations](https://developer.apple.com/videos/play/wwdc2026/298/).

## Sottotitoli: usare le capacità native di AVKit

Il lettore di produzione usa già `AVPlayerViewController` su iPhone/iPad e
`AVPlayerView` su Mac, con i controlli nativi. Apple documenta l’integrazione
automatica dei menu di scelta e anteprima dello stile: non serve un secondo
selettore di sottotitoli nell’app.

La disponibilità documentata comprende trascrizione inglese→inglese e traduzione
da sottotitoli inglesi ad altre lingue sui sistemi e dispositivi compatibili.
Questo lavoro non promette trascrizione dell’audio italiano.

Il bundle di test contiene `Fixtures/subtitles-en.mov`, un campione sintetico
locale di circa 35 secondi, con audio inglese dichiarato e senza traccia di
sottotitoli già scritti. `RecordingSubtitlePlaybackTests` è un controllo Mac
esplicito: con `RUN_RECORDING_SUBTITLE_CHECK=1` apre il file tramite il vero
`RecordingPlayer`, verifica metadati e avanzamento e lascia la finestra aperta
per esaminare i menu nativi. L’asserzione automatica riguarda la riproduzione;
non certifica l’esistenza o la qualità dei sottotitoli generati.

### Controllo locale eseguito

Sul MacBook Pro di sviluppo con macOS 27.2, il campione ha superato il test di avanzamento (60 secondi).
Il menu AVKit mostrava **Attivi / Non attivi** e **Stile**, con Classico,
Sfondo trasparente, Testo con contorno e Testo grande. Attivando i sottotitoli
non è apparso testo durante la parte osservata del campione. La presenza dei
controlli è verificata; la generazione automatica non è certificata da questa
prova. Non è stata aggiunta una UI alternativa né una promessa di supporto
all’audio italiano.

Per il controllo manuale su altri dispositivi annotare: dispositivo e sistema, menu Lingua/Stile,
presenza dell’opzione generata, parole effettivamente visualizzate e
comportamento senza rete. La prova locale non sostituisce una successiva prova
HLS autenticata su una registrazione reale.

Fonte: [WWDC26 — Generated subtitles](https://developer.apple.com/videos/play/wwdc2026/256/).

## Verifiche complessive

La suite ordinaria è stata eseguita sul simulatore iPhone iOS 27.2 con tutte
le icone incluse: **1.333 test superati, 7 saltati, nessun fallimento**
(1.340 test dichiarati; i casi parametrizzati producono ulteriori esecuzioni).
I controlli costosi o manuali restano a esecuzione esplicita. Il benchmark
di qualità ha un esito distinto dalla suite ordinaria.

Revisione Standards e Spec: nessun rilievo aperto dopo la correzione della
metrica Language. La tranche aggiunge strumenti e verifiche; non attribuisce
benefici prestazionali né correzioni del generatore a questi soli cambiamenti.
Il profiling Release dei percorsi reali della ricerca resta un passo separato.
