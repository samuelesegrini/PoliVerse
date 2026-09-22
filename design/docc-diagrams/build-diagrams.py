#!/usr/bin/env python3
"""Builds the diagrams in the DocC catalogue, light and dark from one definition.

Run `python3 build-diagrams.py` to regenerate
`PoliVerse/PoliVerse.docc/Resources/`.

Each diagram is written twice: `name.svg` and `name~dark.svg`. DocC picks the
dark variant by that filename suffix, so the two differ only in the palette
they are handed and can never drift apart.

The root element carries `width` and `height` as well as `viewBox`. Without an
intrinsic size an SVG has no natural dimensions to scale from, and DocC renders
it at a default far smaller than the column it sits in; with one, it fills the
width and keeps its aspect ratio.

`RENDER_SCALE` multiplies that intrinsic size without touching the drawing: the
`viewBox` stays put, so nothing is redrawn and nothing can go blurry. An image
fills its column up to its intrinsic width and stops growing after that, so
raise this if the diagrams ever sit in a column wider than `WIDTH` points and
leave space beside them.
"""
import colorsys, os, pathlib

OUT = pathlib.Path(__file__).resolve().parents[2] / "PoliVerse" / "PoliVerse.docc" / "Resources"

LIGHT = dict(ink="#1C1C1E", muted="#6C6C70", line="#C7C7CC", surface="#F7F7FA",
             surfaceLine="#D6D6DB", band="#EFEFF4", accent="#0F3D6E", accent2="#2E7FB8",
             warn="#C25E10", good="#2E7D3A", bad="#C0392B", purple="#6155C8", onAccent="#FFFFFF")
DARK = dict(ink="#F2F2F7", muted="#9A9AA0", line="#48484A", surface="#1F1F22", surfaceLine="#3A3A3D",
            band="#2A2A2E", accent="#6BA8DE", accent2="#63C2EF", warn="#FF9F45", good="#4CD964",
            bad="#FF6F62", purple="#A79BFF", onAccent="#101014")

# Multiplies the emitted width/height only. 1.0 means the drawing's own size.
RENDER_SCALE = 1.0

FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, Menlo, monospace"


# ---------------------------------------------------------------- helpers

def hsb_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0, min(1, s)), max(0, min(1, v)))
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))


def hex_to_hsb(value):
    value = value.lstrip("#")
    r, g, b = (int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return h, s, v


def derived(base_hex, hue_shift, saturation, brightness):
    """Flavor.derived(hueShift:saturation:brightness:), verbatim."""
    h, s, v = hex_to_hsb(base_hex)
    if s < 0.12:
        return hsb_to_hex(h, s, v * brightness)
    return hsb_to_hex(h + hue_shift, s * saturation, max(v * brightness, 0.25))


def ramp(base_hex, count, spread=0.16):
    """FlavorRamp.colours(_:), before the contrast nudge."""
    h, s, _ = hex_to_hsb(base_hex)
    grey = s < 0.12
    out = []
    for i in range(count):
        p = i / (count - 1) if count > 1 else 0.0
        out.append(hsb_to_hex(h if grey else h + spread * (p - 0.5),
                              s if grey else max(0.40, min(0.95, s)),
                              0.48 + 0.42 * p))
    return out


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def svg(width, height, body, title):
    # width/height as well as viewBox: see the note at the top of the file.
    shown_w = round(width * RENDER_SCALE)
    shown_h = round(height * RENDER_SCALE)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{shown_w}" height="{shown_h}" '
            f'viewBox="0 0 {width} {height}" '
            f'role="img" aria-labelledby="t"><title id="t">{esc(title)}</title>'
            f'<style>text{{font-family:{FONT}}} .m{{font-family:{MONO}}}</style>'
            f'{body}</svg>')


def box(x, y, w, h, p, fill=None, stroke=None, r=12, dash=None, width=1.5):
    fill = fill or p["surface"]
    stroke = stroke or p["surfaceLine"]
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{width}"{d}/>')


