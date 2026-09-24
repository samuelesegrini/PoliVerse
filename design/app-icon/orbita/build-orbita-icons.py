import math, random
import pathlib, os
D=str(pathlib.Path(__file__).parent)+"/out/"; os.makedirs(D, exist_ok=True)
HEAD='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
CLIP='<clipPath id="m"><rect width="1024" height="1024" rx="228"/></clipPath>\n'
def blurf(i,s): return f'<filter id="{i}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="{s}"/></filter>\n'
NOISE='<filter id="nz" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" seed="4"/><feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.9 -0.35"/></filter>\n'
def soft(i,c,peak=1.0,mid=0.55):
    """A radial gradient over the shape's own box: the colour at the centre, nothing at the edge.
    Stands in for a Gaussian blur, which Icon Composer does not draw."""
    return (f'<radialGradient id="{i}" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{c}" stop-opacity="{peak}"/>'
            f'<stop offset="{mid}" stop-color="{c}" stop-opacity="{peak*0.5:.2f}"/><stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>\n')
def attrs(d): return " ".join(f'{k.replace("_","-")}="{v}"' for k,v in d.items())

class Orbit:
    """One continuous ring: the part behind the planet is masked out, the planet is cut where the ring passes in front, and the ring is cut around the moon."""
    def __init__(s, uid="o", cx=512, cy=512, rx=400, ry=120, rot=-20, pr=215, ring_w=54, gap=14, moon_t=25, moon_r=76, moon_gap=12):
        s.__dict__.update(locals()); del s.__dict__["s"]
        s.R=f"rotate({rot} {cx} {cy})"
        s.full=f"M{cx-rx} {cy} A{rx} {ry} 0 1 1 {cx+rx} {cy} A{rx} {ry} 0 1 1 {cx-rx} {cy} Z"
        s.front=f"M{cx-rx} {cy} A{rx} {ry} 0 0 0 {cx+rx} {cy}"
        t=math.radians(moon_t); s.mx=cx+rx*math.cos(t); s.my=cy+ry*math.sin(t)
    def pt(s,deg):
        t=math.radians(deg); return (s.cx+s.rx*math.cos(t), s.cy+s.ry*math.sin(t))
    def defs(s):
        rr=s.pr+s.gap; big='x="-3000" y="-3000" width="7000" height="7000"'
        moon = f'<circle cx="{s.mx:.1f}" cy="{s.my:.1f}" r="{s.moon_r+s.moon_gap}" fill="#000"/>' if s.moon_r else ''
        return (f'<mask id="{s.uid}r" maskUnits="userSpaceOnUse" {big}><rect {big} fill="#fff"/>'
                f'<path d="M{s.cx-rr} {s.cy} A{rr} {rr} 0 0 1 {s.cx+rr} {s.cy} Z" fill="#000"/>{moon}</mask>\n'
                f'<mask id="{s.uid}p" maskUnits="userSpaceOnUse" {big}><rect {big} fill="#fff"/>'
                f'<g transform="{s.R}"><path d="{s.front}" fill="none" stroke="#000" stroke-width="{s.ring_w+2*s.gap}"/></g></mask>\n')
    def ring(s, *layers, extra=""):
        p="".join(f'<path d="{s.full}" fill="none" {attrs(l)}/>' for l in layers)
        return f'<g transform="{s.R}"><g mask="url(#{s.uid}r)">{p}{extra}</g></g>'
    def trail(s, paint, w, start=80):
        x1,y1=s.pt(start); x2,y2=s.mx,s.my
        return f'<path d="M{x1:.1f} {y1:.1f} A{s.rx} {s.ry} 0 0 0 {x2:.1f} {y2:.1f}" fill="none" stroke="{paint}" stroke-width="{w}"/>'
    def trail_grad(s, gid, color):
        x1,y1=s.pt(80)
        return f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{x1:.1f}" y1="{y1:.1f}" x2="{s.mx:.1f}" y2="{s.my:.1f}"><stop offset="0" stop-color="{color}" stop-opacity="0"/><stop offset="1" stop-color="{color}" stop-opacity="0.95"/></linearGradient>\n'
    def planet(s, content): return f'<g mask="url(#{s.uid}p)">{content}</g>'
    def moon(s, content): return f'<g transform="{s.R}"><g transform="translate({s.mx:.1f} {s.my:.1f})">{content}</g></g>'

def sc(k, body, cx=512, cy=512): return f'<g transform="translate({cx} {cy}) scale({k}) translate(-512 -512)">{body}</g>'
def svg(name, defs, body, clip=True):
    open(D+name,"w").write(HEAD+'<defs>\n'+(CLIP if clip else '')+defs+'</defs>\n'+(f'<g clip-path="url(#m)">\n{body}\n</g>' if clip else body)+'\n</svg>\n')
def sparkle(x,y,r,op=1,f=None):
    fa=f' filter="url(#{f})"' if f else ''
    return f'<path transform="translate({x} {y}) scale({r/80:.3f})" d="M0 -80 C 6 -12 12 -6 80 0 C 12 6 6 12 0 80 C -6 12 -12 6 -80 0 C -12 -6 -6 -12 0 -80 Z" fill="#FFFFFF" fill-opacity="{op}"{fa}/>'
MOONG='<radialGradient id="mo" cx="0.34" cy="0.28" r="0.85"><stop offset="0" stop-color="{a}"/><stop offset="0.45" stop-color="{b}"/><stop offset="1" stop-color="{c}"/></radialGradient>\n'
HL='<ellipse cx="-26" cy="-31" rx="28" ry="17" fill="#FFFFFF" fill-opacity="0.75"/>'

