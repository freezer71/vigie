// Visuels de présentation de Vigie, composés à partir de vraies captures de l'app.
// Usage : swift scripts/make-media.swift <apercu.png> <processus.png> <barre.png> <dossier de sortie>
//   social-preview.png  1280 × 640  miniature des liens (GitHub, réseaux sociaux, messageries)
//   hero.png            2400 × 1500 visuel du README (barre des menus + les deux onglets)
import AppKit

let args = CommandLine.arguments
guard args.count == 5 else { fatalError("usage : make-media.swift apercu.png processus.png barre.png sortie/") }
func load(_ p: String) -> NSImage { NSImage(contentsOfFile: p) ?? { fatalError("introuvable : \(p)") }() }
let overview = load(args[1]), processes = load(args[2]), menubar = load(args[3])
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let icon = load(root.appendingPathComponent("design/logo/vigie-icon.png").path)
let out = URL(fileURLWithPath: args[4])

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let palette = [color(0x5B8DEF), color(0xA27CEB), color(0x4CB782)]

/// Pixels réels d'une capture (les NSImage de captures Retina annoncent une taille en points).
func pixels(_ img: NSImage) -> NSSize {
    guard let rep = img.representations.first else { return img.size }
    return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

func canvas(_ w: Int, _ h: Int, _ name: String, _ body: (CGContext, CGFloat, CGFloat) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
    body(g.cgContext, CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("✔ \(name)")
}

/// Fond graphite et courbe d'activité discrète, comme dans le logo.
func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, curveY: CGFloat, amplitude: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bg = CGGradient(colorsSpace: space, colors: [color(0x2A2E36).cgColor, color(0x131519).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: CGPoint(x: w * 0.3, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let values: [CGFloat] = [0.3, 0.5, 0.2, 0.7, 0.4, 0.9, 0.35, 0.6, 0.8, 0.3, 0.55, 0.75, 0.4, 0.65, 0.5, 0.7, 0.45]
    let pts = values.enumerated().map { i, v in CGPoint(x: -20 + (w + 40) * CGFloat(i) / CGFloat(values.count - 1), y: curveY + v * amplitude) }
    let line = CGMutablePath(); line.move(to: pts[0])
    for i in 1..<pts.count {
        line.addQuadCurve(to: CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2), control: pts[i - 1])
    }
    line.addLine(to: pts.last!)
    let area = line.mutableCopy()!
    area.addLine(to: CGPoint(x: w + 20, y: 0)); area.addLine(to: CGPoint(x: -20, y: 0)); area.closeSubpath()
    ctx.addPath(area); ctx.setFillColor(color(0xFFFFFF, 0.025).cgColor); ctx.fillPath()
    ctx.addPath(line); ctx.setStrokeColor(color(0xFFFFFF, 0.09).cgColor); ctx.setLineWidth(w / 640); ctx.strokePath()
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ col: NSColor, at p: CGPoint, kern: CGFloat = 0) -> CGFloat {
    let attr = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                          .foregroundColor: col, .kern: kern])
    attr.draw(at: p)
    return attr.size().width
}

/// Capture posée telle quelle (l'ombre de la fenêtre est déjà dans l'image), mise à l'échelle sur la hauteur.
func place(_ img: NSImage, height: CGFloat, x: CGFloat, y: CGFloat) -> CGFloat {
    let px = pixels(img)
    let width = px.width * height / px.height
    img.draw(in: NSRect(x: x, y: y, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
    return width
}

// Miniature des liens : 1280 × 640 (format conseillé par GitHub).
try canvas(1280, 640, "social-preview.png") { ctx, w, h in
    background(ctx, w, h, curveY: 70, amplitude: 60)
    // Capture de l'Aperçu à droite, coupée par le bas pour rester lisible.
    _ = place(overview, height: 940, x: 690, y: -330)

    let x: CGFloat = 76
    icon.draw(in: NSRect(x: x - 14, y: 410, width: 150, height: 150))
    _ = text("Vigie", 92, .bold, color(0xF2F3F5), at: CGPoint(x: x, y: 290), kern: -1.5)
    _ = text("Votre Mac, d'un coup d'œil.", 34, .medium, color(0xFFFFFF, 0.78), at: CGPoint(x: x, y: 238))
    _ = text("Le moniteur système de la barre des menus.", 24, .regular, color(0xFFFFFF, 0.5), at: CGPoint(x: x, y: 200))
    // Les mesures, aux couleurs de l'app.
    var cx = x
    for (i, label) in ["CPU", "GPU", "Mémoire", "Température", "Processus"].enumerated() {
        let c = i < 3 ? palette[i] : color(0xFFFFFF, 0.55)
        let attr = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: c])
        let sz = attr.size()
        let pill = NSRect(x: cx, y: 128, width: sz.width + 26, height: 38)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 19, cornerHeight: 19, transform: nil))
        ctx.setFillColor(c.withAlphaComponent(0.13).cgColor); ctx.fillPath()
        attr.draw(at: CGPoint(x: cx + 13, y: 128 + (38 - sz.height) / 2))
        cx += pill.width + 10
    }
    _ = text("macOS 14+ · Apple Silicon · Swift · open source", 18, .regular, color(0xFFFFFF, 0.38), at: CGPoint(x: x, y: 70))
}

// Visuel du README : la barre des menus en haut, les deux onglets côte à côte.
try canvas(2400, 1500, "hero.png") { ctx, w, h in
    background(ctx, w, h, curveY: 120, amplitude: 110)
    // Bandeau « barre des menus » centré, avec la vraie capture du texte de Vigie.
    let mb = pixels(menubar)
    let barH: CGFloat = 76, barW = mb.width * barH / mb.height + 80
    let bar = NSRect(x: (w - barW) / 2, y: h - 150, width: barW, height: barH)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
    ctx.setFillColor(color(0x000000).cgColor); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.08).cgColor); ctx.setLineWidth(2); ctx.strokePath()
    menubar.draw(in: NSRect(x: bar.minX + 40, y: bar.minY, width: barW - 80, height: barH), from: .zero, operation: .sourceOver, fraction: 1)

    let panelH: CGFloat = 1250
    let ow = pixels(overview).width * panelH / pixels(overview).height
    let pw = pixels(processes).width * panelH / pixels(processes).height
    let gap: CGFloat = 40
    let start = (w - ow - pw - gap) / 2
    _ = place(overview, height: panelH, x: start, y: 20)
    _ = place(processes, height: panelH, x: start + ow + gap, y: 20)
}