def label(x, y, text, p, size=14, weight=600, fill=None, anchor="start", mono=False, opacity=1):
    cls = ' class="m"' if mono else ""
    return (f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill or p["ink"]}" text-anchor="{anchor}" opacity="{opacity}"{cls}>{esc(text)}</text>')


def arrow_defs(p, name="a", colour=None):
    c = colour or p["muted"]
    return (f'<defs><marker id="{name}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
            f'markerHeight="7" orient="auto-start-reverse">'
            f'<path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker></defs>')


def line(x1, y1, x2, y2, p, colour=None, marker="a", dash=None, width=1.6):
    c = colour or p["muted"]
    d = f' stroke-dasharray="{dash}"' if dash else ""
    m = f' marker-end="url(#{marker})"' if marker else ""
    return f'<path d="M{x1},{y1} L{x2},{y2}" stroke="{c}" stroke-width="{width}" fill="none"{d}{m}/>'


def chip(x, y, text, p, fill=None, stroke=None, ink=None, size=12, pad=11, h=24):
    w = len(text) * size * 0.60 + pad * 2
    return (box(x, y, w, h, p, fill=fill or p["band"], stroke=stroke or p["surfaceLine"], r=h / 2, width=1) +
            label(x + w / 2, y + h / 2 + size * 0.36, text, p, size=size, weight=600,
                  fill=ink or p["muted"], anchor="middle", mono=True), w)


# ---------------------------------------------------------------- diagrams

def layers(p):
    b = arrow_defs(p) + arrow_defs(p, "acc", p["accent"])
    # targets
    b += box(24, 56, 600, 250, p)
    b += label(44, 84, "PoliVerse — app target", p, 15, 700, p["accent"])
    b += box(664, 56, 312, 250, p)
    b += label(684, 84, "PoliVerseWidgets — extension", p, 15, 700, p["accent"])

    rows = [("Features", "screens, grouped by what a student is doing", p["accent2"]),
            ("Model", "stores, sources, observable models", p["accent"]),
            ("DesignSystem", "Theme, surfaces, previews", p["purple"])]
    for i, (name, detail, colour) in enumerate(rows):
        y = 104 + i * 66
        b += box(44, y, 560, 52, p, fill=p["band"], stroke=colour, width=1.6, r=10)
        b += f'<rect x="44" y="{y}" width="5" height="52" rx="2.5" fill="{colour}"/>'
        b += label(64, y + 24, name, p, 14, 700)
        b += label(64, y + 41, detail, p, 11.5, 400, p["muted"])

    for i, (name, detail) in enumerate([("Widgets", "Next lecture, Today, Career, Free rooms"),
                                        ("Controls", "Control Center, Lock Screen"),
                                        ("Live Activity", "the lesson in progress")]):
        y = 104 + i * 66
        b += box(684, y, 272, 52, p, fill=p["band"], stroke=p["accent2"], width=1.6, r=10)
        b += f'<rect x="684" y="{y}" width="5" height="52" rx="2.5" fill="{p["accent2"]}"/>'
        b += label(704, y + 24, name, p, 14, 700)
        b += label(704, y + 41, detail, p, 11.5, 400, p["muted"])

    # shared band
    b += box(24, 348, 952, 92, p, fill=p["band"], stroke=p["accent"], dash="6 5", width=1.6)
    b += label(44, 376, "Shared — compiled into both targets", p, 14, 700, p["accent"])
    x = 44
    for name in ["OfflineStore", "AgendaEvent", "CareerSnapshot", "WidgetKind", "AppDestination",
                 "LectureActivityAttributes"]:
        c, w = chip(x, 392, name, p, ink=p["ink"])
        b += c
        x += w + 8

    b += line(200, 306, 200, 344, p, p["accent"], "acc")
    b += label(210, 330, "writes snapshots", p, 11.5, 600, p["accent"])
    b += line(820, 344, 820, 306, p, p["accent"], "acc")
    b += label(600, 330, "reads them", p, 11.5, 600, p["accent"], anchor="end")

    # services
    b += box(24, 12, 952, 30, p, fill="none", stroke="none")
    b += label(500, 32, "Politecnico services  ·  WeBeep (Moodle)  ·  public room occupancy",
               p, 12.5, 600, p["muted"], anchor="middle")
    b += line(324, 42, 324, 100, p, p["line"], "a", dash="4 4")
    b += label(334, 62, "only Model talks to them", p, 11.5, 500, p["muted"])
    return svg(1000, 452, b, "The three layers of the app target, the widget extension, "
                             "and the Shared types compiled into both.")


