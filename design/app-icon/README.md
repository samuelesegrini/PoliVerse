# App icon

A ringed planet: the *-Verse* of PoliVerse, with one amber moon for the thing
coming up next. Navy and amber are the app's own colours, so the icon sits in
the same family as ``Theme`` and the default ``Flavor``.

It deliberately avoids the mortarboard every university app reaches for, and it
carries nothing from the Politecnico's own identity — PoliVerse is not an
official app, and the icon should not suggest otherwise.

> **No SF Symbols.** Apple's terms prohibit using a symbol — *or an image
> confusingly similar to one* — in an app icon, a logo, or any other
> trademarked use. Every shape here is drawn from scratch, and the subject is
> one SF Symbols does not cover.

## Files

| File | What it is |
|---|---|
| `build-icon.py` | the source of truth; regenerates everything below |
| `layers/` | one 1024×1024 SVG per Icon Composer layer |
| `preview.svg` | all layers flattened, for looking at |
| `verify.html` | the icon at real sizes, each layer on transparency, and the layers restacked |

Layers are numbered in back-to-front order:

1. `1-background` — the navy gradient. Drop it if you'd rather use Icon
   Composer's own background.
2. `2-ring-back` — the far half of the ring, dimmed so it sits behind.
3. `3-planet` — the sphere.
4. `4-ring-front` — the near half, with a hole punched where the moon crosses.
5. `5-moon` — the amber accent.

## Importing into Icon Composer

1. Open **Icon Composer** (bundled with Xcode: Xcode ▸ Open Developer Tool).
2. New document, then drag the five SVGs in **in numbered order** — Icon
   Composer stacks them bottom-up, so `1-background` goes first.
3. Leave each layer's position and scale alone. All five share one 1024×1024
   coordinate space, so they land registered with no nudging.
4. Add depth per layer rather than in the artwork: a soft shadow on
   `4-ring-front` is what makes the ring read as passing in front of the
   sphere, and a small specular highlight on `3-planet` gives it form. The SVGs
   are deliberately flat so the tool owns those effects.
5. For the dark and mono appearances, drop `1-background` and let Icon Composer
   supply the ground. The other four layers already hold up on their own —
   `verify.html` shows them over a light ground.

## Why the SVGs are shaped the way they are

Icon Composer's importer is conservative, so `build-icon.py` only emits what it
handles predictably:

- flat fills and plain linear gradients — no CSS, no filters, no masks;
- `gradientUnits="userSpaceOnUse"`, so the ring's gradient stays one continuous
  field across the two halves instead of restarting inside each layer's own
  bounding box;
- no `transform` attributes — every rotated coordinate is baked into the path
  data;
- strokes converted to filled outlines, so weights cannot shift on import;
- the moon's clearance is a real hole punched through the ring rather than a
  painted disc, so it stays correct whatever the background becomes.

## Changing it

Edit the constants at the top of `build-icon.py` — the ring's radii and tilt,
the planet's size, where the moon sits — then:

```bash
python3 build-icon.py
```

It prints the artwork's bounds so you can check nothing has drifted towards the
corners, where the icon mask would clip it. Open `verify.html` afterwards: the
icon has to survive 40pt, which is where most people actually see it.