# ---------- Orbita: glass family ----------
def glass(name, bg, glow, pl, rf, moon, trail, stars=True, clear=False):
    o=Orbit()
    d=o.defs()
    if bg: d+=f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{bg[0]}"/><stop offset="1" stop-color="{bg[1]}"/></linearGradient>\n'
    d+=f'<radialGradient id="gl" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#3E84B4" stop-opacity="{glow}"/><stop offset="1" stop-color="#3E84B4" stop-opacity="0"/></radialGradient>\n'
    d+=f'<radialGradient id="pl" cx="0.36" cy="0.3" r="0.8"><stop offset="0" stop-color="{pl[0]}"/><stop offset="0.42" stop-color="{pl[1]}"/><stop offset="1" stop-color="{pl[2]}"/></radialGradient>\n'
    d+=f'<linearGradient id="rf" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{rf[0]}"/><stop offset="0.55" stop-color="{rf[1]}"/><stop offset="1" stop-color="{rf[2]}"/></linearGradient>\n'
    d+=MOONG.format(a=moon[0],b=moon[1],c=moon[2])+o.trail_grad("tr",trail)
    b=''
    if bg: b+='<rect width="1024" height="1024" fill="url(#bg)"/>'
    if glow: b+='<circle cx="512" cy="512" r="400" fill="url(#gl)"/>'
    if stars: b+='<circle cx="196" cy="226" r="6" fill="#FFFFFF" fill-opacity="0.7"/><circle cx="824" cy="176" r="4" fill="#FFFFFF" fill-opacity="0.55"/><circle cx="170" cy="780" r="4" fill="#FFFFFF" fill-opacity="0.45"/>'
    pc='<circle cx="512" cy="512" r="215" fill="url(#pl)"'+(' stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="8"' if clear else '')+'/>'
    if not clear: pc+='<path d="M714 585.5 A215 215 0 0 1 438.5 714" fill="none" stroke="#A9D4F5" stroke-opacity="0.45" stroke-width="10" stroke-linecap="round"/>'
    pc+='<ellipse cx="438" cy="410" rx="84" ry="44" fill="#FFFFFF" fill-opacity="0.3" transform="rotate(-32 438 410)"/>'
    b+=o.planet(pc)+o.ring({"stroke":"url(#rf)","stroke_width":54}, extra=o.trail("url(#tr)",54))
    b+=o.moon('<circle r="76" fill="url(#mo)"/>'+HL)
    svg(name,d,b,clip=bool(bg))
    return o
glass("hero.svg",("#15406A","#040C18"),0.55,("#9CD0F2","#2E6E99","#0A2640"),("#B7CADC","#FFFFFF","#9FB6CC"),("#FFE7B4","#F2A93B","#A9650C"),"#F2A93B")
glass("dark.svg",("#0A111C","#000000"),0.3,("#7FB6E0","#245A80","#081D31"),("#8FA6BC","#DCE6F0","#7F97AE"),("#FFE0A0","#E89A2C","#8E540A"),"#E89A2C",stars=False)
glass("clear.svg",None,0,("rgba(255,255,255,0.55)","rgba(255,255,255,0.28)","rgba(255,255,255,0.12)"),("#FFFFFF","#FFFFFF","#EAF2FA"),("#FFFFFF","#FFFFFF","#E6EEF6"),"#FFFFFF",stars=False,clear=True)
glass("tinted.svg",("#0B2A30","#030C0E"),0.25,("#6FC3CE","#1D5761","#082126"),("#7FCBD5","#D8F6FA","#6BB5BF"),("#FFFFFF","#EAFBFF","#8FD2DB"),"#CFF3F8",stars=False)

# transparent mark for the brand board
o=Orbit()
svg("mark.svg", o.defs()+'<radialGradient id="pl" cx="0.36" cy="0.3" r="0.8"><stop offset="0" stop-color="#9CD0F2"/><stop offset="0.42" stop-color="#2E6E99"/><stop offset="1" stop-color="#0A2640"/></radialGradient>\n'+MOONG.format(a="#FFE7B4",b="#F2A93B",c="#A9650C"),
    o.planet('<circle cx="512" cy="512" r="215" fill="url(#pl)"/><ellipse cx="438" cy="410" rx="84" ry="44" fill="#FFFFFF" fill-opacity="0.3" transform="rotate(-32 438 410)"/>')
    +o.ring({"stroke":"#E8EEF4","stroke_width":54})+o.moon('<circle r="76" fill="url(#mo)"/>'+HL), clip=False)

# Piatto
o=Orbit(ring_w=64)
svg("piatto.svg", o.defs()+'<clipPath id="pc"><circle cx="512" cy="512" r="220"/></clipPath>\n',
 '<rect width="1024" height="1024" fill="#0F3D66"/>'
 +o.planet('<circle cx="512" cy="512" r="220" fill="#F4F1EA"/><g clip-path="url(#pc)"><circle cx="600" cy="600" r="240" fill="#DCD5C6"/></g>')
 +o.ring({"stroke":"#8EC3EA","stroke_width":64})+o.moon('<circle r="70" fill="#F2A93B"/><circle cx="-18" cy="-18" r="20" fill="#FFC766"/>'))
# Ravvicinato
o=Orbit(cx=380,cy=760,rx=900,ry=230,rot=-30,pr=520,ring_w=70,gap=18,moon_t=-50,moon_r=112,moon_gap=16)
svg("vicino.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1B4F80"/><stop offset="1" stop-color="#061322"/></linearGradient>\n'
 '<radialGradient id="pl" cx="0.38" cy="0.22" r="0.8"><stop offset="0" stop-color="#9CD0F2"/><stop offset="0.4" stop-color="#2E6E99"/><stop offset="1" stop-color="#08203A"/></radialGradient>\n'
 '<linearGradient id="rf" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#9FB6CC"/><stop offset="0.6" stop-color="#FFFFFF"/><stop offset="1" stop-color="#B7CADC"/></linearGradient>\n'
 +MOONG.format(a="#FFE7B4",b="#F2A93B",c="#A9650C"),
 '<rect width="1024" height="1024" fill="url(#bg)"/>'
 +o.planet('<circle cx="380" cy="760" r="520" fill="url(#pl)"/><ellipse cx="300" cy="340" rx="140" ry="52" fill="#FFFFFF" fill-opacity="0.25" transform="rotate(-28 300 340)"/>')
 +o.ring({"stroke":"url(#rf)","stroke_width":70})+o.moon('<circle r="112" fill="url(#mo)"/><ellipse cx="-38" cy="-44" rx="40" ry="24" fill="#FFFFFF" fill-opacity="0.75"/>'))
