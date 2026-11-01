import Charts
import SwiftUI

// MARK: - Bloc

/// Conteneur discret : titre gris, fond à peine teinté.
struct Panel<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension Panel where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Tuile de mesure

struct MetricTile: View {
    let title: String
    let value: Double
    let caption: String
    let color: Color
    let history: [HistoryPoint]
    let xDomain: ClosedRange<Int>
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int((value * 100).rounded()))")
                        .font(.system(size: 24, weight: .semibold))
                    Text("%").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                .monospacedDigit()
                Sparkline(points: history, color: color, xDomain: xDomain)
                    .frame(height: 22)
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? color.opacity(0.12) : Palette.fill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? color.opacity(0.45) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct Sparkline: View {
    let points: [HistoryPoint]
    let color: Color
    let xDomain: ClosedRange<Int>

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("t", p.id), y: .value("v", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(color.opacity(0.12))
            LineMark(x: .value("t", p.id), y: .value("v", p.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .foregroundStyle(color)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// MARK: - Survol des graphiques

extension View {
    /// Survol d'un graphique temporel : renvoie l'abscisse (numéro d'échantillon) sous le pointeur.
    func chartHover(_ tick: Binding<Int?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geo[plot].origin.x
                            tick.wrappedValue = proxy.value(atX: x, as: Double.self).map { Int($0.rounded()) }
                        case .ended:
                            tick.wrappedValue = nil
                        }
                    }
            }
        }
    }
}

enum Ago {
    static func text(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 2 { return "maintenant" }
        return s < 60 ? "il y a \(s) s" : "il y a \(s / 60) min \(String(format: "%02d", s % 60))"
    }
}

extension Array where Element == HistoryPoint {
    func value(at tick: Int) -> Double? { first { $0.id == tick }?.value }
}

// MARK: - Grand graphique interactif

/// Historique en pourcentage ; le survol affiche la valeur et l'ancienneté du point.
struct DetailChart: View {
    let points: [HistoryPoint]
    let color: Color
    let xDomain: ClosedRange<Int>
    let secondsPerPoint: Double

    @State private var hovered: Int?

    var body: some View {
        let latest = points.last?.id ?? 0
        let selected = hovered.flatMap { h in points.min { abs($0.id - h) < abs($1.id - h) } }
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("t", p.id), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.id), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .foregroundStyle(color)
            }
            if let selected {
                RuleMark(x: .value("t", selected.id))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(Fmt.percent(selected.value))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                            Text(Ago.text(Double(latest - selected.id) * secondsPerPoint))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                PointMark(x: .value("t", selected.id), y: .value("v", selected.value))
                    .symbolSize(28)
                    .foregroundStyle(color)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v * 100))").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartHover($hovered)
    }
}

// MARK: - Carte de chaleur des cœurs

struct HeatmapHover: Equatable {
    let core: Int
    let load: Double
    /// Nombre d'échantillons depuis le plus récent.
    let age: Int
}

/// Une ligne par cœur, une colonne par échantillon : l'intensité de la couleur suit la charge.
struct CoreHeatmap: View {
    let history: [[Double]]
    let efficiencyCores: Int
    @Binding var hover: HeatmapHover?
    var columns = 60

    private let cell: CGFloat = 7
    private let gap: CGFloat = 2

    var body: some View {
        let cores = history.last?.count ?? 0
        let recent = Array(history.suffix(columns))
        let offset = columns - recent.count
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: gap) {
                ForEach(0..<cores, id: \.self) { i in
                    Text(Self.label(for: i, efficiencyCores: efficiencyCores))
                        .font(.system(size: 7.5, weight: hover?.core == i ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(hover?.core == i ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(height: cell)
                }
            }
            GeometryReader { geo in
                let width = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                Canvas { context, _ in
                    for column in 0..<columns {
                        let sample = column >= offset ? recent[column - offset] : nil
                        for core in 0..<cores {
                            let rect = CGRect(x: CGFloat(column) * (width + gap), y: CGFloat(core) * (cell + gap),
                                              width: width, height: cell)
                            let base = core < efficiencyCores ? Palette.download : Palette.cpu
                            let color: Color
                            if let load = sample?[safe: core] {
                                color = load < 0.02 ? Color.primary.opacity(0.06) : base.opacity(0.18 + 0.82 * min(load, 1))
                            } else {
                                color = Color.primary.opacity(0.04)
                            }
                            let path = Path(roundedRect: rect, cornerRadius: 1.5)
                            context.fill(path, with: .color(color))
                            if let hover, hover.core == core, hover.age == columns - 1 - column {
                                context.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 2),
                                               with: .color(.primary), lineWidth: 1)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let p) = phase else { hover = nil; return }
                    let column = Int(p.x / (width + gap)), core = Int(p.y / (cell + gap))
                    guard column >= offset, column < columns, core >= 0, core < cores,
                          let load = recent[column - offset][safe: core] else { hover = nil; return }
                    hover = HeatmapHover(core: core, load: load, age: columns - 1 - column)
                }
            }
            .frame(height: max(CGFloat(cores) * (cell + gap) - gap, 0))
        }
    }

    static func label(for index: Int, efficiencyCores: Int) -> String {
        index < efficiencyCores ? "E\(index + 1)" : "P\(index - efficiencyCores + 1)"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Débits (réseau, disque)

struct RateChart: View {
    struct Series: Identifiable {
        let id: String
        let points: [HistoryPoint]
        let color: Color
    }

    let series: [Series]
    let xDomain: ClosedRange<Int>
    @Binding var hovered: Int?

    var body: some View {
        let peak = max(series.flatMap(\.points).map(\.value).max() ?? 0, 50_000) * 1.15
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in
                    LineMark(x: .value("t", p.id), y: .value("v", p.value), series: .value("s", s.id))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.3))
                        .foregroundStyle(s.color)
                }
            }
            if let hovered {
                RuleMark(x: .value("t", hovered))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.25))
                ForEach(series) { s in
                    if let v = s.points.value(at: hovered) {
                        PointMark(x: .value("t", hovered), y: .value("v", v))
                            .symbolSize(18)
                            .foregroundStyle(s.color)
                    }
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...peak)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, peak / 2, peak]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.hairline)
            }
        }
        .chartHover($hovered)
    }
}

