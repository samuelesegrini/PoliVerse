# Manifesti degli Studi

The university's public course catalogue. **No authentication, HTML only** —
`onlineservices.polimi.it/manifesti` is a Struts application with no API behind
it, so everything is scraped.

It answers what the authenticated services cannot: what a teaching covers,
which books it uses, who lectures which alphabetical bracket, and all of that
*before* enrolling.

## Endpoints, all verified 2026-09-12

Base: `https://onlineservices.polimi.it/manifesti/manifesti/controller`

| Purpose | Request |
| --- | --- |
| Search teachings | `POST ricerche/RicercaPerInsegnamentoPublic.do` |
| Search teachers | `ricerche/RicercaPerDocentiPublic.do` |
| A teacher's teachings | `RicercaPerDocentiPublic.do?evn_didattica=evento&k_doc=…` |
| Teaching detail | `ManifestoPublic.do?EVN_DETTAGLIO_RIGA_MANIFESTO=evento&k_corso_la&k_indir&idItemOfferta&idRiga&codDescr&aa` |
| Course structure | `MostraIndirizziPublic.do` |
| Faculty | `MostraFacultyPublic.do` |
| PDF of the manifesto | `ManifestoPublic.do?evn_stampa=EVENTO&tipo=PDF` |

Search form fields: `aa`, `k_cf` (school), `sede`, `tipoCorso`, `ac_ins`
(year), `semestre`, `aree`, `tipoInsegnamento`, `insegn_ricerca`, `lang`.
`-1` / `ALL_*` mean "any".

### The syllabus is a different service

The manifesto hides it behind an icon linking to
`aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=178&c_classe=N`,
which **redirects to a public page**:

```
https://onlineservices.polimi.it/schedaincarico/schedaincarico/controller/
        scheda_pubblica/SchedaPublic.do?evn_default=evento&c_classe=N&lang=IT
```

The direct URL returns byte-identical content, so the app skips the redirect.
Sections: obiettivi, risultati di apprendimento attesi, argomenti trattati,
prerequisiti, modalità di valutazione, **bibliografia**.

### Personalised timetable (the cart)

Server-side state on a session cookie:

```
GET  ManifestoPublic.do?evn_gointrocarrello=evento&aa=…      intro
POST ManifestoPublic.do  evn_setcognome + cognome="Cognome Nome"   → sets the bracket
GET  ManifestoPublic.do?EVN_ADDCART=EVENTO  + aa,k_corso_la,k_indir,
     codDescr,ac_ins,semestre,sezione       → <success><num-ins-cart>N</…>
GET  ManifestoPublic.do?EVN_DELCART=EVENTO  + same
GET  ManifestoPublic.do?evn_eliminacarrello=evento           empties it
GET  GestioneCarrelloPublic.do?EVN_DEFAULT=evento&aa=…       the weekly grid
```

Capacity is 15 teachings. The service warns that a surname without a forename
may resolve the bracket wrongly, so the app sends both and repeats the warning.

## The scaglione

Big first-year teachings are split by surname, and which bracket a student
falls in decides **their lecturer and their timetable**. It appears nowhere
else in any Politecnico service the app talks to.

The page labels the bounds "Da (compreso)" and "A (escluso)", and the app
implements exactly that: a bracket `CAS`–`FER` takes Casati and not Ferrari.
Matching folds case and accents, because a student types their name the way
they write it and the registry stores it shouted and unaccented.

## What is not implemented, and why

**The weekly grid is shown as the university renders it**, in the same cookie
session, rather than parsed into a native calendar. The slot cells are empty
until the year's timetables are published, and for 2026/27 they were not at the
time of writing — verified against 2025 as well. Parsing an empty grid would
produce a confident, beautiful, blank week, which reads as a broken app rather
than an unpublished timetable. Everything else about the cart is native.

## On scraping

`HTMLScraper` reads three shapes with regular expressions: label/value cards
(`ElementInfoCard1`/`ElementInfoCard2`), table rows, and links. That works
because the markup is template-generated and therefore regular. It is **not** an
HTML parser and must not be asked to become one — the moment a page needs real
nesting, the answer is a parser.

Parsing lives in `ManifestoParser`, apart from the networking, so it can be
tested against saved markup. The fixtures in `ManifestoParserTests` are real
fragments from the live service; a scraper tested against invented markup tests
nothing but the invention.