# Chiaro
o=Orbit(ring_w=66)
svg("chiaro.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#DCE6F1"/></linearGradient>\n'
 '<radialGradient id="pl" cx="0.36" cy="0.3" r="0.8"><stop offset="0" stop-color="#4F95C6"/><stop offset="0.45" stop-color="#0F4A74"/><stop offset="1" stop-color="#00223A"/></radialGradient>\n'
 +MOONG.format(a="#FFE7B4",b="#F2A93B",c="#A9650C")+blurf("b24",24),
 '<rect width="1024" height="1024" fill="url(#bg)"/><ellipse cx="512" cy="800" rx="300" ry="60" fill="#0B2A48" fill-opacity="0.22" filter="url(#b24)"/>'
 +o.planet('<circle cx="512" cy="512" r="215" fill="url(#pl)"/><ellipse cx="438" cy="410" rx="84" ry="44" fill="#FFFFFF" fill-opacity="0.3" transform="rotate(-32 438 410)"/>')
 +o.ring({"stroke":"#0F4A74","stroke_width":66},{"stroke":"#FFFFFF","stroke_width":46})
 +o.moon('<circle r="70" fill="url(#mo)"/><ellipse cx="-24" cy="-28" rx="24" ry="14" fill="#FFFFFF" fill-opacity="0.75"/>'))
# Cromo
o=Orbit()
svg("cromo.svg", o.defs()
 +'<radialGradient id="bg" cx="0.5" cy="0.35" r="0.8"><stop offset="0" stop-color="#2A2A2C"/><stop offset="1" stop-color="#0B0B0C"/></radialGradient>\n'
 '<radialGradient id="pl" cx="0.35" cy="0.28" r="0.85"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.35" stop-color="#C4C4C4"/><stop offset="0.7" stop-color="#5A5A5A"/><stop offset="1" stop-color="#9A9A9A"/></radialGradient>\n'
 '<linearGradient id="cr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.45" stop-color="#8A8A8A"/><stop offset="0.55" stop-color="#E6E6E6"/><stop offset="1" stop-color="#7A7A7A"/></linearGradient>\n'
 +MOONG.format(a="#FFE7B4",b="#F2A93B",c="#A9650C"),
 '<rect width="1024" height="1024" fill="url(#bg)"/>'
 +o.planet('<circle cx="512" cy="512" r="215" fill="url(#pl)"/>')
 +o.ring({"stroke":"url(#cr)","stroke_width":54})+o.moon('<circle r="76" fill="url(#mo)"/>'+HL))
# Layers
o=Orbit()
open(D+"layer1-sfondo.svg","w").write(HEAD+'<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#15406A"/><stop offset="1" stop-color="#040C18"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>\n</svg>\n')
svg("layer2-pianeta.svg", o.defs(), o.planet('<circle cx="512" cy="512" r="215" fill="#2E6E99"/>'), clip=False)
svg("layer3-anello.svg", o.defs()+o.trail_grad("tr","#F2A93B"), o.ring({"stroke":"#E8EEF4","stroke_width":54}, extra=o.trail("url(#tr)",54)), clip=False)
svg("layer4-luna.svg", o.defs(), o.moon('<circle r="76" fill="#F2A93B"/>'), clip=False)

# ---------- Grain ----------
# Noise is a filter, which Icon Composer does not draw either: it is rendered
# once to a PNG (grain.png, next to this script) to add as an image layer.

# ---------- Premium ----------
P="p-"
# Neon
o=Orbit(ring_w=78,gap=12)
svg(P+"01-neon.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0A0B2E"/><stop offset="1" stop-color="#2B0B45"/></linearGradient>\n'
 '<linearGradient id="rg" gradientUnits="userSpaceOnUse" x1="112" y1="512" x2="912" y2="512"><stop offset="0" stop-color="#2B3BFF"/><stop offset="0.3" stop-color="#22D3F5"/><stop offset="0.48" stop-color="#C9F6FF"/><stop offset="0.52" stop-color="#7A2BD6"/><stop offset="0.8" stop-color="#FF4FD8"/><stop offset="1" stop-color="#FFC2F0"/></linearGradient>\n'
 '<radialGradient id="mg" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.5" stop-color="#FFC2F0"/><stop offset="1" stop-color="#FF4FD8"/></radialGradient>\n'
 +soft("ng","#5B3CFF",0.4)+soft("nm","#FF8BE6",0.8,0.7),
 '<rect width="1024" height="1024" fill="url(#bg)"/><circle cx="512" cy="512" r="440" fill="url(#ng)"/>'
 # The glow as wider, fainter strokes under the sharp one.
 +o.planet('<circle cx="512" cy="512" r="215" fill="#150B34"/><circle cx="512" cy="512" r="215" fill="none" stroke="#7B6BFF" stroke-opacity="0.18" stroke-width="40"/><circle cx="512" cy="512" r="215" fill="none" stroke="#7B6BFF" stroke-opacity="0.35" stroke-width="22"/><circle cx="512" cy="512" r="215" fill="none" stroke="#9C8FFF" stroke-width="10"/>')
 +o.ring({"stroke":"#FF4FD8","stroke_opacity":0.12,"stroke_width":150},{"stroke":"#FF4FD8","stroke_opacity":0.2,"stroke_width":116},{"stroke":"#F4E9FF","stroke_width":78},{"stroke":"url(#rg)","stroke_width":58})
 +o.moon('<circle r="124" fill="url(#nm)"/><circle r="76" fill="url(#mg)" stroke="#F4E9FF" stroke-width="10"/>')
 +sparkle(790,250,120,0.25)+sparkle(790,250,86)+sparkle(250,770,88,0.25)+sparkle(250,770,62))
