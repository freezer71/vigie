import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let monitor: SystemMonitor

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        monitor.onUpdate = { [weak self] in self?.scheduleRender() }
        // Cette notification peut être émise de façon synchrone en pleine mise en page du texte
        // (registerDefaults appelé par AppKit) : on ne rend jamais directement depuis elle.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lastPrefs != self.currentPrefs() else { return }
                self.scheduleRender()
            }
        }
        scheduleRender()

        // Débogage : `open Vigie.app --args -debugOpen overview|processes|settings` ouvre le panneau au lancement.
        // `-debugOpenDelay 190` : attend N secondes (historiques remplis, pour les captures d'écran).
        if UserDefaults.standard.string(forKey: "debugOpen") != nil {
            let delay = UserDefaults.standard.double(forKey: "debugOpenDelay")
            let openAt = delay > 0 ? delay : 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + openAt) { [weak self] in self?.togglePopover() }
            // `-debugCloseAfter 10` : referme le panneau après N secondes (mesures de consommation).
            let closeAfter = UserDefaults.standard.double(forKey: "debugCloseAfter")
            if closeAfter > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + openAt + closeAfter) { [weak self] in self?.popover.performClose(nil) }
                // `-debugReopenAfter 5` : rouvre N secondes plus tard (coût d'une réouverture).
                let reopenAfter = UserDefaults.standard.double(forKey: "debugReopenAfter")
                if reopenAfter > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + openAt + closeAfter + reopenAfter) { [weak self] in self?.togglePopover() }
                }
            }
        }
    }

    // MARK: Clics

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Construit à la première ouverture (~150 ms), puis réutilisé : fermé, il ne se met pas
            // à jour et ne coûte rien (mesuré) ; le reconstruire à chaque fois créait un pic à l'ouverture.
            if popover.contentViewController == nil {
                let host = NSHostingController(rootView: DashboardView(monitor: monitor))
                host.sizingOptions = [.preferredContentSize]
                popover.contentViewController = host
            }
            monitor.setDetailVisible(true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Ouvrir le Moniteur d'activité", action: #selector(openActivityMonitor), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Vigie", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { monitor.setDetailVisible(false) }
    }

    // MARK: Rendu de la barre des menus

    private var renderPending = false
    private var lastTitle = ""
    private var lastPrefs: [Bool] = []

    private func currentPrefs() -> [Bool] {
        [Prefs.showCPU, Prefs.showGPU, Prefs.showMemory, Prefs.showNetwork, Prefs.showTemperature]
            .map { UserDefaults.standard.bool(forKey: $0) }
    }

    /// Regroupe les demandes et rend au prochain tour de boucle, hors de toute mise en page en cours.
    private func scheduleRender() {
        guard !renderPending else { return }
        renderPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderPending = false
            self.render()
        }
    }

    /// Texte simple, couleurs système : s'adapte seul au thème clair / sombre de la barre.
    private func render() {
        guard let button = item.button else { return }
        lastPrefs = currentPrefs()
        let defaults = UserDefaults.standard

        var parts: [(String, String)] = []
        if defaults.bool(forKey: Prefs.showCPU) { parts.append(("CPU", percent(monitor.cpu.total))) }
        if defaults.bool(forKey: Prefs.showGPU) { parts.append(("GPU", percent(monitor.gpu.utilization))) }
        if defaults.bool(forKey: Prefs.showMemory) { parts.append(("RAM", percent(monitor.memory.usage))) }
        if defaults.bool(forKey: Prefs.showTemperature), let celsius = monitor.temperature.soc {
            parts.append(("", "\(Int(celsius.rounded()))°"))
        }
        if defaults.bool(forKey: Prefs.showNetwork) {
            parts.append(("↓", Fmt.shortRate(monitor.network.download)))
            parts.append(("↑", Fmt.shortRate(monitor.network.upload)))
        }
        if parts.isEmpty { parts.append(("CPU", percent(monitor.cpu.total))) }

        // Noir + opacité dans une image « template » : macOS la teinte en blanc ou en noir selon la barre.
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let title = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: "  ", attributes: [.font: valueFont])) }
            if !part.0.isEmpty { title.append(NSAttributedString(string: part.0 + " ", attributes: [
                .font: labelFont, .foregroundColor: NSColor.black.withAlphaComponent(0.6), .baselineOffset: 0.5,
            ])) }
            title.append(NSAttributedString(string: part.1, attributes: [
                .font: valueFont, .foregroundColor: NSColor.black,
            ]))
        }
        // Rien n'a changé à l'affichage : on garde l'image actuelle.
        guard title.string != lastTitle || button.image == nil else { return }
        lastTitle = title.string

        // Rendu une seule fois dans un bitmap : AppKit recopie l'élément dans chaque barre de menus
        // (un par écran) et redessinerait sinon le texte à chaque copie.
        let textSize = title.size()
        let size = NSSize(width: ceil(textSize.width), height: NSStatusBar.system.thickness)
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = size   // avant le contexte : il dessine alors en points, à l'échelle de l'écran
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        title.draw(at: NSPoint(x: 0, y: ((size.height - textSize.height) / 2).rounded()))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        button.image = image
        button.toolTip = "Vigie — clic : détails · clic droit : menu"
    }

    /// Largeur fixe (« \u{2007} » = espace de la largeur d'un chiffre) pour que la barre ne tremble pas.
    private func percent(_ value: Double) -> String {
        let n = Int((value * 100).rounded())
        return String(repeating: "\u{2007}", count: n < 10 ? 2 : n < 100 ? 1 : 0) + "\(n)%"
    }
}
