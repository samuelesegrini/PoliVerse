# Personalizza flow — PROTOTYPE (throwaway)

**Question:** what should Personalizza's whole flow be if it follows the Lock
Screen's curated model, and how does swipe-up-to-delete feel on a look?

Open `index.html`. No build, no dependencies, state in memory. Drag with the
mouse as on the phone; the side panel lists the flow, jump buttons, what
changes from `CustomizeOggi`, open questions, and the live state.

## The flow

1. **Oggi** — the brush in the bar, or a long press on the date.
2. **Galleria** — saved looks on black. Sideways uses one, **up lifts the card
   and shows the trash** (one look left: rubber-band only), tap returns to the
   app. The last card is *Aggiungi nuovo*.
3. **Aggiungi** — a gallery of starting points: kinds on top (Flavor, foto,
   carta, casuale, copia, vuota), then In primo piano / Temi / Flavor / Carte.
4. **Editor** — the page full size with outlined zones, each opening one small
   sheet. Sideways swipes run through variants (Naturale, Tinta, Contrasto,
   Notte, Carta). Flavor bottom-left, the rest behind •••. Annulla / Aggiungi
   (new) or Annulla / Fine (existing, on a draft).
5. **Aggiungi → App** — the first time a look is saved it asks once: *Abbina
   all'app* (the app takes colour, icon and bar from the page) or
   *Personalizza l'app*. Either way the look goes in use and drops into the
   gallery, labelled "App abbinata" or "App su misura".
6. **App** — the other half of a look, a card previewing Corsi (the Home
   Screen while choosing the icon). Abbinata, Colore, Icona, Barra: any choice
   of its own unpairs; Abbinata pairs again. Later only from the editor's
   **••• › App**, whose Fine returns to the page editor.

## Decided

- Adding a look always uses it — no question at the end.
- Variants are fixed: the same five for every look.
- Delete is immediate, with an Annulla toast.
- The app question is asked once per look, on adding; afterwards only ••• › App.
- Barra moves from the page's ••• menu into App.