# Spettro
blobs=[(400,380,170,"#2BE0A0"),(640,390,150,"#3A7BFF"),(700,560,160,"#FFD23F"),(600,700,150,"#FF3B6B"),(380,660,160,"#9B5CFF")]
# No blur filters: Icon Composer does not draw them and shows every blob as a
# hard disc. Each glow is a radial gradient fading to nothing instead.
def glow(i,x,y,r,c,spread,peak):
    return (f'<radialGradient id="g{i}" cx="{x}" cy="{y}" r="{r*spread:.0f}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{c}" stop-opacity="{peak}"/><stop offset="0.55" stop-color="{c}" stop-opacity="{peak*0.6:.2f}"/>'
            f'<stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>\n')
outer="".join(glow(f"o{i}",x,y,r,c,1.5,0.55) for i,(x,y,r,c) in enumerate(blobs))
inner="".join(glow(f"i{i}",x,y,r,c,1.3,1) for i,(x,y,r,c) in enumerate(blobs))
dots=lambda k,spread: "".join(f'<circle cx="{x}" cy="{y}" r="{r*spread:.0f}" fill="url(#g{k}{i})"/>' for i,(x,y,r,c) in enumerate(blobs))
o=Orbit(ring_w=76,gap=10,moon_r=70)
svg(P+"02-spettro.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#121D3A"/><stop offset="1" stop-color="#070D1E"/></linearGradient>\n'
 '<clipPath id="cp"><circle cx="512" cy="512" r="215"/></clipPath>\n'+outer+inner
 +'<radialGradient id="hl" cx="470" cy="450" r="110" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>\n'
 +'<radialGradient id="mg" cx="0" cy="0" r="96" gradientUnits="userSpaceOnUse"><stop offset="0.6" stop-color="#FFFFFF" stop-opacity="0.7"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>\n',
 '<rect width="1024" height="1024" fill="url(#bg)"/>'
 +dots("o",1.5)
 +o.planet(f'<g clip-path="url(#cp)"><rect x="297" y="297" width="430" height="430" fill="#4A9BFF"/>{dots("i",1.3)}<circle cx="470" cy="450" r="110" fill="url(#hl)"/></g><circle cx="512" cy="512" r="214" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="4"/>')
 +o.ring({"stroke":"#FFFFFF","stroke_opacity":0.45,"stroke_width":76},{"stroke":"#0C1530","stroke_width":56})
 +o.moon('<circle r="96" fill="url(#mg)"/><circle r="68" fill="#FFFFFF"/>'))
# Pelle
o=Orbit(gap=14,moon_r=74)
def lmark(c): return o.planet(f'<circle cx="512" cy="512" r="215" fill="{c}"/>')+o.ring({"stroke":c,"stroke_width":54})
svg(P+"03-pelle.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7A818D"/><stop offset="1" stop-color="#5A606B"/></linearGradient>\n'
 '<radialGradient id="br" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#FFE9B0"/><stop offset="0.5" stop-color="#C8912F"/><stop offset="1" stop-color="#6E4A12"/></radialGradient>\n',
 '<rect width="1024" height="1024" fill="url(#bg)"/>'
 '<rect x="58" y="62" width="908" height="908" rx="176" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="12" stroke-dasharray="36 22" stroke-linecap="round"/>'
 '<rect x="58" y="58" width="908" height="908" rx="176" fill="none" stroke="#1B2029" stroke-width="12" stroke-dasharray="36 22" stroke-linecap="round"/>'
 '<circle cx="512" cy="518" r="342" fill="#FFFFFF" fill-opacity="0.12"/><circle cx="512" cy="512" r="340" fill="#242A35"/>'
 '<circle cx="512" cy="506" r="334" fill="none" stroke="#000000" stroke-opacity="0.12" stroke-width="16"/><circle cx="512" cy="506" r="337" fill="none" stroke="#000000" stroke-opacity="0.22" stroke-width="6"/>'
 +sc(0.78,'<g transform="translate(0 7)" opacity="0.45">'+lmark("#000000")+'</g>'+lmark("#6E7581")
     +o.moon('<circle r="74" fill="url(#br)"/><ellipse cx="-22" cy="-26" rx="26" ry="15" fill="#FFFFFF" fill-opacity="0.6"/>')))
# Olografico
hblobs=[(200,200,300,"#BFE8FF"),(820,180,280,"#F2B8FF"),(860,700,300,"#B3C2FF"),(180,820,300,"#FFB8C6"),(520,900,260,"#A6F0E6"),(330,560,200,"#FFF3B8")]
holo=('<rect width="1024" height="1024" fill="#EDF3FF"/>'
 +"".join(f'<circle cx="{x}" cy="{y}" r="{r*1.4:.0f}" fill="url(#hb{i})"/>' for i,(x,y,r,c) in enumerate(hblobs))
 +'<rect width="1024" height="1024" fill="url(#sh)"/>')
o=Orbit(pr=226,ring_w=62,gap=12,moon_r=78)
svg(P+"04-olografico.svg", o.defs()
 +'<linearGradient id="sh" x1="0" y1="0" x2="1" y2="1"><stop offset="0.3" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0.85"/><stop offset="0.6" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>\n'
 '<clipPath id="cp"><circle cx="512" cy="512" r="215"/></clipPath>\n'+"".join(soft(f"hb{i}",c,1,0.6) for i,(x,y,r,c) in enumerate(hblobs))+f'<g id="h">{holo}</g>\n',
 '<use href="#h" xlink:href="#h"/><rect x="52" y="52" width="920" height="920" rx="190" fill="none" stroke="#14101E" stroke-width="24"/>'
 +o.planet('<g clip-path="url(#cp)"><g transform="rotate(180 512 512)"><use href="#h" xlink:href="#h"/></g></g><circle cx="512" cy="512" r="215" fill="none" stroke="#14101E" stroke-width="22"/>')
 +o.ring({"stroke":"#14101E","stroke_width":62})
 +o.moon('<circle r="78" fill="#14101E"/><ellipse cx="-22" cy="-26" rx="24" ry="14" fill="#FFFFFF" fill-opacity="0.55"/>'))
