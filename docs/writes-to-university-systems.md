# Scritture verso i sistemi dell'ateneo — decisione

Deciso il 2026-09-22. Questo documento registra una scelta che finora era
implicita nel codice: PoliVerse **legge** dai sistemi del Politecnico e da
WeBeep, e non **scrive**.

La scelta stava già nel codice, ma da nessuna parte come decisione: chi
leggeva `CourseForum` vedeva solo un parser senza `post`, e chi leggeva
`ExamDetailView` vedeva una frase che manda lo studente altrove. Senza una
ragione scritta, la prossima persona che ci passa la legge come lavoro non
finito.

## Cosa l'app non fa

| Azione | Endpoint noto | Stato |
| --- | --- | --- |
| Iscriversi a un appello | `POST iae/v1/iscriz/{a}/{b}/{c}` | non implementato |
| Ritirarsi da un appello | `DELETE iae/v1/iscriz/{id}` | non implementato |
| Rifiutare un voto | `PATCH iae/v1/esito/rifiuta/{id}` | non implementato |
| Chiedere un colloquio sul voto | `PATCH iae/v1/esito/richcoll/{id}` | non implementato |
| Scrivere in un forum WeBeep | `mod_forum_add_discussion` | non implementato |
| Consegnare un compito | `mod_assign_save_submission` | non implementato |

I percorsi vengono da [polimi-api-research.md](polimi-api-research.md) §4c,
letti dal bundle del client ufficiale. Sono elencati qui perché *sapere come*
non è *decidere di*.

## Perché

1. **Una scrittura sbagliata non si annulla dallo studente.** Un'iscrizione
   mancata a un appello, o un voto rifiutato per errore, costa una sessione.
   Una lettura sbagliata costa un aggiornamento.

2. **Le forme delle richieste non sono verificate.** `docs/polimi-api-research.md`
   §4c dice, di tutto ciò che sta su quell'host: *«Response shapes beyond these
   field names are INFERRED»*. Il corpo di `POST /v1/iscriz` è noto solo in
   parte (`{cRisposta, cRispostaAteneo}`), e i tre parametri di percorso non
   sono identificati. Indovinare una lettura produce una schermata vuota;
   indovinare una scrittura produce un'iscrizione a qualcos'altro.

3. **Code 6 non è un errore di richiesta.** `docs/endpoint-status.md` documenta
   che `iae` risponde *«Utente non abilitato Code: 6»* tra una sessione e
   l'altra. Una scrittura che parte in quella finestra fallisce in un modo che
   l'app non sa distinguere da un rifiuto di merito.

4. **Zona grigia sul permesso.** [academic-intelligence-layer.md](academic-intelligence-layer.md)
   §0: nessuna norma trovata su client non ufficiali. Leggere con la sessione
   dello studente sul suo dispositivo resta nel perimetro in cui l'app opera
   già; agire al posto suo sul sistema d'ateneo è un'altra cosa, e non è una
   scelta che si prende per omissione.

5. **Nei forum, scrivere non è il buco che sembra.** I forum `announcements`
   sono a sola scrittura del docente per costruzione
   (`CourseForum.isAnnouncements`), quindi «rispondere» non si applica alla
   parte che lo studente legge di più. Per i forum di discussione, un post
   pubblicato dall'app porta il nome dello studente davanti al corso intero:
   è la stessa categoria di azione irreversibile del punto 1.

## Cosa l'app fa invece

Legge, confronta e avvisa — e quando serve un'azione, manda allo strumento
ufficiale con il contesto già in mano:

- `ExamDetailView` mostra la finestra d'iscrizione e dice dove si gestisce.
- `CorrectionsSection` elenca gli elaborati corretti e apre i Servizi Online.
- `DeadlineDetailView` apre la consegna su WeBeep.
- Le notifiche di `ExamUpdatePolicy` arrivano *prima* che la finestra si
  chiuda, che è il valore vero: il problema di uno studente non è che
  iscriversi richieda due tap in più, è accorgersene il giorno dopo.

## Quando riaprire la decisione

Se e quando: (a) le forme delle richieste sono verificate su un account reale
e documentate qui, **e** (b) esiste una conferma esplicita per ogni scrittura,
con il testo di ciò che sta per succedere, **e** (c) il proprietario decide di
accettarne la responsabilità. Finché i tre punti non valgono insieme, la
risposta resta questa.
