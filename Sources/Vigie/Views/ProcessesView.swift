import SwiftUI

struct ProcessesView: View {
    let monitor: SystemMonitor

    enum SortKey { case cpu, memory, disk }

    @State private var query = UserDefaults.standard.string(forKey: "debugQuery") ?? ""
    @State private var sort: SortKey = .cpu
    @State private var grouped = true
    @State private var expanded: Set<String> = []

    struct Row: Identifiable {
        let id: String
        let name: String
        let detail: String?
        let icon: ProcessIcon
        let path: String?
        let cwd: String?
        let appPath: String?
        let pids: [pid_t]
        let cpu: Double
        let memory: UInt64
        let disk: Double
        var children: [Row] = []
    }

    var body: some View {
        VStack(spacing: 10) {
            // Clic sur une app de la barre : filtre la liste sur elle (re-clic pour annuler).
            MemorySplitCard(apps: monitor.apps, selected: query) { name in
                query = (query == name) ? "" : name
            }
            controls
            header
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        // Pendant une recherche, on déplie les groupes pour montrer les processus trouvés.
                        let searching = !needle.isEmpty
                        let open = expanded.contains(row.id) || (searching && row.children.count > 1)
                        ProcessRow(row: row, depth: 0, isExpanded: open, monitor: monitor) {
                            withAnimation(.snappy) {
                                if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
                            }
                        }
                        if open {
                            ForEach(searching ? row.children.filter(matches) : row.children) { child in
                                ProcessRow(row: child, depth: 1, isExpanded: false, monitor: monitor, toggle: nil)
                            }
                        }
                    }
                }
            }
            footer
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: Données

    private var needle: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private func matches(_ row: Row) -> Bool {
        row.name.lowercased().contains(needle) || (row.detail?.lowercased().contains(needle) ?? false)
    }

    private var rows: [Row] {
        var result: [Row]
        if grouped {
            result = monitor.apps.map { app in
                Row(id: app.id, name: app.name, detail: nil, icon: app.icon, path: app.appPath, cwd: nil, appPath: app.appPath,
                    pids: app.processes.map(\.id), cpu: app.cpu, memory: app.memory, disk: app.disk,
                    children: sorted(app.processes.map(row(for:))))
            }
        } else {
            result = monitor.processes.map(row(for:))
        }
        if !needle.isEmpty {
            result = result.filter { matches($0) || $0.children.contains(where: matches) }
        }
        return Array(sorted(result).prefix(150))
    }

    private func row(for p: ProcessItem) -> Row {
        Row(id: "\(p.id)", name: p.name, detail: p.detail, icon: p.icon, path: p.path, cwd: p.cwd, appPath: nil, pids: [p.id],
            cpu: p.cpu, memory: p.memory, disk: p.disk)
    }

    private func sorted(_ rows: [Row]) -> [Row] {
        switch sort {
        case .cpu: rows.sorted { ($0.cpu, $0.memory) > ($1.cpu, $1.memory) }
        case .memory: rows.sorted { $0.memory > $1.memory }
        case .disk: rows.sorted { ($0.disk, $0.cpu) > ($1.disk, $1.cpu) }
        }
    }

    // MARK: Contrôles

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Rechercher une app ou un processus", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Picker("", selection: $grouped) {
                Text("Apps").tag(true)
                Text("Processus").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(grouped ? "\(monitor.apps.count) apps" : "\(monitor.processes.count) processus")
                .frame(maxWidth: .infinity, alignment: .leading)
            sortButton("CPU", key: .cpu).frame(width: 96, alignment: .trailing)
            sortButton("Mémoire", key: .memory).frame(width: 66, alignment: .trailing)
            sortButton("Disque", key: .disk).frame(width: 62, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
    }

    private func sortButton(_ title: String, key: SortKey) -> some View {
        Button {
            withAnimation(.snappy) { sort = key }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sort == key { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)) }
            }
            .foregroundStyle(sort == key ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 8))
            Text("\(monitor.inaccessibleProcesses) processus système (root) non mesurables sans droits admin")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

// MARK: - Ligne