# Iperspazio
random.seed(7); st=""
for i in range(56):
    a=random.uniform(0,2*math.pi); r1=random.uniform(290,560); L=random.uniform(60,280)
    w=random.uniform(3,7); op=random.uniform(0.35,0.9); c=random.choice(["#A8B6FF","#FFFFFF","#7F95FF"])
    st+=f'<line x1="{512+r1*math.cos(a):.1f}" y1="{512+r1*math.sin(a):.1f}" x2="{512+(r1+L)*math.cos(a):.1f}" y2="{512+(r1+L)*math.sin(a):.1f}" stroke="{c}" stroke-opacity="{op:.2f}" stroke-width="{w:.1f}" stroke-linecap="round"/>'
inner=""
for i in range(22):
    a=random.uniform(0,2*math.pi); r1=random.uniform(30,90); L=random.uniform(40,110)
    inner+=f'<line x1="{512+r1*math.cos(a):.1f}" y1="{512+r1*math.sin(a):.1f}" x2="{512+(r1+L)*math.cos(a):.1f}" y2="{512+(r1+L)*math.sin(a):.1f}" stroke="#6C7DFF" stroke-opacity="{random.uniform(.3,.8):.2f}" stroke-width="{random.uniform(2,5):.1f}" stroke-linecap="round"/>'
o=Orbit(pr=224,ring_w=58,moon_r=72)
svg(P+"05-iperspazio.svg", o.defs()
 +'<radialGradient id="bg" cx="0.5" cy="0.5" r="0.75"><stop offset="0" stop-color="#2A3DF0"/><stop offset="0.55" stop-color="#1422B8"/><stop offset="1" stop-color="#080C4E"/></radialGradient>\n'
 '<radialGradient id="pg" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#000324"/><stop offset="0.7" stop-color="#0B1270"/><stop offset="1" stop-color="#2233D8"/></radialGradient>\n'
 '<linearGradient id="wg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#C8CCF4"/></linearGradient>\n'
 +MOONG.format(a="#FFE7B4",b="#F2A93B",c="#A9650C")+'<clipPath id="cp"><circle cx="512" cy="512" r="210"/></clipPath>\n'+soft("ih","#F2A93B",0.7,0.65),
 '<rect width="1024" height="1024" fill="url(#bg)"/>'+st
 +o.planet(f'<circle cx="512" cy="512" r="224" fill="#FFFFFF"/><circle cx="512" cy="512" r="210" fill="url(#pg)"/><g clip-path="url(#cp)">{inner}</g>')
 +o.ring({"stroke":"url(#wg)","stroke_width":58})
 +o.moon('<circle r="118" fill="url(#ih)"/><circle r="72" fill="url(#mo)"/><ellipse cx="-22" cy="-28" rx="24" ry="14" fill="#FFFFFF" fill-opacity="0.75"/>'))
# Blueprint
kl=("".join(f'<line x1="{x}" y1="110" x2="{x}" y2="914"/>' for x in (196,828))+"".join(f'<line x1="110" y1="{y}" x2="914" y2="{y}"/>' for y in (196,828)))
o=Orbit(pr=221,ring_w=70,gap=12,moon_r=86)
svg(P+"06-blueprint.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#12A8FF"/><stop offset="1" stop-color="#0A62E4"/></linearGradient>\n'
 '<linearGradient id="pf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D4E9FF"/><stop offset="1" stop-color="#5AA4F5"/></linearGradient>\n',
 '<rect width="1024" height="1024" fill="url(#bg)"/><rect x="62" y="62" width="900" height="900" rx="178" fill="none" stroke="#FFFFFF" stroke-width="12"/>'
 f'<g stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="5" stroke-dasharray="18 14">{kl}<circle cx="512" cy="512" r="316" fill="none" stroke-opacity="0.4"/></g>'
 +sc(0.9, o.planet('<circle cx="512" cy="512" r="215" fill="url(#pf)" stroke="#FFFFFF" stroke-width="12"/>')
   +o.ring({"stroke":"#FFFFFF","stroke_width":70},{"stroke":"#8CC4FA","stroke_width":46},{"stroke":"#FFFFFF","stroke_width":8,"stroke_dasharray":"1 24","stroke_linecap":"round"})
   +o.moon('<circle r="80" fill="#FFD27A" stroke="#FFFFFF" stroke-width="12"/>')))
# Circuito
pins=[340,392,444,548,600,652]
def Pn(x,y,w,h): return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="url(#gd)"/>'
pin="".join(Pn(x,262,32,42)+Pn(x,720,32,42) for x in pins)+"".join(Pn(262,y,42,32)+Pn(720,y,42,32) for y in pins)
top=[(356,[(356,170),(230,170)]),(408,[(408,110)]),(460,[(460,-10)]),(564,[(564,130)]),(616,[(616,190),(760,190)]),(668,[(668,236),(880,236)])]
top2=[(356,[(356,210),(160,210)]),(408,[(408,-10)]),(460,[(460,150)]),(564,[(564,90)]),(616,[(616,-10)]),(668,[(668,170),(800,170),(800,100)])]
def traces(spec,rot):
    s=""
    for x,pts in spec:
        s+=f'<path d="M{x} 262 '+" ".join(f"L{a} {b}" for a,b in pts)+'" fill="none" stroke="#0A8A54" stroke-width="10" stroke-linejoin="round"/>'
        ex,ey=pts[-1]
        if ey>0: s+=f'<circle cx="{ex}" cy="{ey}" r="18" fill="#12C97C" stroke="#0A8A54" stroke-width="9"/>'
    return f'<g transform="rotate({rot} 512 512)">{s}</g>'
