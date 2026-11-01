import AppKit
import Foundation
import Observation

// MARK: - Préférences

enum Prefs {
    static let showCPU = "menubar.cpu"
    static let showGPU = "menubar.gpu"
    static let showMemory = "menubar.memory"
    static let showNetwork = "menubar.network"
    static let showTemperature = "menubar.temperature"
    static let interval = "refresh.interval"

    static func register() {
        UserDefaults.standard.register(defaults: [
            showCPU: true, showGPU: true, showMemory: true, showNetwork: false, showTemperature: true,
            interval: 2.0,
        ])
    }
}

// MARK: - Infos statiques

struct SystemInfo: Sendable {
    let chip: String
    let cpuCores: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let gpuCores: Int
    let memory: UInt64
    let osVersion: String
    let bootDate: Date

    static func load() -> SystemInfo {
        let perfLevels = sysctlInt("hw.nperflevels") ?? 1
        let gpu = GPUSampler.staticInfo()
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        let bootDate = sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0
            ? Date(timeIntervalSince1970: TimeInterval(boot.tv_sec)) : Date()
        return SystemInfo(
            chip: sysctlString("machdep.cpu.brand_string") ?? gpu.model,
            cpuCores: ProcessInfo.processInfo.processorCount,
            performanceCores: perfLevels > 1 ? sysctlInt("hw.perflevel0.logicalcpu") ?? 0 : ProcessInfo.processInfo.processorCount,
            efficiencyCores: perfLevels > 1 ? sysctlInt("hw.perflevel1.logicalcpu") ?? 0 : 0,
            gpuCores: gpu.cores,
            memory: ProcessInfo.processInfo.physicalMemory,
            osVersion: "macOS \(v.majorVersion).\(v.minorVersion)",
            bootDate: bootDate
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }
}

// MARK: - Échantillonnage

struct Snapshot: Sendable {
    var cpu: CPUStats
    var memory: MemoryStats
    var gpu: GPUStats
    var network: NetworkStats
    var disk: DiskStats
    var battery: BatteryStats?
    var temperature: TemperatureStats
    var processes: ProcessSnapshot?
}

/// Regroupe les échantillonneurs ; utilisé uniquement depuis la file série de `SystemMonitor`.
final class SamplerHub: @unchecked Sendable {
    /// La température est la mesure la plus chère (~12 ms, 45 capteurs) et varie lentement :
    /// relue au plus toutes les 6 s.
    private func sampleTemperature() -> TemperatureStats {
        let now = DispatchTime.now().uptimeNanoseconds
        if lastTemperatureRead == 0 || now - lastTemperatureRead >= 5_900_000_000 {
            lastTemperature = temperature.sample()
            lastTemperatureRead = now
        }
        return lastTemperature
    }

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let network = NetworkSampler()
    private let disk = DiskSampler()
    private let processes = ProcessSampler()
    private let temperature = TemperatureSampler()
    private var lastTemperature = TemperatureStats()
    private var lastTemperatureRead: UInt64 = 0

    func sample(includeProcesses: Bool) -> Snapshot {
        Snapshot(cpu: cpu.sample(), memory: memory.sample(), gpu: gpu.sample(),
                 network: network.sample(), disk: disk.sample(includeCapacity: includeProcesses), battery: BatterySampler.sample(),
                 temperature: sampleTemperature(),
                 processes: includeProcesses ? processes.sample() : nil)
    }
}

struct HistoryPoint: Identifiable, Sendable, Equatable {
    let id: Int
    let value: Double
}

@MainActor
@Observable
final class SystemMonitor {
    static let historyLength = 90

    let info = SystemInfo.load()

    private(set) var tick = 0
    private(set) var cpu = CPUStats()
    private(set) var memory = MemoryStats()
    private(set) var gpu = GPUStats()
    private(set) var network = NetworkStats()
    private(set) var disk = DiskStats()
    private(set) var battery: BatteryStats?
    private(set) var temperature = TemperatureStats()
    private(set) var thermal: ProcessInfo.ThermalState = .nominal

