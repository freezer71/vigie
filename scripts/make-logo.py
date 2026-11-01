#!/usr/bin/env python3
"""Logo de Vigie : des lunettes posées devant un graphe, qui le révèlent en couleur.

Source unique, en SVG. Produit dans design/logo/ :
  vigie-icon.svg / .pdf / .png         icône couleur
  vigie-icon-mono.svg / .pdf / .png    icône monochrome (niveaux de gris)
  vigie-symbol.svg / .pdf / .png       symbole noir, fond transparent
                                       (en SVG, il prend la couleur du texte : currentColor)
  vigie-symbol-blanc.svg / .pdf / .png le même en blanc, pour les fonds sombres
et Resources/AppIcon.icns pour l'app. Nécessite rsvg-convert (brew install librsvg).
Usage : python3 scripts/make-logo.py
"""
import math, os, shutil, subprocess, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "design", "logo")

S = 1024.0
INSET = 100.0
T = S - 2 * INSET                       # côté du carré arrondi (grille macOS : 824/1024)
CX = CY = S / 2
R = 0.165 * T                           # rayon d'un verre
GAP_X = 0.205 * T                       # écart du centre de l'icône au centre d'un verre
LEFT, RIGHT = CX - GAP_X, CX + GAP_X
FRAME = 0.034 * T

CPU, GPU, MEM = "#5B8DEF", "#A27CEB", "#4CB782"
LIGHT, GLASS = "#E8EAED", "#10141B"

# Courbe d'activité : pics et creux comme une vraie mesure de CPU.
VALUES = [0.02, 0.06, -0.04, 0.10, 0.00, 0.16, 0.05, 0.24, -0.02, 0.08, 0.20, 0.03, -0.08, 0.06,
          0.14, -0.02, 0.22, 0.10, 0.28, 0.04, 0.12, -0.04, 0.18, 0.06, 0.10, 0.00, 0.08]


def f(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def up(y):
    """Les mesures sont pensées avec y vers le haut ; le SVG a y vers le bas."""
    return S - y


def chart(closed):
    x0, width = INSET - 0.05 * T, 1.1 * T
    pts = [(x0 + width * i / (len(VALUES) - 1), up(CY - 0.06 * T + v * 0.42 * T)) for i, v in enumerate(VALUES)]
    d = [f"M{f(pts[0][0])} {f(pts[0][1])}"]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):   # Bézier par les milieux : courbe douce
        d.append(f"Q{f(ax)} {f(ay)} {f((ax + bx) / 2)} {f((ay + by) / 2)}")
    d.append(f"L{f(pts[-1][0])} {f(pts[-1][1])}")
    if closed:
        bottom = up(INSET - 0.05 * T)
        d.append(f"L{f(pts[-1][0])} {f(bottom)}L{f(pts[0][0])} {f(bottom)}Z")
    return "".join(d)


LINE, AREA = chart(False), chart(True)


def circle(cx, r=R):
    return f'<circle cx="{f(cx)}" cy="{f(CY)}" r="{f(r)}"/>'


def frame_paths():
    """Monture : deux cercles, le pont arqué, les deux branches (tracés, sans remplissage)."""
    a0 = math.pi * 0.20
    p0 = (LEFT + math.cos(a0) * R, up(CY + math.sin(a0) * R))
    p1 = (RIGHT - math.cos(a0) * R, up(CY + math.sin(a0) * R))
    bridge = (f"M{f(p0[0])} {f(p0[1])}C{f(p0[0] + 0.04 * T)} {f(p0[1] - 0.05 * T)} "
              f"{f(p1[0] - 0.04 * T)} {f(p1[1] - 0.05 * T)} {f(p1[0])} {f(p1[1])}")
    temples = ""
    for x, d in ((LEFT - R, -1), (RIGHT + R, 1)):
        temples += f"M{f(x)} {f(up(CY + R * 0.45))}L{f(x + d * 0.06 * T)} {f(up(CY + R * 0.62))}"
    return (f'<circle cx="{f(LEFT)}" cy="{f(CY)}" r="{f(R)}"/><circle cx="{f(RIGHT)}" cy="{f(CY)}" r="{f(R)}"/>'
            f'<path d="{bridge}{temples}"/>')


def glare(cx):
    rr, a, b = R * 0.78, math.pi * 0.62, math.pi * 0.88
    sx, sy = cx + rr * math.cos(a), up(CY + rr * math.sin(a))
    ex, ey = cx + rr * math.cos(b), up(CY + rr * math.sin(b))
    return f"M{f(sx)} {f(sy)}A{f(rr)} {f(rr)} 0 0 0 {f(ex)} {f(ey)}"


