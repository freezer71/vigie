// Fond de la fenêtre du DMG (640 × 400 points), dans l'esprit du logo.
// Usage : swift scripts/make-dmg-background.swift <dossier de sortie>  → background.png et background@2x.png
import AppKit

let W: CGFloat = 640, H: CGFloat = 400
/// Centres des icônes (repère Finder : origine en haut à gauche). À garder identiques dans package.sh.
let appCenter = CGPoint(x: 170, y: 190), applicationsCenter = CGPoint(x: 470, y: 190)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(_ ctx: CGContext) {
    // Repère « Finder » : y vers le bas.
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    let bg = CGGradient(colorsSpace: space, colors: [color(0x2A2E36).cgColor, color(0x15171C).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: H), options: [])

    // Courbe d'activité discrète en bas, comme derrière les lunettes du logo.
    let values: [CGFloat] = [0.3, 0.5, 0.2, 0.7, 0.4, 0.9, 0.35, 0.6, 0.8, 0.3, 0.55, 0.75, 0.4, 0.65, 0.5]
    let pts = values.enumerated().map { i, v in CGPoint(x: -10 + 660 * CGFloat(i) / CGFloat(values.count - 1), y: 362 - v * 34) }
    let line = CGMutablePath(); line.move(to: pts[0])
    for i in 1..<pts.count {
        line.addQuadCurve(to: CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2), control: pts[i - 1])
    }
    line.addLine(to: pts.last!)
    let area = line.mutableCopy()!
    area.addLine(to: CGPoint(x: 650, y: H)); area.addLine(to: CGPoint(x: -10, y: H)); area.closeSubpath()
    ctx.addPath(area); ctx.setFillColor(color(0xFFFFFF, 0.025).cgColor); ctx.fillPath()
    ctx.addPath(line); ctx.setStrokeColor(color(0xFFFFFF, 0.10).cgColor); ctx.setLineWidth(1.5)
    ctx.setLineJoin(.round); ctx.strokePath()

    // Le Finder écrit toujours les noms en noir sur un fond personnalisé : petites étiquettes claires dessous.
    for (c, width) in [(appCenter, 62.0), (applicationsCenter, 112.0)] as [(CGPoint, CGFloat)] {
        let tag = CGRect(x: c.x - width / 2, y: c.y + 63, width: width, height: 21)
        ctx.addPath(CGPath(roundedRect: tag, cornerWidth: 10.5, cornerHeight: 10.5, transform: nil))
        ctx.setFillColor(color(0xE8EAED, 0.92).cgColor); ctx.fillPath()
    }

    // Flèche : trait en dégradé bleu → violet → vert, pointe arrondie.
    let from = CGPoint(x: appCenter.x + 88, y: appCenter.y), to = CGPoint(x: applicationsCenter.x - 88, y: appCenter.y)
    let arrow = CGMutablePath()
    arrow.move(to: from); arrow.addLine(to: to)
    arrow.move(to: CGPoint(x: to.x - 14, y: to.y - 13)); arrow.addLine(to: to); arrow.addLine(to: CGPoint(x: to.x - 14, y: to.y + 13))
    ctx.saveGState()
    ctx.addPath(arrow); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let palette = CGGradient(colorsSpace: space, colors: [color(0x5B8DEF).cgColor, color(0xA27CEB).cgColor, color(0x4CB782).cgColor] as CFArray,
                             locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(palette, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Textes (AppKit dessine en repère retourné : on rétablit y vers le haut localement).
    func text(_ string: String, _ size: CGFloat, _ weight: NSFont.Weight, _ col: NSColor, centerY: CGFloat) {
        let attr = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: col])
        let sz = attr.size()
        ctx.saveGState()
        ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
        attr.draw(at: CGPoint(x: (W - sz.width) / 2, y: H - centerY - sz.height / 2))
        ctx.restoreGState()
    }
    text("Installer Vigie", 22, .semibold, color(0xF2F3F5), centerY: 50)
    text("Glissez Vigie dans le dossier Applications", 13, .regular, color(0xFFFFFF, 0.6), centerY: 78)
    text("Première ouverture : Réglages Système → Confidentialité et sécurité → Ouvrir quand même",
         10.5, .regular, color(0xFFFFFF, 0.42), centerY: 304)
}

func render(scale: CGFloat, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
    draw(g.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try render(scale: 1, to: out.appendingPathComponent("background.png"))
try render(scale: 2, to: out.appendingPathComponent("background@2x.png"))