    private(set) var cpuHistory: [HistoryPoint] = []
    private(set) var gpuHistory: [HistoryPoint] = []
    private(set) var memoryHistory: [HistoryPoint] = []
    private(set) var downloadHistory: [HistoryPoint] = []
    private(set) var uploadHistory: [HistoryPoint] = []
    private(set) var diskReadHistory: [HistoryPoint] = []
    private(set) var diskWriteHistory: [HistoryPoint] = []
    /// Charge de chaque cœur, une colonne par échantillon (du plus ancien au plus récent).
    private(set) var coreHistory: [[Double]] = []

    private(set) var processes: [ProcessItem] = []
    private(set) var apps: [AppGroup] = []
    private(set) var inaccessibleProcesses = 0

    var xDomain: ClosedRange<Int> { (tick - Self.historyLength + 1)...max(tick, 1) }
    var historySpanLabel: String { "\(Int((interval * Double(Self.historyLength) / 60).rounded())) dernières minutes" }

    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let hub = SamplerHub()
    @ObservationIgnored private let queue = DispatchQueue(label: "dev.tharsan.vigie.sampler", qos: .utility)
    @ObservationIgnored private var detailVisible = false
    @ObservationIgnored private var sampling = false
    @ObservationIgnored private(set) var interval: TimeInterval = 0

    func start() {
        applyInterval()
        refresh()
        // Écran en veille ou session verrouillée : plus personne ne regarde, on suspend tout.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyInterval() }
        }
    }

    /// Les processus ne sont échantillonnés que lorsque le panneau détaillé est ouvert.
    func setDetailVisible(_ visible: Bool) {
        detailVisible = visible
        guard visible else { return }
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func resume() {
        guard timer == nil else { return }
        interval = 0          // force la recréation du minuteur
        applyInterval()
        refresh()
    }

    private func applyInterval() {
        let wanted = max(UserDefaults.standard.double(forKey: Prefs.interval), 1)
        guard wanted != interval else { return }
        interval = wanted
        timer?.invalidate()
        let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = wanted * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !sampling else { return }
        sampling = true
        let includeProcesses = detailVisible || tick == 0
        let hub = hub
        queue.async { [weak self] in
            let snapshot = hub.sample(includeProcesses: includeProcesses)
            Task { @MainActor in self?.apply(snapshot) }
        }
    }

    private func apply(_ s: Snapshot) {
        sampling = false
        tick += 1
        cpu = s.cpu
        memory = s.memory
        gpu = s.gpu
        network = s.network
        disk = s.disk
        battery = s.battery
        temperature = s.temperature
        thermal = ProcessInfo.processInfo.thermalState

        push(&cpuHistory, s.cpu.total)
        push(&gpuHistory, s.gpu.utilization)
        push(&memoryHistory, s.memory.usage)
        push(&downloadHistory, s.network.download)
        push(&uploadHistory, s.network.upload)
        push(&diskReadHistory, s.disk.read)
        push(&diskWriteHistory, s.disk.write)
        if !s.cpu.cores.isEmpty {
            coreHistory.append(s.cpu.cores)
            if coreHistory.count > Self.historyLength { coreHistory.removeFirst(coreHistory.count - Self.historyLength) }
        }

        if let p = s.processes {
            processes = p.items
            apps = AppGroup.make(from: p.items)
            inaccessibleProcesses = p.inaccessible
        }
        onUpdate?()
    }

    private func push(_ history: inout [HistoryPoint], _ value: Double) {
        history.append(HistoryPoint(id: tick, value: value))
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    // MARK: Actions sur les processus

    func terminate(pids: [pid_t], appPath: String?, force: Bool) {
        if let appPath {
            let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == appPath }
            if !running.isEmpty {
                for app in running {
                    if force { app.forceTerminate() } else { app.terminate() }
                }
                return
            }
        }
        pids.forEach { kill($0, force ? SIGKILL : SIGTERM) }
    }
}