o=Orbit(gap=16,moon_r=74,moon_gap=16)
svg(P+"07-circuito.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1ADB8C"/><stop offset="1" stop-color="#0CB46C"/></linearGradient>\n'
 '<pattern id="st" width="28" height="28" patternUnits="userSpaceOnUse"><rect width="12" height="28" fill="#000000" fill-opacity="0.045"/></pattern>\n'
 '<linearGradient id="gd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFE68A"/><stop offset="1" stop-color="#D4A020"/></linearGradient>\n'
 '<linearGradient id="ch" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3C3D46"/><stop offset="1" stop-color="#25262C"/></linearGradient>\n',
 '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#st)"/>'
 +traces(top,0)+traces(top2,90)+traces(top,180)+traces(top2,270)+pin
 +'<rect x="284" y="310" width="456" height="456" rx="70" fill="#000000" fill-opacity="0.08"/><rect x="292" y="314" width="440" height="440" rx="62" fill="#000000" fill-opacity="0.12"/><rect x="300" y="318" width="424" height="424" rx="54" fill="#000000" fill-opacity="0.15"/><rect x="300" y="300" width="424" height="424" rx="54" fill="url(#ch)"/>'
 '<rect x="302" y="302" width="420" height="420" rx="52" fill="none" stroke="#FFFFFF" stroke-opacity="0.1" stroke-width="3"/>'
 +sc(0.4, o.planet('<circle cx="512" cy="512" r="215" fill="#C9CCD2"/>')+o.ring({"stroke":"#C9CCD2","stroke_width":54})+o.moon('<circle r="74" fill="url(#gd)"/>'))
)
# Cielo
cloud=('<g fill="url(#cl)"><ellipse cx="250" cy="930" rx="280" ry="160"/><ellipse cx="90" cy="840" rx="200" ry="140"/><ellipse cx="460" cy="990" rx="250" ry="140"/></g>'
 '<g fill="url(#cl2)"><ellipse cx="880" cy="140" rx="270" ry="140"/><ellipse cx="1000" cy="260" rx="210" ry="140"/></g>')
o=Orbit(pr=252,ring_w=112,gap=10,moon_r=104,moon_gap=10)
svg(P+"08-cielo.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0A84FF"/><stop offset="1" stop-color="#33C1FF"/></linearGradient>\n'
 '<linearGradient id="pf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#BDE6FF"/></linearGradient>\n'
 '<linearGradient id="wf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#D6F0FF"/></linearGradient>\n'+soft("cl","#FFFFFF",0.95,0.7)+soft("cl2","#FFFFFF",0.8,0.7)+soft("cs","#003A7A",0.35,0.75),
 '<rect width="1024" height="1024" fill="url(#bg)"/>'+cloud
 +'<circle cx="512" cy="528" r="300" fill="url(#cs)"/>'
 +sc(0.86, o.planet('<circle cx="512" cy="512" r="252" fill="#FFFFFF"/><circle cx="512" cy="512" r="224" fill="#1A8FD6"/><circle cx="512" cy="512" r="200" fill="url(#pf)"/>'
     '<rect x="540" y="400" width="34" height="78" rx="17" fill="#1A8FD6" transform="rotate(-8 557 439)"/><rect x="608" y="392" width="34" height="78" rx="17" fill="#1A8FD6" transform="rotate(-8 625 431)"/>'
     '<path d="M440 470 L470 444 Q500 540 600 520" fill="none" stroke="#1A8FD6" stroke-width="22" stroke-linecap="round" stroke-linejoin="round"/>')
   +o.ring({"stroke":"#FFFFFF","stroke_width":112},{"stroke":"#1A8FD6","stroke_width":76},{"stroke":"url(#wf)","stroke_width":50})
   +o.moon('<circle r="104" fill="#FFFFFF"/><circle r="84" fill="#1A8FD6"/><circle r="62" fill="#FFE9A8"/>'))
 +'<rect x="9" y="9" width="1006" height="1006" rx="219" fill="none" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="18"/>')
# Osservatorio
o=Orbit(gap=18,moon_gap=16)
svg(P+"09-osservatorio.svg", o.defs()
 +'<linearGradient id="sky" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2D5B8C"/><stop offset="0.42" stop-color="#9FB4C4"/><stop offset="0.68" stop-color="#F2A560"/><stop offset="1" stop-color="#E7C9A0"/></linearGradient>\n'
 '<linearGradient id="fr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F6F4F0"/><stop offset="1" stop-color="#D6D2CB"/></linearGradient>\n'
 '<radialGradient id="mt" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#F7EAD6"/><stop offset="0.6" stop-color="#BFA07C"/><stop offset="1" stop-color="#6E5A43"/></radialGradient>\n'
 '<radialGradient id="gl" cx="0.4" cy="0.35" r="0.7"><stop offset="0" stop-color="#4FA3E0"/><stop offset="0.45" stop-color="#3A3FB0"/><stop offset="0.7" stop-color="#5B2A9A"/><stop offset="1" stop-color="#07070F"/></radialGradient>\n'
 '<radialGradient id="mp" cx="0.36" cy="0.3" r="0.8"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#8FB6DD"/></radialGradient>\n'
 '<path id="tp" d="M600 390 a220 220 0 1 1 -0.1 0"/>\n'+soft("os","#2B1A08",0.5,0.8),
 '<rect width="1024" height="1024" fill="url(#fr)"/><rect x="74" y="74" width="876" height="876" rx="170" fill="url(#sky)"/>'
 '<rect x="74" y="74" width="876" height="876" rx="170" fill="none" stroke="#000000" stroke-opacity="0.12" stroke-width="8"/>'
 '<circle cx="610" cy="632" r="340" fill="url(#os)"/><circle cx="600" cy="610" r="300" fill="url(#mt)"/>'
 '<circle cx="600" cy="610" r="298" fill="none" stroke="#FFFFFF" stroke-opacity="0.6" stroke-width="5"/><circle cx="600" cy="610" r="250" fill="#1C1C1E"/>'
 '<text font-family="SF Mono, Menlo, monospace" font-size="24" letter-spacing="4" fill="#8E8E93"><textPath href="#tp" xlink:href="#tp" startOffset="4%">ORBITA · 50MM f/2.0</textPath></text>'
 '<circle cx="600" cy="610" r="200" fill="#0E0E10"/><circle cx="600" cy="610" r="176" fill="#2A2B30"/><circle cx="600" cy="610" r="160" fill="#111114"/><circle cx="600" cy="610" r="146" fill="url(#gl)"/>'
 +sc(0.24, o.planet('<circle cx="512" cy="512" r="215" fill="url(#mp)"/>')+o.ring({"stroke":"#F4F8FC","stroke_width":54})+o.moon('<circle r="76" fill="#F2A93B"/>'),600,610)
 +'<ellipse cx="548" cy="548" rx="44" ry="24" fill="#FFFFFF" fill-opacity="0.35" transform="rotate(-35 548 548)"/><circle cx="660" cy="680" r="10" fill="#FFFFFF" fill-opacity="0.35"/>')