def pipeline(p):
    b = arrow_defs(p) + arrow_defs(p, "ok", p["good"]) + arrow_defs(p, "no", p["warn"])
    steps = [("View", ".task { await model.load() }", p["purple"]),
             ("Model", "observable, no fetching of its own", p["accent2"]),
             ("Store", "drives one Source", p["accent"]),
             ("Source", "cache key, request, decoding", p["accent"])]
    for i, (name, detail, colour) in enumerate(steps):
        x = 24 + i * 245
        b += box(x, 44, 220, 62, p, fill=p["band"], stroke=colour, width=1.6, r=12)
        b += label(x + 16, 70, name, p, 15, 700)
        b += label(x + 16, 90, detail, p, 11, 400, p["muted"])
        if i:
            b += line(x - 22, 75, x - 4, 75, p)

    b += label(24, 150, "What one load() does, in order", p, 13, 700, p["muted"])
    order = [("1", "read the cache and publish it", "the first frame already has something to draw", p["good"]),
             ("2", "ask the LoadWindow", "is a refresh due at all?", p["accent"]),
             ("3", "fetch, decode, write the cache", "through HTTP / PoliMiAPI", p["accent"]),
             ("4", "publish, then record", "DataStatus and the FreshnessCoordinator", p["accent2"])]
    for i, (n, title, detail, colour) in enumerate(order):
        y = 172 + i * 56
        b += box(24, y, 640, 44, p, fill=p["surface"], stroke=p["surfaceLine"], r=10, width=1)
        b += f'<circle cx="48" cy="{y + 22}" r="13" fill="{colour}"/>'
        b += label(48, y + 27, n, p, 13, 700, p["onAccent"], anchor="middle")
        b += label(72, y + 21, title, p, 13.5, 650)
        b += label(72, y + 36, detail, p, 11, 400, p["muted"])

    b += box(692, 172, 284, 156, p, fill=p["band"], stroke=p["warn"], width=1.6, dash="6 5")
    b += label(712, 198, "When a refresh fails", p, 13.5, 700, p["warn"])
    for i, text in enumerate(["the cached value stays published,",
                              "the failure is recorded beside it,",
                              "and the screen says how old it is."]):
        b += label(712, 222 + i * 19, text, p, 11.5, 400, p["ink"])
    b += label(712, 296, "An empty screen says less", p, 11.5, 600, p["muted"])
    b += label(712, 313, "than a stale one with a date on it.", p, 11.5, 600, p["muted"])
    b += line(664, 250, 688, 250, p, p["warn"], "no")

    b += box(24, 366, 952, 74, p, fill=p["surface"], stroke=p["surfaceLine"], r=12, width=1)
    b += label(44, 393, "Writing goes the other way", p, 13.5, 700, p["accent"])
    b += label(44, 414, "PendingChanges applies the change at once through OptimisticFlags, so the screen "
                        "updates under the finger,", p, 11.5, 400, p["muted"])
    b += label(44, 430, "and queues the real request in the ActionQueue, which sends it when the network "
                        "comes back.", p, 11.5, 400, p["muted"])
    return svg(1000, 452, b, "A load through the Store pipeline, what happens when it fails, "
                             "and how a write goes the other way.")