// MARK: - Anneau

struct DonutChart: View {
    struct Slice: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let slices: [Slice]
    /// Segment survolé (anneau ou légende) : mis en avant, les autres s'estompent.
    @Binding var highlighted: String?

    var body: some View {
        Chart(slices) { slice in
            let isOn = highlighted == nil || highlighted == slice.id
            SectorMark(angle: .value("v", slice.value),
                       innerRadius: .ratio(highlighted == slice.id ? 0.64 : 0.72),
                       outerRadius: .ratio(highlighted == slice.id ? 1 : 0.94),
                       angularInset: 1.2)
                .cornerRadius(2)
                .foregroundStyle(slice.color.opacity(isOn ? 1 : 0.3))
        }
        .chartLegend(.hidden)
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .overlay {
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let p) = phase else { highlighted = nil; return }
                        highlighted = slice(at: p, in: geo.size)
                    }
            }
        }
    }

    /// Le premier secteur part du haut et tourne dans le sens horaire.
    private func slice(at point: CGPoint, in size: CGSize) -> String? {
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let radius = min(size.width, size.height) / 2
        let distance = hypot(dx, dy)
        guard distance > radius * 0.55, distance <= radius * 1.04 else { return nil }
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let total = slices.reduce(0) { $0 + $1.value }
        guard total > 0 else { return nil }
        let target = angle / (2 * .pi) * total
        var cumulative = 0.0
        for slice in slices {
            cumulative += slice.value
            if target <= cumulative { return slice.id }
        }
        return slices.last?.id
    }
}

// MARK: - Petits éléments

struct LegendRow: View {
    let color: Color
    let label: String
    let value: String
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(isHighlighted ? .primary : .secondary)
            Spacer(minLength: 6)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 11, weight: isHighlighted ? .medium : .regular))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(isHighlighted ? color.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MiniBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct AppIcon: View {
    let path: String?
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: IconCache.shared.icon(for: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

// MARK: - Icône de processus

struct ProcessIconView: View {
    let icon: ProcessIcon
    var size: CGFloat = 18

    var body: some View {
        switch icon {
        case .file(let path): AppIcon(path: path, size: size)
        case .badge(let badge): BadgeIcon(badge: badge, size: size)
        }
    }
}

/// Pastille sobre aux couleurs de l'outil, à la taille optique d'une icône d'app.
private struct BadgeIcon: View {
    let badge: RuntimeBadge
    let size: CGFloat

    var body: some View {
        let inner = size * 0.84
        let background = Color(hex: badge.background)
        ZStack {
            shape.fill(background)
            shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
            Text(badge.text)
                .font(.system(size: inner * (badge.text.count >= 3 ? 0.3 : badge.text.count == 2 ? 0.42 : 0.55),
                              weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: badge.foreground))
                .minimumScaleFactor(0.5)
        }
        .frame(width: inner, height: inner)
        .frame(width: size, height: size)
    }

    private var shape: AnyInsettableShape {
        switch badge.shape {
        case .circle: AnyInsettableShape(Circle())
        case .rounded: AnyInsettableShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        case .hexagon: AnyInsettableShape(Hexagon())
        }
    }
}

private struct Hexagon: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = min(r.width, r.height) / 2
        let center = CGPoint(x: r.midX, y: r.midY)
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat.pi / 3 * CGFloat(i) - CGFloat.pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Hexagon { Hexagon(inset: inset + amount) }
}

/// Efface le type concret d'une forme « insettable » (pour fill + strokeBorder).
private struct AnyInsettableShape: InsettableShape {
    private let base: any InsettableShape

    init(_ base: some InsettableShape) { self.base = base }

    func path(in rect: CGRect) -> Path { base.path(in: rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { AnyInsettableShape(base.inset(by: amount)) }
}