# Morbido
o=Orbit(pr=230,ring_w=74,gap=14,moon_r=80)
svg(P+"10-morbido.svg", o.defs()
 +'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF8F63"/><stop offset="1" stop-color="#FF4B2E"/></linearGradient>\n'
 '<pattern id="gr" width="42" height="42" patternUnits="userSpaceOnUse"><path d="M42 0H0V42" fill="none" stroke="#FFFFFF" stroke-opacity="0.09" stroke-width="2"/></pattern>\n'
 '<radialGradient id="pl" cx="0.38" cy="0.3" r="0.8"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.6" stop-color="#FFE5DE"/><stop offset="1" stop-color="#FFB09C"/></radialGradient>\n'
 '<linearGradient id="rb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF1EC"/><stop offset="1" stop-color="#FFB7A4"/></linearGradient>\n'
 '<radialGradient id="mo" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#FFB19E"/><stop offset="1" stop-color="#E83A20"/></radialGradient>\n'+soft("ms","#8A1A08",0.45,0.6),
 '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#gr)"/>'
 '<ellipse cx="540" cy="800" rx="360" ry="110" fill="url(#ms)"/>'
 '<g transform="rotate(-10 512 512)">'
 +o.planet('<circle cx="512" cy="512" r="230" fill="url(#pl)"/><circle cx="512" cy="512" r="226" fill="none" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="6"/><path d="M432 470 Q512 560 592 470" fill="none" stroke="#FF4B2E" stroke-width="46" stroke-linecap="round"/>')
 +o.ring({"stroke":"url(#rb)","stroke_width":74},{"stroke":"#FFFFFF","stroke_opacity":0.75,"stroke_width":12,"transform":"translate(0 -20)"})
 +o.moon('<circle r="80" fill="url(#mo)"/><ellipse cx="-24" cy="-28" rx="24" ry="14" fill="#FFFFFF" fill-opacity="0.7"/>')+'</g>')
# Carta
o=Orbit(gap=16,moon_r=74,moon_gap=16)
svg(P+"11-carta.svg", o.defs()
 +'<linearGradient id="tb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5E6169"/><stop offset="1" stop-color="#44474F"/></linearGradient>\n'
 '<linearGradient id="mt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4F4F6"/><stop offset="1" stop-color="#A4A6AC"/></linearGradient>\n'
 '<linearGradient id="gf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5A5D66"/><stop offset="1" stop-color="#1F2126"/></linearGradient>\n'
 '<linearGradient id="gf2" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2B2D33"/><stop offset="0.5" stop-color="#4A4D55"/><stop offset="1" stop-color="#2B2D33"/></linearGradient>\n'
 '<linearGradient id="fl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#AEB1B8"/></linearGradient>\n'
 '<pattern id="gr" width="64" height="64" patternUnits="userSpaceOnUse" y="240"><path d="M64 0H0V64" fill="none" stroke="#C3C6CE" stroke-width="2" stroke-dasharray="6 6"/></pattern>\n',
 '<rect width="1024" height="1024" fill="#34363D"/><rect width="1024" height="270" fill="url(#tb)"/>'
 '<rect x="250" y="96" width="190" height="72" rx="36" fill="#2A2C31"/><rect x="270" y="115" width="150" height="34" rx="17" fill="url(#mt)"/>'
 '<rect x="584" y="96" width="190" height="72" rx="36" fill="#2A2C31"/><rect x="604" y="115" width="150" height="34" rx="17" fill="url(#mt)"/>'
 '<path d="M0 266 H1024 V768 L768 1024 H0 Z" fill="#000000" fill-opacity="0.12"/><path d="M0 258 H1024 V762 L762 1024 H0 Z" fill="#000000" fill-opacity="0.18"/>'
 '<path d="M0 250 H1024 V760 L760 1024 H0 Z" fill="#ECEDF0"/><path d="M0 250 H1024 V760 L760 1024 H0 Z" fill="url(#gr)"/>'
 +sc(0.7, o.planet('<circle cx="512" cy="512" r="215" fill="url(#gf)"/>')+o.ring({"stroke":"url(#gf2)","stroke_width":54})+o.moon('<circle r="74" fill="#6B6E77"/>'),512,612)
 +'<path d="M760 1024 Q742 778 1024 760 Q900 900 760 1024 Z" fill="#000000" fill-opacity="0.22" transform="translate(-10 -10)"/>'
 '<path d="M760 1024 Q742 778 1024 760 Q900 900 760 1024 Z" fill="url(#fl)"/>')

# ---------- Giorno and Vicino, in layers ----------
# Each part on its own transparent layer, no filters, so Icon Composer can put
# any background under them.
def layer(folder, name, defs, body):
    os.makedirs(D+folder, exist_ok=True)
    open(D+folder+"/"+name,"w").write(HEAD+'<defs>\n'+defs+'</defs>\n'+body+'\n</svg>\n')
PLG='<radialGradient id="pl" cx="0.36" cy="0.3" r="0.8"><stop offset="0" stop-color="#9CD0F2"/><stop offset="0.42" stop-color="#2E6E99"/><stop offset="1" stop-color="#0A2640"/></radialGradient>\n'
MO=MOONG.format(a="#FFE7B4",b="#F2A93B",c="#A9650C")
# Giorno: the day as a dial, the moon on the rim.
G="layers-giorno"
layer(G,"1-sfondo.svg",'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#15406A"/><stop offset="1" stop-color="#040C18"/></linearGradient>\n',
      '<rect width="1024" height="1024" fill="url(#bg)"/>')