def oauth(p):
    lanes = [("The app", p["accent"]), ("AuthWebView", p["purple"]),
             ("oauthidp.polimi.it", p["warn"]), ("TokenStore", p["good"])]
    w, top, bottom = 1000, 76, 396
    b = arrow_defs(p) + arrow_defs(p, "g", p["good"])
    xs = [130, 360, 620, 880]
    for (name, colour), x in zip(lanes, xs):
        tw = len(name) * 7.2 + 28
        b += box(x - tw / 2, 28, tw, 34, p, fill=p["band"], stroke=colour, r=8, width=1.6)
        b += label(x, 50, name, p, 12.5, 700, p["ink"], anchor="middle")
        b += f'<path d="M{x},{top} L{x},{bottom}" stroke="{p["line"]}" stroke-width="1.4" ' \
             f'stroke-dasharray="5 5"/>'

    msgs = [(0, 1, "open the provider's own page", 108, False),
            (1, 2, "credentials, SPID or CIE — never through the app", 148, False),
            (2, 1, "redirect to redirectURI?code=…", 196, True),
            (1, 3, "exchange the code", 236, False),
            (3, 2, "token request", 276, False),
            (2, 3, "access + refresh pair", 316, True),
            (3, 0, "signed in", 360, True)]
    for a, z, text, y, back in msgs:
        x1, x2 = xs[a], xs[z]
        colour = p["good"] if back else p["muted"]
        b += line(x1, y, x2, y, p, colour, "g" if back else "a")
        mid = (x1 + x2) / 2
        b += box(mid - (len(text) * 5.6 + 16) / 2, y - 26, len(text) * 5.6 + 16, 20, p,
                 fill=p["surface"], stroke="none", r=6, width=0)
        b += label(mid, y - 11, text, p, 11.5, 550, p["ink"], anchor="middle")

    b += box(24, 416, 952, 100, p, fill=p["band"], stroke=p["good"], width=1.6, r=12)
    b += label(44, 444, "TokenStore is an actor, and that is the point", p, 13.5, 700, p["good"])
    b += label(44, 466, "The Politecnico rotates the refresh token. Two concurrent refreshes would present "
                        "a token the other has already", p, 11.5, 400, p["ink"])
    b += label(44, 483, "invalidated and end the session — so the first request starts the refresh and the "
                        "rest await the same task.", p, 11.5, 400, p["ink"])
    b += label(44, 504, "A transport failure leaves the pair alone. Only a refusal from the provider clears it.",
               p, 11.5, 600, p["muted"])
    return svg(1000, 528, b, "The OAuth sign-in as a sequence between the app, the web view, "
                             "the identity provider and the token store.")


def widgets(p):
    b = arrow_defs(p) + arrow_defs(p, "acc", p["accent"]) + arrow_defs(p, "g", p["good"])
    b += box(24, 40, 300, 150, p, fill=p["band"], stroke=p["accent"], width=1.6)
    b += label(44, 68, "The app", p, 15, 700, p["accent"])
    for i, text in enumerate(["learns something new", "writes a snapshot",
                              "asks WidgetKit to reload"]):
        b += label(44, 96 + i * 26, f"{i + 1}.  {text}", p, 12, 500 if i else 600)
    c, _ = chip(44, 152, "WidgetReloader", p, ink=p["ink"])
    b += c

    b += box(392, 30, 216, 170, p, fill=p["surface"], stroke=p["accent"], width=2, dash="7 5")
    b += label(500, 60, "OfflineStore", p, 15, 700, p["accent"], anchor="middle")
    b += label(500, 80, "app-group container", p, 11.5, 500, p["muted"], anchor="middle")
    for i, text in enumerate(["agenda", "career", "free rooms", "current lesson"]):
        c, w = chip(500 - (len(text) * 12 * 0.60 + 22) / 2, 98 + i * 26, text, p, ink=p["ink"])
        b += c
    b += line(330, 112, 386, 112, p, p["accent"], "acc")
    b += label(358, 104, "writes", p, 11, 600, p["accent"], anchor="middle")

    reads = [("NextLectureWidget", "the next lesson, its room, the countdown"),
             ("TodayWidget", "the day as a list"),
             ("CareerWidget", "the average and the credits"),
             ("FreeRoomsWidget", "free now, by campus"),
             ("LectureLiveActivity", "Lock Screen and Dynamic Island")]
    for i, (name, detail) in enumerate(reads):
        y = 24 + i * 62
        b += box(676, y, 300, 50, p, fill=p["band"], stroke=p["accent2"], width=1.4, r=10)
        b += label(692, y + 22, name, p, 12.5, 700)
        b += label(692, y + 38, detail, p, 10.5, 400, p["muted"])
        b += line(612, 112, 670, y + 25, p, p["accent2"], "a", width=1.2)

    b += box(24, 214, 584, 112, p, fill=p["band"], stroke=p["good"], width=1.6, dash="6 5")
    b += label(44, 242, "No token, no network, no waking the app", p, 13.5, 700, p["good"])
    b += label(44, 266, "A widget only ever reads. A timeline can be built with the app not running,",
               p, 11.5, 400, p["ink"])
    b += label(44, 283, "and a widget that finds nothing draws the sample data — so a freshly placed",
               p, 11.5, 400, p["ink"])
    b += label(44, 300, "widget is never blank.", p, 11.5, 400, p["ink"])
    b += label(44, 318, "Everything outside — Siri, Shortcuts, a control, a notification — lands "
                        "through AppDestination.", p, 11, 600, p["muted"])
    return svg(1000, 340, b, "The app writes snapshots into the app-group OfflineStore; "
                             "the widgets and the Live Activity only read from it.")


