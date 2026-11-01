import SwiftUI

/// Chaque section est une vue à part : SwiftUI (Observation) ne la recalcule que lorsque les mesures
/// qu'elle lit changent, et un survol ne redessine que la section survolée.
struct OverviewView: View {
    let monitor: SystemMonitor

    enum Metric { case cpu, gpu, memory }
    @State private var focus: Metric = .cpu

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Paresseux : les sections hors écran ne sont ni construites ni redessinées.
            LazyVStack(spacing: 10) {
                TilesRow(monitor: monitor, focus: $focus)
                FocusPanel(monitor: monitor, focus: focus)
                CoresPanel(monitor: monitor)
                MemoryPanel(monitor: monitor)
                TopAppsPanel(monitor: monitor)
                HStack(alignment: .top, spacing: 10) {
                    NetworkPanel(monitor: monitor)
                    DiskPanel(monitor: monitor)
                }
                EnergyPanel(monitor: monitor)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }
}

// MARK: - Tuiles

private struct TilesRow: View {
    let monitor: SystemMonitor
    @Binding var focus: OverviewView.Metric

    var body: some View {
        HStack(spacing: 8) {
            MetricTile(title: "CPU", value: monitor.cpu.total,
                       caption: "\(monitor.info.cpuCores) cœurs", color: Palette.cpu,
                       history: monitor.cpuHistory, xDomain: monitor.xDomain, isSelected: focus == .cpu) { focus = .cpu }
            MetricTile(title: "GPU", value: monitor.gpu.utilization,
                       caption: "\(monitor.info.gpuCores) cœurs", color: Palette.gpu,
                       history: monitor.gpuHistory, xDomain: monitor.xDomain, isSelected: focus == .gpu) { focus = .gpu }
            MetricTile(title: "Mémoire", value: monitor.memory.usage,
                       caption: "\(Fmt.bytes(monitor.memory.used)) / \(Fmt.bytes(monitor.memory.total))", color: Palette.memory,
                       history: monitor.memoryHistory, xDomain: monitor.xDomain, isSelected: focus == .memory) { focus = .memory }
        }
    }
}

// MARK: - Graphique principal

private struct FocusPanel: View {
    let monitor: SystemMonitor
    let focus: OverviewView.Metric

    var body: some View {
        let (title, points, color): (String, [HistoryPoint], Color) = switch focus {
        case .cpu: ("Processeur", monitor.cpuHistory, Palette.cpu)
        case .gpu: ("Carte graphique", monitor.gpuHistory, Palette.gpu)
        case .memory: ("Mémoire", monitor.memoryHistory, Palette.memory)
        }
        Panel(title: title) {
            Text(monitor.historySpanLabel).font(.system(size: 10)).foregroundStyle(.tertiary)
        } content: {
            DetailChart(points: points, color: color, xDomain: monitor.xDomain, secondsPerPoint: monitor.interval)
                .frame(height: 110)
                .id(focus)
            HStack(spacing: 8) {
                switch focus {
                case .cpu:
                    StatItem(label: "Utilisateur", value: Fmt.percent(monitor.cpu.user))
                    StatItem(label: "Système", value: Fmt.percent(monitor.cpu.system))
                    StatItem(label: "Charge 1 · 5 · 15 min",
                             value: monitor.cpu.loadAverage.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }.joined(separator: " · "))
                case .gpu:
                    StatItem(label: "Rendu", value: Fmt.percent(monitor.gpu.renderer))
                    StatItem(label: "Géométrie", value: Fmt.percent(monitor.gpu.tiler))
                    StatItem(label: "Mémoire GPU", value: Fmt.bytes(monitor.gpu.memoryUsed))
                case .memory:
                    StatItem(label: "Utilisée", value: Fmt.bytes(monitor.memory.used))
                    StatItem(label: "Compressée", value: Fmt.bytes(monitor.memory.compressed))
                    StatItem(label: "Swap", value: Fmt.bytes(monitor.memory.swapUsed))
                }
            }
        }
    }
}

// MARK: - Cœurs

private struct CoresPanel: View {
    let monitor: SystemMonitor
    @State private var hover: HeatmapHover?