layer(G,"2-quadrante.svg","",
      '<circle cx="512" cy="512" r="360" fill="none" stroke="#1E4468" stroke-width="48"/>'
      '<path d="M844.6 374.2 A360 360 0 0 1 823.8 692" fill="none" stroke="#FFFFFF" stroke-width="48" stroke-linecap="round"/>'
      '<path d="M465 868.9 A360 360 0 0 1 200.2 692" fill="none" stroke="#8FB0CE" stroke-width="48" stroke-linecap="round"/>'
      '<circle cx="512" cy="152" r="10" fill="#8FB0CE"/>')
layer(G,"3-pianeta.svg",PLG,
      '<circle cx="512" cy="512" r="210" fill="url(#pl)"/>'
      '<ellipse cx="440" cy="414" rx="80" ry="42" fill="#FFFFFF" fill-opacity="0.3" transform="rotate(-32 440 414)"/>')
layer(G,"4-luna.svg",MO+soft("lg","#F2A93B",0.6,0.6),
      '<circle cx="865.4" cy="580.7" r="120" fill="url(#lg)"/>'
      '<circle cx="865.4" cy="580.7" r="72" fill="url(#mo)" stroke="#0B2034" stroke-width="10"/>'
      '<ellipse cx="842" cy="554" rx="24" ry="14" fill="#FFFFFF" fill-opacity="0.75"/>')
# Vicino: the planet close up, filling the corner.
V="layers-vicino"
o=Orbit(cx=380,cy=760,rx=900,ry=230,rot=-30,pr=520,ring_w=70,gap=18,moon_t=-50,moon_r=112,moon_gap=16)
layer(V,"1-sfondo.svg",'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1B4F80"/><stop offset="1" stop-color="#061322"/></linearGradient>\n',
      '<rect width="1024" height="1024" fill="url(#bg)"/>')
layer(V,"2-pianeta.svg",o.defs()+'<radialGradient id="pl" cx="0.38" cy="0.22" r="0.8"><stop offset="0" stop-color="#9CD0F2"/><stop offset="0.4" stop-color="#2E6E99"/><stop offset="1" stop-color="#08203A"/></radialGradient>\n',
      o.planet('<circle cx="380" cy="760" r="520" fill="url(#pl)"/><ellipse cx="300" cy="340" rx="140" ry="52" fill="#FFFFFF" fill-opacity="0.25" transform="rotate(-28 300 340)"/>'))
layer(V,"3-anello.svg",o.defs()+'<linearGradient id="rf" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#9FB6CC"/><stop offset="0.6" stop-color="#FFFFFF"/><stop offset="1" stop-color="#B7CADC"/></linearGradient>\n',
      o.ring({"stroke":"url(#rf)","stroke_width":70}))
layer(V,"4-luna.svg",MO,
      o.moon('<circle r="112" fill="url(#mo)"/><ellipse cx="-38" cy="-44" rx="40" ry="24" fill="#FFFFFF" fill-opacity="0.75"/>'))

# ---------- Giorno and Vicino, in every colour ----------
# The Flavor swatches (Flavor.swatches) plus cream. Each gives a background
# layer for Icon Composer, next to the shared layers, and a whole icon to look at.
import re as _re, colorsys
SWATCHES=[("Cream","#F4EDDE"),("Lavender","#7A6FE0"),("Indigo","#3B4BC8"),("Sky","#2E9BD6"),("Mint","#2FA88A"),
          ("Sage","#5E8C61"),("Mandarin","#E8751A"),("Coral","#E0584F"),("Raspberry","#C2386F"),("Coffee","#8A5A3C"),
          ("Slate","#5B6472"),("Graphite","#1F2328")]
def darker(h,k=0.4):
    r,g,b=(int(h[i:i+2],16)/255 for i in (1,3,5)); hh,l,s=colorsys.rgb_to_hls(r,g,b)
    r,g,b=colorsys.hls_to_rgb(hh,l*k,s); return "#%02X%02X%02X"%(round(r*255),round(g*255),round(b*255))
def bglayer(top,bottom):
    return (HEAD+f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/>'
            f'<stop offset="1" stop-color="{bottom}"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>\n</svg>\n')
def merged(folder, background):
    """The layers over a background, as one clipped SVG: ids made unique per layer."""
    defs,body="",""
    for i,f in enumerate(sorted(os.listdir(D+folder))):
        if not f[0].isdigit() or f.startswith("1-"): continue
        s=open(D+folder+"/"+f).read()
        d=_re.search(r'<defs>(.*?)</defs>',s,_re.S).group(1); b=s.split('</defs>',1)[1].rsplit('</svg>',1)[0]
        for x in _re.findall(r'id="([^"]+)"',d):
            d=d.replace(f'id="{x}"',f'id="L{i}{x}"'); b=b.replace(f'#{x})',f'#L{i}{x})')
        defs+=d; body+=b
    bs=open(background).read()
    bd=_re.search(r'<defs>(.*?)</defs>',bs,_re.S).group(1); bb=bs.split('</defs>',1)[1].rsplit('</svg>',1)[0]
    return HEAD+'<defs>\n'+CLIP+bd+defs+'</defs>\n<g clip-path="url(#m)">'+bb+body+'</g>\n</svg>\n'
for folder,label in (("layers-giorno","Dial"),("layers-vicino","CloseUp")):
    os.makedirs(D+folder+"/sfondi",exist_ok=True); os.makedirs(D+"variants",exist_ok=True)
    for name,hexc in SWATCHES:
        bgf=D+folder+f"/sfondi/1-sfondo-{name.lower()}.svg"
        open(bgf,"w").write(bglayer(hexc,darker(hexc)))
        open(D+f"variants/AppIcon-{label}-{name}.svg","w").write(merged(folder,bgf))
