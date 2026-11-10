# Onboarding: spiegare le funzioni con scene illustrate

Le prime tre proposte (sequenza di schede, finestra dell’app e funzione in primo piano) sono state scartate: troppo monotone e poco illustrate.

La nuova direzione usa una scena animata per spiegare un’azione concreta, con un titolo e una descrizione espliciti. I disegni sono SwiftUI, senza immagini da scaricare o richieste ai servizi universitari.

- **Giornata:** un campus illustrato mostra il percorso verso la lezione e il promemoria; evidenzia un’aula libera con il suo intervallo; un calendario evidenzia la scadenza di iscrizione all’appello.
- **Studio:** i documenti escono dalla cartella WeBeep del corso; il player recupera il minuto salvato; una simulazione del voto fa cambiare la media.

Il flusso proposto è landing → funzionalità → login → collegamento dei servizi → impostazioni aggiuntive → ingresso nell’app. Non viene chiesto come ordinare Oggi.

## Aprire il prototipo

```sh
./scripts/preview-onboarding-features.sh day
./scripts/preview-onboarding-features.sh study
```

L’argomento opzionale `0`, `1` o `2` apre una funzione specifica. I nomi delle funzioni permettono di esplorare gli esempi; il comando pausa ferma il racconto. Riduci movimento mostra il risultato statico. Continua è sempre disponibile.

Le scene sono montate sulle due pagine precedenti al login, solo in DEBUG con `-PrototypeFeatures Illustrated`. I dati sono illustrativi e non vengono salvate preferenze per la home. La presentazione definitiva verrà integrata dopo la revisione visiva; il prototipo verrà conservato in un ramo temporaneo al momento della scelta, senza includere gli altri lavori in corso nello spazio condiviso.

Già applicato al flusso comune: rimossa la barra di avanzamento, rimossi gesto/maniglia/invito a trascinare nell’ultima pagina. Il pulsante con freccia verso destra attiva la stessa animazione di uscita verso il basso. Il completamento non riordina Oggi e il riepilogo non descrive più una scelta della home.