def flavor(p):
    base = "#0F3D6E"
    acc = derived(base, -0.08, 0.9, 0.85)
    ext = derived(base, -0.18, 0.95, 0.7)
    b = arrow_defs(p) + arrow_defs(p, "acc", p["accent"])
    b += label(24, 34, "One colour becomes the palette", p, 15, 700, p["accent"])
    b += label(24, 54, "Flavor.derived(hueShift:saturation:brightness:), from the Politecnico's own navy",
               p, 11.5, 400, p["muted"])

    roles = [("Main", base, "the colour the student picked", None),
             ("Accent", acc, "hue −0.08 · sat ×0.90 · bri ×0.85", "controls and marks"),
             ("Extra", ext, "hue −0.18 · sat ×0.95 · bri ×0.70", "a further, darker step")]
    for i, (name, colour, formula, use) in enumerate(roles):
        x = 24 + i * 246
        b += box(x, 74, 222, 116, p, fill=p["surface"], stroke=p["surfaceLine"], r=12, width=1)
        b += f'<rect x="{x + 14}" y="{88}" width="70" height="70" rx="16" fill="{colour}"/>'
        b += label(x + 98, 108, name, p, 14, 700)
        b += label(x + 98, 126, colour, p, 11.5, 600, p["muted"], mono=True)
        b += label(x + 14, 178, formula, p, 10, 500, p["muted"], mono=True)
        if use:
            b += label(x + 98, 146, use, p, 10.5, 400, p["muted"])
        if i:
            b += line(x - 22, 124, x - 6, 124, p, p["accent"], "acc")

    b += box(762, 74, 214, 116, p, fill=p["band"], stroke=p["warn"], r=12, width=1.6, dash="6 5")
    b += label(778, 100, "A grey only deepens", p, 12.5, 700, p["warn"])
    for i, text in enumerate(["Under 0.12 saturation there is", "no hue worth moving along, and",
                              "spreading one would invent a", "colour nobody picked."]):
        b += label(778, 122 + i * 16, text, p, 10.5, 400, p["ink"])

    b += label(24, 232, "FlavorRamp — deep to pale across a sixth of the wheel", p, 14, 700, p["accent"])
    b += label(24, 251, "A page hands out steps by position, so a settings page's tiles and a course's "
                        "marks stay in the look's own family.", p, 11.5, 400, p["muted"])
    strip = ramp(base, 8)
    for i, colour in enumerate(strip):
        x = 24 + i * 119
        b += f'<rect x="{x}" y="266" width="111" height="54" rx="10" fill="{colour}"/>'
        b += label(x + 55, 338, colour, p, 10, 600, p["muted"], anchor="middle", mono=True)
    b += label(24, 358, "0 — deepest", p, 10.5, 600, p["muted"])
    b += label(976, 358, "1 — palest", p, 10.5, 600, p["muted"], anchor="end")
    b += label(24, 382, "Each step is then nudged until it clears the page it is drawn on, so a dark look "
                        "never draws near-black on near-black.", p, 11, 500, p["muted"])
    return svg(1000, 398, b, "Accent and Extra derived from Main, and the ramp a page hands out "
                             "its colours from.")


