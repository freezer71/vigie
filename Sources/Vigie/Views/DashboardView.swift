import ServiceManagement
import SwiftUI

struct DashboardView: View {
    let monitor: SystemMonitor

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Aperçu", processes = "Processus", settings = "Réglages"
        var id: String { rawValue }
    }

    /// Le panneau est recréé à chaque ouverture : on rouvre sur le dernier onglet consulté.
    @State private var tab: Tab = {
        let saved = UserDefaults.standard.string(forKey: "debugOpen") ?? UserDefaults.standard.string(forKey: "ui.tab")
        switch saved {
        case "processes": return .processes
        case "settings": return .settings
        default: return .overview
        }
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch tab {
                case .overview: OverviewView(monitor: monitor)
                case .processes: ProcessesView(monitor: monitor)
                case .settings: SettingsView()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: 440, height: 700)
        // Atténue ce qui transparaît derrière le panneau, sans perdre le matériau natif.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.info.chip)
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(monitor.info.performanceCores) cœurs performance · \(monitor.info.efficiencyCores) efficacité · \(Fmt.bytes(monitor.info.memory))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(monitor.info.osVersion).font(.system(size: 11, weight: .medium))
                    Text("allumé depuis \(Fmt.duration(since: monitor.info.bootDate))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: tab) { _, new in
                let key: String = switch new { case .overview: "overview"; case .processes: "processes"; case .settings: "settings" }
                UserDefaults.standard.set(key, forKey: "ui.tab")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            Button("Ouvrir le Moniteur d'activité") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
    }
}

// MARK: - Réglages

struct SettingsView: View {
    @AppStorage(Prefs.showCPU) private var showCPU = true
    @AppStorage(Prefs.showGPU) private var showGPU = true
    @AppStorage(Prefs.showMemory) private var showMemory = true
    @AppStorage(Prefs.showNetwork) private var showNetwork = false
    @AppStorage(Prefs.showTemperature) private var showTemperature = true
    @AppStorage(Prefs.interval) private var interval = 2.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Afficher dans la barre des menus") {
                Toggle("Processeur", isOn: $showCPU)
                Toggle("Carte graphique", isOn: $showGPU)
                Toggle("Mémoire", isOn: $showMemory)
                Toggle("Température de la puce", isOn: $showTemperature)
                Toggle("Réseau", isOn: $showNetwork)
            }
            Section {
                Picker("Actualisation", selection: $interval) {
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
            } footer: {
                Text("Les processus ne sont mesurés que lorsque ce panneau est ouvert.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Ouvrir Vigie à la connexion", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            } footer: {
                if let loginError {
                    Text(loginError).font(.system(size: 10)).foregroundStyle(Palette.critical)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .controlSize(.small)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Impossible : \(error.localizedDescription). Installe l'app dans /Applications."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