private struct ProcessRow: View {
    let row: ProcessesView.Row
    let depth: Int
    let isExpanded: Bool
    let monitor: SystemMonitor
    let toggle: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if depth > 0 {
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 16).padding(.leading, 10)
                }
                ProcessIconView(icon: row.icon, size: depth > 0 ? 16 : 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name)
                        .font(.system(size: depth > 0 ? 11 : 12))
                        .foregroundStyle(depth > 0 ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.children.count > 1 {
                        Text("\(row.children.count) processus")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    } else if let detail = row.detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if !row.children.isEmpty, row.children.count > 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                MiniBar(value: min(row.cpu / 100, 1), color: Palette.level(row.cpu / 100, base: Palette.cpu), height: 3)
                    .frame(width: 36)
                Text(Fmt.cpu(row.cpu))
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(width: 96, alignment: .trailing)
            Text(Fmt.bytes(row.memory))
                .frame(width: 66, alignment: .trailing)
                .foregroundStyle(row.memory > 2_000_000_000 ? AnyShapeStyle(Palette.memory) : AnyShapeStyle(.primary))
            Text(row.disk >= 1_000 ? Fmt.rate(row.disk) : "—")
                .frame(width: 62, alignment: .trailing)
                .foregroundStyle(row.disk >= 1_000 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, depth > 0 ? 3 : 5)
        .background(hovering ? Palette.fill : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { toggle?() }
        .help(row.cwd ?? row.path ?? row.name)
        .contextMenu {
            Button("Quitter") { monitor.terminate(pids: row.pids, appPath: row.appPath, force: false) }
            Button("Forcer à quitter") { monitor.terminate(pids: row.pids, appPath: row.appPath, force: true) }
            Divider()
            if let cwd = row.cwd {
                Button("Ouvrir le dossier du projet") { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
            }
            if let path = row.path, !path.isEmpty {
                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Button("Copier le PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.pids.map(String.init).joined(separator: " "), forType: .string)
            }
        }
    }
}

// MARK: - Répartition mémoire

/// Barre fine empilée : la part de chaque app dans la mémoire occupée par les apps mesurables.
private struct MemorySplitCard: View {
    let apps: [AppGroup]
    let selected: String
    let onSelect: (String) -> Void

    @State private var hovered: String?

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let memory: UInt64
        let processes: Int
        let color: Color
        let selectable: Bool
    }

    var body: some View {
        let sorted = apps.sorted { $0.memory > $1.memory }
        let total = max(Double(sorted.reduce(UInt64(0)) { $0 + $1.memory }), 1)
        let entries = makeEntries(sorted)
        let active = entries.first { $0.id == hovered }

        Panel(title: "Qui occupe la mémoire") {
            // Au survol : nom, taille, part et nombre de processus de l'app pointée.
            Group {
                if let active {
                    Text("\(active.name) · \(Fmt.bytes(active.memory)) · \(Fmt.percent(Double(active.memory) / total)) · \(active.processes) processus")
                } else {
                    Text(Fmt.bytes(UInt64(total)))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
        } content: {
            GeometryReader { geo in
                let usable = geo.size.width - 1.5 * CGFloat(entries.count - 1)
                HStack(spacing: 1.5) {
                    ForEach(entries) { entry in
                        Rectangle()
                            .fill(entry.color.opacity(hovered == nil || hovered == entry.id ? 1 : 0.3))
                            .frame(width: max(0, usable * Double(entry.memory) / total))
                            .contentShape(Rectangle())
                            .onHover { inside in hover(entry.id, inside) }
                            .onTapGesture { if entry.selectable { onSelect(entry.name) } }
                    }
                }
            }
            .frame(height: hovered == nil ? 8 : 12)
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: hovered)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 2) {
                ForEach(entries) { entry in
                    let isOn = hovered == entry.id || (entry.selectable && selected == entry.name)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(entry.color).frame(width: 8, height: 8)
                        Text(entry.name).lineLimit(1).foregroundStyle(entry.selectable ? .primary : .secondary)
                        Spacer(minLength: 4)
                        Text(Fmt.bytes(entry.memory)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isOn ? entry.color.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                    .onHover { inside in hover(entry.id, inside) }
                    .onTapGesture { if entry.selectable { onSelect(entry.name) } }
                }
            }
            .font(.system(size: 11))
        }
    }

    private func hover(_ id: String, _ inside: Bool) {
        if inside { hovered = id } else if hovered == id { hovered = nil }
    }

    private func makeEntries(_ sorted: [AppGroup]) -> [Entry] {
        let colors = Palette.series
        var entries = sorted.prefix(5).enumerated().map { i, app in
            Entry(id: app.id, name: app.name, memory: app.memory, processes: app.processes.count,
                  color: colors[i % colors.count], selectable: true)
        }
        let rest = sorted.dropFirst(5)
        entries.append(Entry(id: "others", name: "Autres", memory: rest.reduce(0) { $0 + $1.memory },
                             processes: rest.reduce(0) { $0 + $1.processes.count },
                             color: Color.primary.opacity(0.15), selectable: false))
        return entries
    }
}