def diagnostics(p):
    b = arrow_defs(p) + arrow_defs(p, "g", p["good"]) + arrow_defs(p, "w", p["warn"])
    b += box(24, 48, 636, 330, p, fill=p["band"], stroke=p["good"], width=2, dash="8 5")
    b += label(44, 78, "Stays on this device", p, 15, 700, p["good"])
    b += label(44, 98, "No analytics service, no crash reporter, nothing sent on its own.",
               p, 11.5, 400, p["muted"])

    items = [("DiagnosticsCollector", "session, scopes, WeBeep, queue, background runs", p["accent"]),
             ("PerformanceMonitor", "MetricKit's daily payloads and hang reports", p["accent2"]),
             ("ReportArchive", "those reports, on disk", p["accent2"]),
             ("StorageAudit", "what the app is holding, by kind", p["purple"]),
             ("DiagnosticsLog", "background runs and their outcomes", p["purple"])]
    for i, (name, detail, colour) in enumerate(items):
        y = 116 + i * 50
        b += box(44, y, 596, 40, p, fill=p["surface"], stroke=colour, r=10, width=1.4)
        b += f'<rect x="44" y="{y}" width="5" height="40" rx="2.5" fill="{colour}"/>'
        b += label(64, y + 18, name, p, 12.5, 700, mono=True)
        b += label(64, y + 33, detail, p, 10.5, 400, p["muted"])

    b += box(700, 48, 276, 120, p, fill=p["surface"], stroke=p["warn"], r=12, width=1.6)
    b += label(720, 76, "ConnectionProbe", p, 13, 700, p["warn"], mono=True)
    b += label(720, 98, "The one part that reaches out.", p, 11, 500, p["ink"])
    b += label(720, 116, "Asks each service whether it is", p, 11, 400, p["muted"])
    b += label(720, 132, "there, with no credentials. A 404", p, 11, 400, p["muted"])
    b += label(720, 148, "counts as reachable.", p, 11, 400, p["muted"])
    b += line(666, 108, 694, 108, p, p["warn"], "w")

    b += box(700, 196, 276, 108, p, fill=p["surface"], stroke=p["good"], r=12, width=1.6)
    b += label(720, 224, "DiagnosticsReport", p, 13, 700, p["good"], mono=True)
    b += label(720, 246, "Plain text, to attach to a report.", p, 11, 500, p["ink"])
    b += label(720, 264, "The matricola only if asked.", p, 11, 400, p["muted"])
    b += label(720, 282, "Never a token or a password —", p, 11, 400, p["muted"])
    b += label(720, 298, "stripped even out of an error.", p, 11, 400, p["muted"])
    b += line(666, 250, 694, 250, p, p["good"], "g")

    b += box(700, 332, 276, 46, p, fill=p["band"], stroke=p["surfaceLine"], r=12, width=1)
    b += label(838, 352, "Leaves the device only when", p, 11, 600, p["ink"], anchor="middle")
    b += label(838, 368, "the student shares it.", p, 11, 600, p["ink"], anchor="middle")
    b += line(838, 308, 838, 328, p, p["muted"], "a")
    return svg(1000, 396, b, "What the app records about itself, and the two things that ever "
                             "cross the device's edge.")


DIAGRAMS = {"layers": layers, "store-pipeline": pipeline, "oauth-flow": oauth,
            "widget-dataflow": widgets, "flavor-ramp": flavor, "diagnostics-map": diagnostics}

OUT.mkdir(parents=True, exist_ok=True)
for name, make in DIAGRAMS.items():
    for suffix, palette in (("", LIGHT), ("~dark", DARK)):
        path = OUT / f"{name}{suffix}.svg"
        path.write_text(make(palette), encoding="utf-8")
        print(path.name, path.stat().st_size, "bytes")