def icon(mono):
    colors = [LIGHT, LIGHT, LIGHT] if mono else [CPU, GPU, MEM]
    fill_opacity = 0.30 if mono else 0.55
    corner = 0.225 * T
    lenses = ""
    for i, cx in enumerate((LEFT, RIGHT)):
        grid = "".join(
            f'<path d="M{f(cx - R)} {f(up(CY - R + 2 * R * k / 5))}H{f(cx + R)}"/>' for k in range(1, 5))
        zoom = f"translate({f(cx)} {f(CY)}) scale(1.25) translate({f(-cx)} {f(-CY)})"
        lenses += f'''
  <g clip-path="url(#lens{i})">
    <rect x="{f(cx - R)}" y="{f(CY - R)}" width="{f(2 * R)}" height="{f(2 * R)}" fill="{GLASS}"/>
    <g stroke="#FFFFFF" stroke-opacity="0.06" stroke-width="{f(0.004 * T)}">{grid}</g>
    <g transform="{zoom}">
      <path d="{AREA}" fill="url(#palette)" fill-opacity="{fill_opacity}"/>
      <path d="{AREA}" fill="url(#fade)"/>
      <path d="{LINE}" fill="none" stroke="url(#palette)" stroke-width="{f(0.016 * T)}" stroke-linecap="round" stroke-linejoin="round"/>
    </g>
    <path d="{glare(cx)}" fill="none" stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="{f(0.016 * T)}" stroke-linecap="round"/>
  </g>'''
    title = "Vigie — icône monochrome" if mono else "Vigie"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {f(S)} {f(S)}" width="{f(S)}" height="{f(S)}">
  <title>{title}</title>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2A2E36"/><stop offset="1" stop-color="#15171C"/>
    </linearGradient>
    <linearGradient id="palette" gradientUnits="userSpaceOnUse" x1="{f(INSET)}" y1="0" x2="{f(S - INSET)}" y2="0">
      <stop offset="0" stop-color="{colors[0]}"/><stop offset="0.5" stop-color="{colors[1]}"/><stop offset="1" stop-color="{colors[2]}"/>
    </linearGradient>
    <linearGradient id="fade" gradientUnits="userSpaceOnUse" x1="0" y1="{f(up(CY + 0.1 * T))}" x2="0" y2="{f(up(CY - 0.2 * T))}">
      <stop offset="0" stop-color="{GLASS}" stop-opacity="0"/><stop offset="1" stop-color="{GLASS}" stop-opacity="0.75"/>
    </linearGradient>
    <clipPath id="tile"><rect x="{f(INSET)}" y="{f(INSET)}" width="{f(T)}" height="{f(T)}" rx="{f(corner)}"/></clipPath>
    <clipPath id="lens0">{circle(LEFT)}</clipPath>
    <clipPath id="lens1">{circle(RIGHT)}</clipPath>
    <filter id="tileShadow" x="-10%" y="-10%" width="120%" height="125%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="{f(0.015 * S)}"/><feOffset dy="{f(0.01 * S)}"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.35"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="frameShadow" x="-10%" y="-20%" width="120%" height="140%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="{f(0.01 * T)}"/><feOffset dy="{f(0.008 * T)}"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.5"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect x="{f(INSET)}" y="{f(INSET)}" width="{f(T)}" height="{f(T)}" rx="{f(corner)}" fill="url(#bg)" filter="url(#tileShadow)"/>
  <g clip-path="url(#tile)">
    <path d="{AREA}" fill="#FFFFFF" fill-opacity="0.035"/>
    <path d="{LINE}" fill="none" stroke="#FFFFFF" stroke-opacity="0.22" stroke-width="{f(0.010 * T)}" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <rect x="{f(INSET)}" y="{f(INSET)}" width="{f(T)}" height="{f(T)}" rx="{f(corner)}" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="{f(0.006 * S)}"/>
{lenses}
  <g fill="none" stroke="{LIGHT}" stroke-width="{f(FRAME)}" stroke-linecap="round" filter="url(#frameShadow)">
    {frame_paths()}
  </g>
</svg>
'''


def symbol(color="#000000", title="Vigie — symbole"):
    """Une seule couleur, sans fond ni dégradé : la monture et la courbe vue à travers les verres."""
    zoom = lambda cx: f"translate({f(cx)} {f(CY)}) scale(1.25) translate({f(-cx)} {f(-CY)})"
    # Cadrage resserré sur les lunettes.
    x0, x1 = LEFT - R - 0.06 * T - FRAME, RIGHT + R + 0.06 * T + FRAME
    y0, y1 = CY - R - FRAME, CY + R + FRAME
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{f(x0)} {f(y0)} {f(x1 - x0)} {f(y1 - y0)}" width="{f(x1 - x0)}" height="{f(y1 - y0)}" color="{color}">
  <title>{title}</title>
  <defs>
    <clipPath id="lens0">{circle(LEFT)}</clipPath>
    <clipPath id="lens1">{circle(RIGHT)}</clipPath>
  </defs>
  <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
    <g clip-path="url(#lens0)"><path d="{LINE}" transform="{zoom(LEFT)}" stroke-width="{f(0.018 * T)}"/></g>
    <g clip-path="url(#lens1)"><path d="{LINE}" transform="{zoom(RIGHT)}" stroke-width="{f(0.018 * T)}"/></g>
    <g stroke-width="{f(FRAME)}">{frame_paths()}</g>
  </g>
</svg>
'''


def render(svg_path, fmt, out, size=None):
    cmd = ["rsvg-convert", "-f", fmt, "-o", out]
    if size:
        cmd += ["-w", str(size), "-h", str(size)]
    subprocess.run(cmd + [svg_path], check=True)


def main():
    if not shutil.which("rsvg-convert"):
        raise SystemExit("rsvg-convert introuvable : brew install librsvg")
    os.makedirs(OUT, exist_ok=True)
    files = {"vigie-icon": icon(False), "vigie-icon-mono": icon(True), "vigie-symbol": symbol(),
             "vigie-symbol-blanc": symbol("#FFFFFF", "Vigie — symbole blanc")}
    for name, svg in files.items():
        path = os.path.join(OUT, name + ".svg")
        with open(path, "w") as fh:
            fh.write(svg)
        render(path, "pdf", os.path.join(OUT, name + ".pdf"))
        render(path, "png", os.path.join(OUT, name + ".png"), None if name.startswith("vigie-symbol") else 1024)

    # Icône de l'app : toutes les tailles demandées par macOS, rendues depuis le SVG couleur.
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for base in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ""), (2, "@2x")):
                render(os.path.join(OUT, "vigie-icon.svg"), "png",
                       os.path.join(iconset, f"icon_{base}x{base}{suffix}.png"), base * scale)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(ROOT, "Resources", "AppIcon.icns")], check=True)
    print("✔ design/logo/ et Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