    var body: some View {
        Panel(title: "Activité par cœur") {
            if let h = hover {
                let kind = h.core < monitor.info.efficiencyCores ? "efficacité" : "performance"
                Text("Cœur \(CoreHeatmap.label(for: h.core, efficiencyCores: monitor.info.efficiencyCores)) (\(kind)) · \(Fmt.percent(h.load)) · \(Ago.text(Double(h.age) * monitor.interval))")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            } else {
                HStack(spacing: 10) {
                    legendDot(Palette.download, "Efficacité")
                    legendDot(Palette.cpu, "Performance")
                }
            }
        } content: {
            CoreHeatmap(history: monitor.coreHistory, efficiencyCores: monitor.info.efficiencyCores, hover: $hover)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Mémoire

private struct MemoryPanel: View {
    let monitor: SystemMonitor
    @State private var hovered: String?

    private struct Section: Identifiable {
        let id: String
        let label: String
        let bytes: UInt64
        let color: Color
        let explanation: String
    }

    var body: some View {
        let m = monitor.memory
        let sections = sections(m)
        let slices = sections.map { DonutChart.Slice(id: $0.id, value: Double($0.bytes), color: $0.color) }
        let active = sections.first { $0.id == hovered }

        Panel(title: "Répartition de la mémoire") {
            pressureBadge(m.pressure)
        } content: {
            HStack(spacing: 18) {
                ZStack {
                    DonutChart(slices: slices, highlighted: $hovered)
                    VStack(spacing: 0) {
                        if let active {
                            Text(Fmt.bytes(active.bytes)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            Text(Fmt.percent(Double(active.bytes) / Double(max(m.total, 1))))
                                .font(.system(size: 9.5)).foregroundStyle(.secondary).monospacedDigit()
                        } else {
                            Text(Fmt.bytes(m.used)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            Text("sur \(Fmt.bytes(m.total))").font(.system(size: 9.5)).foregroundStyle(.secondary)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: 104, height: 104)
                VStack(spacing: 2) {
                    ForEach(sections) { section in
                        LegendRow(color: section.color, label: section.label, value: Fmt.bytes(section.bytes),
                                  isHighlighted: hovered == section.id)
                            .onHover { inside in
                                if inside { hovered = section.id } else if hovered == section.id { hovered = nil }
                            }
                    }
                }
            }
            // Explication du compartiment survolé ; hauteur fixe pour que rien ne saute.
            Text(active?.explanation ?? "Survolez l'anneau ou la légende pour voir ce que contient chaque compartiment.")
                .font(.system(size: 10.5))
                .foregroundStyle(active == nil ? .tertiary : .secondary)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sections(_ m: MemoryStats) -> [Section] {
        [
            .init(id: "apps", label: "Applications", bytes: m.app, color: Palette.memory,
                  explanation: "Applications : mémoire utilisée par les apps et leurs processus. C'est ce que vous libérez en fermant des apps."),
            .init(id: "wired", label: "Réservée au système", bytes: m.wired, color: Palette.cpu,
                  explanation: "Réservée : mémoire du noyau et des pilotes (dont une part du GPU). Elle ne peut être ni compressée ni écrite sur disque."),
            .init(id: "compressed", label: "Compressée", bytes: m.compressed, color: Palette.gpu,
                  explanation: "Compressée : données peu utilisées que macOS compresse pour faire de la place, plutôt que de les écrire sur le disque."),
            .init(id: "cached", label: "Cache de fichiers", bytes: m.cached, color: Palette.disk.opacity(0.75),
                  explanation: "Cache : fichiers lus récemment, gardés en mémoire pour aller plus vite. Libérée aussitôt qu'une app en a besoin."),
            .init(id: "free", label: "Libre", bytes: m.free, color: Color.primary.opacity(0.15),
                  explanation: "Libre : mémoire inutilisée, disponible immédiatement."),
        ]
    }

    private func pressureBadge(_ p: MemoryStats.Pressure) -> some View {
        switch p {
        case .normal: Badge(text: "Pression normale", color: Palette.memory)
        case .warning: Badge(text: "Pression élevée", color: Palette.warning)
        case .critical: Badge(text: "Pression critique", color: Palette.critical)
        }
    }
}

// MARK: - Applications

private struct TopAppsPanel: View {
    let monitor: SystemMonitor

    var body: some View {
        let top = Array(monitor.apps.sorted { $0.cpu > $1.cpu }.prefix(5))
        let peak = max(top.first?.cpu ?? 1, 1)
        Panel(title: "Applications les plus actives") {
            HStack(spacing: 0) {
                Text("CPU").frame(width: 46, alignment: .trailing)
                Text("Mémoire").frame(width: 62, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        } content: {
            if top.isEmpty {
                Text("Analyse en cours…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(spacing: 7) {
                ForEach(top) { app in
                    HStack(spacing: 8) {
                        ProcessIconView(icon: app.icon, size: 16)
                        Text(app.name).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 8)
                        MiniBar(value: app.cpu / peak, color: Palette.level(app.cpu / 100, base: Palette.cpu), height: 3)
                            .frame(width: 56)
                        Text(Fmt.cpu(app.cpu)).frame(width: 46, alignment: .trailing)
                        Text(Fmt.bytes(app.memory)).foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)
                    }
                    .font(.system(size: 11).monospacedDigit())
                }
            }
        }
    }
}

// MARK: - Réseau & disque

private struct RateLine: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(color).frame(width: 12)
            Text(text).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
    }
}

/// « il y a 12 s » sous un graphique survolé, « en direct » sinon (hauteur constante).
private struct HoverCaption: View {
    let monitor: SystemMonitor
    let tick: Int?

    var body: some View {
        Text(tick.map { Ago.text(Double(monitor.tick - $0) * monitor.interval) } ?? "en direct")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}

private struct NetworkPanel: View {
    let monitor: SystemMonitor
    @State private var hovered: Int?

    var body: some View {
        let down = hovered.flatMap { monitor.downloadHistory.value(at: $0) } ?? monitor.network.download
        let up = hovered.flatMap { monitor.uploadHistory.value(at: $0) } ?? monitor.network.upload
        Panel(title: "Réseau") {
            VStack(alignment: .leading, spacing: 4) {
                RateLine(icon: "arrow.down", text: Fmt.rate(down), color: Palette.download)
                RateLine(icon: "arrow.up", text: Fmt.rate(up), color: Palette.upload)
            }
            RateChart(series: [
                .init(id: "down", points: monitor.downloadHistory, color: Palette.download),
                .init(id: "up", points: monitor.uploadHistory, color: Palette.upload),
            ], xDomain: monitor.xDomain, hovered: $hovered)
            .frame(height: 44)
            HoverCaption(monitor: monitor, tick: hovered)
        }
    }
}

private struct DiskPanel: View {
    let monitor: SystemMonitor
    @State private var hovered: Int?

    var body: some View {
        let d = monitor.disk
        let read = hovered.flatMap { monitor.diskReadHistory.value(at: $0) } ?? d.read
        let write = hovered.flatMap { monitor.diskWriteHistory.value(at: $0) } ?? d.write
        Panel(title: "Disque") {
            VStack(alignment: .leading, spacing: 4) {
                RateLine(icon: "arrow.down.doc", text: Fmt.rate(read), color: Palette.disk)
                RateLine(icon: "arrow.up.doc", text: Fmt.rate(write), color: Palette.upload)
            }
            RateChart(series: [
                .init(id: "read", points: monitor.diskReadHistory, color: Palette.disk),
                .init(id: "write", points: monitor.diskWriteHistory, color: Palette.upload),
            ], xDomain: monitor.xDomain, hovered: $hovered)
            .frame(height: 44)
            HoverCaption(monitor: monitor, tick: hovered)
            MiniBar(value: d.usage, color: Palette.level(d.usage, base: Color.primary.opacity(0.45)), height: 3)
            Text("\(Fmt.bytes(d.available)) libres sur \(Fmt.bytes(d.capacity))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Température et énergie

private struct EnergyPanel: View {
    let monitor: SystemMonitor

    var body: some View {
        let t = monitor.temperature
        Panel(title: "Température et énergie") {
            HStack(spacing: 4) {
                Circle().fill(thermal.color).frame(width: 6, height: 6)
                Text("État thermique \(thermal.label)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        } content: {
            HStack(spacing: 8) {
                StatItem(label: "Puce (moyenne)", value: celsius(t.soc))
                StatItem(label: "Point le plus chaud", value: celsius(t.socMax))
                StatItem(label: "SSD", value: celsius(t.ssd))
            }
            if let b = monitor.battery {
                HStack(spacing: 6) {
                    Image(systemName: batterySymbol(b)).foregroundStyle(.secondary)
                    Text("\(Fmt.percent(b.level)) · \(batteryDetail(b))")
                    Spacer(minLength: 0)
                    if let bt = t.battery {
                        Text("batterie \(celsius(bt))").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11))
                .monospacedDigit()
            }
        }
    }

    private func celsius(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) °C" } ?? "—"
    }

    private var thermal: (label: String, color: Color) {
        switch monitor.thermal {
        case .nominal: ("normale", .secondary)
        case .fair: ("modérée", Palette.warning)
        case .serious: ("élevée", Palette.warning)
        case .critical: ("critique", Palette.critical)
        @unknown default: ("—", .secondary)
        }
    }

    private func batterySymbol(_ b: BatteryStats) -> String {
        if b.isCharging { return "battery.100percent.bolt" }
        switch b.level {
        case ..<0.15: return "battery.0percent"
        case ..<0.4: return "battery.25percent"
        case ..<0.65: return "battery.50percent"
        case ..<0.9: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func batteryDetail(_ b: BatteryStats) -> String {
        let state = b.isCharging ? "en charge" : b.isPluggedIn ? "sur secteur" : "sur batterie"
        guard let minutes = b.minutesRemaining else { return state }
        let time = minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
        return "\(state), \(time) \(b.isCharging ? "avant la charge complète" : "restantes")"
    }
}
