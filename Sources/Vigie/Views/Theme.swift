import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Une couleur sourde par mesure, rien de plus. Les fonds et textes restent ceux du système.
enum Palette {
    static let cpu = Color(hex: 0x5B8DEF)
    static let gpu = Color(hex: 0xA27CEB)
    static let memory = Color(hex: 0x4CB782)
    static let download = Color(hex: 0x4AA8C0)
    static let upload = Color(hex: 0xD99A55)
    static let disk = Color(hex: 0xC9A94A)
    static let warning = Color(hex: 0xE0A040)
    static let critical = Color(hex: 0xE05A4E)

    static let fill = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.08)

    static let series: [Color] = [cpu, gpu, memory, download, upload, disk]

    /// Garde la couleur de base, ne passe à l'orange / rouge que lorsque c'est vraiment chargé.
    static func level(_ value: Double, base: Color) -> Color {
        value >= 0.9 ? critical : value >= 0.75 ? warning : base
    }
}

enum Fmt {
    private static let memoryFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB, .useTB]
        return f
    }()

    private static let rateFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func bytes(_ value: UInt64) -> String { memoryFormatter.string(fromByteCount: Int64(value)) }
    static func rate(_ bytesPerSecond: Double) -> String { rateFormatter.string(fromByteCount: Int64(max(bytesPerSecond, 0))) + "/s" }

    /// « 1,2 M » / « 340 K » : version courte pour la barre des menus.
    static func shortRate(_ bytesPerSecond: Double) -> String {
        let v = max(bytesPerSecond, 0)
        switch v {
        case ..<1_000: return "0 K"
        case ..<1_000_000: return "\(Int(v / 1_000)) K"
        case ..<10_000_000: return String(format: "%.1f M", v / 1_000_000).replacingOccurrences(of: ".", with: ",")
        default: return "\(Int(v / 1_000_000)) M"
        }
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded())) %" }

    static func cpu(_ percent: Double) -> String {
        percent >= 10 ? "\(Int(percent.rounded())) %" : String(format: "%.1f %%", percent).replacingOccurrences(of: ".", with: ",")
    }

    static func duration(since date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
        if d > 0 { return "\(d) j \(h) h" }
        if h > 0 { return "\(h) h \(m) min" }
        return "\(m) min"
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for path: String?) -> NSImage {
        guard let path, !path.isEmpty else {
            return NSImage(systemSymbolName: "gearshape.2.fill", accessibilityDescription: nil) ?? NSImage()
        }
        if let image = cache[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 64, height: 64)
        cache[path] = image
        return image
    }
}
