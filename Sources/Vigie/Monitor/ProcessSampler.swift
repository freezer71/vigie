import Darwin
import Foundation

struct ProcessItem: Identifiable, Sendable, Hashable {
    let id: pid_t
    /// Nom parlant (« Serveur Next.js », « Vite dev », « Claude Code »…).
    let name: String
    let path: String
    /// Répertoire de travail lisible, pour les outils lancés depuis un terminal.
    let detail: String?
    let cwd: String?
    let icon: ProcessIcon
    /// Application à laquelle le processus est rattaché (processus « responsable », ou bundle .app parent).
    let groupKey: String
    let groupName: String
    let groupAppPath: String?
    let groupIcon: ProcessIcon
    /// Pourcentage d'un cœur (peut dépasser 100, comme dans le Moniteur d'activité).
    var cpu: Double
    var memory: UInt64
    var diskRead: Double
    var diskWrite: Double

    var disk: Double { diskRead + diskWrite }
}

struct AppGroup: Identifiable, Sendable {
    let id: String
    let name: String
    let appPath: String?
    let icon: ProcessIcon
    var processes: [ProcessItem] = []
    var cpu: Double = 0
    var memory: UInt64 = 0
    var diskRead: Double = 0
    var diskWrite: Double = 0

    var disk: Double { diskRead + diskWrite }

    static func make(from items: [ProcessItem]) -> [AppGroup] {
        var groups: [String: AppGroup] = [:]
        for item in items {
            groups[item.groupKey, default: AppGroup(id: item.groupKey, name: item.groupName, appPath: item.groupAppPath, icon: item.groupIcon)].add(item)
        }
        return Array(groups.values)
    }

    private mutating func add(_ item: ProcessItem) {
        processes.append(item)
        cpu += item.cpu
        memory += item.memory
        diskRead += item.diskRead
        diskWrite += item.diskWrite
    }
}

struct ProcessSnapshot: Sendable {
    var items: [ProcessItem] = []
    /// Processus d'autres utilisateurs (root, _windowserver…) illisibles sans droits admin.
    var inaccessible = 0
}

private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
/// API privée utilisée par le Moniteur d'activité pour rattacher un processus à son app
/// (ex. les WebContent de Safari). Chargée dynamiquement : absente = pas de regroupement.
private let responsiblePid: ResponsibleFn? = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
    return unsafeBitCast(symbol, to: ResponsibleFn.self)
}()

final class ProcessSampler {
    private struct Identity {
        let start: UInt64
        let name: String
        let path: String
        let appPath: String?
        let detail: String?
        let cwd: String?
        let icon: ProcessIcon
    }
    private struct Counters { let cpuNs: Double; let read: UInt64; let write: UInt64 }

    private var identities: [pid_t: Identity] = [:]
    private var previous: [pid_t: Counters] = [:]
    private var lastTime: UInt64 = 0
    private var appNames: [String: String] = [:]
    private let ticksToNs: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    func sample() -> ProcessSnapshot {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastTime > 0 ? Double(now - lastTime) : 0
        lastTime = now

        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return ProcessSnapshot() }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }

        struct Raw { let pid: pid_t; let identity: Identity; let counters: Counters; let memory: UInt64 }
        var raws: [Raw] = []
        var snapshot = ProcessSnapshot()
        var nextCounters: [pid_t: Counters] = [:]
        var nextIdentities: [pid_t: Identity] = [:]

        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { snapshot.inaccessible += 1; continue }

            let identity: Identity
            if let known = identities[pid], known.start == usage.ri_proc_start_abstime {
                identity = known
            } else {
                identity = resolveIdentity(pid: pid, start: usage.ri_proc_start_abstime)
            }
            let counters = Counters(cpuNs: Double(usage.ri_user_time + usage.ri_system_time) * ticksToNs,
                                    read: usage.ri_diskio_bytesread,
                                    write: usage.ri_diskio_byteswritten)
            nextIdentities[pid] = identity
            nextCounters[pid] = counters
            raws.append(Raw(pid: pid, identity: identity, counters: counters, memory: usage.ri_phys_footprint))
        }

        for raw in raws {
            var cpu = 0.0, read = 0.0, write = 0.0
            if elapsed > 0, let before = previous[raw.pid] {
                cpu = max(0, raw.counters.cpuNs - before.cpuNs) / elapsed * 100
                let seconds = elapsed / 1e9
                read = Double(raw.counters.read &- before.read) / seconds
                write = Double(raw.counters.write &- before.write) / seconds
                if raw.counters.read < before.read || raw.counters.write < before.write { read = 0; write = 0 }
            }

            // Rattachement : app du processus responsable, sinon son propre bundle, sinon lui-même.
            var owner = raw.identity
            if let responsiblePid, case let parent = responsiblePid(raw.pid), parent > 0, parent != raw.pid,
               let parentIdentity = nextIdentities[parent] {
                owner = parentIdentity
            }
            if owner.appPath == nil, raw.identity.appPath != nil { owner = raw.identity }

            let key = owner.appPath ?? "proc:\(owner.path.isEmpty ? owner.name : owner.path)"
            let groupName = owner.appPath.map(appName(for:)) ?? owner.name
            let groupIcon: ProcessIcon = owner.appPath.map { .file($0) } ?? owner.icon

            snapshot.items.append(ProcessItem(id: raw.pid, name: raw.identity.name, path: raw.identity.path,
                                              detail: raw.identity.detail, cwd: raw.identity.cwd, icon: raw.identity.icon,
                                              groupKey: key, groupName: groupName, groupAppPath: owner.appPath,
                                              groupIcon: groupIcon,
                                              cpu: cpu, memory: raw.memory, diskRead: read, diskWrite: write))
        }

        previous = nextCounters
        identities = nextIdentities
        return snapshot
    }

    private func resolveIdentity(pid: pid_t, start: UInt64) -> Identity {
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = length > 0 ? String(cString: pathBuffer) : ""
        var name = (path as NSString).lastPathComponent
        if name.isEmpty {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            name = String(cString: nameBuffer)
        }
        // Bundle .app le plus extérieur (Chrome Helper.app → Google Chrome.app).
        var appPath: String?
        if let range = path.range(of: ".app/") {
            appPath = String(path[..<range.lowerBound]) + ".app"
        }
        // Les processus d'apps gardent le nom et l'icône de leur bundle ; les autres (node, python,
        // binaires de terminal…) sont identifiés via leur ligne de commande et leur dossier de travail.
        guard appPath == nil else {
            return Identity(start: start, name: name, path: path, appPath: appPath, detail: nil, cwd: nil, icon: .file(path))
        }
        let description = ProcessIdentifier.describe(pid: pid, name: name, path: path)
        return Identity(start: start, name: description.title, path: path, appPath: nil,
                        detail: description.detail, cwd: description.cwd, icon: description.icon)
    }

    private func appName(for appPath: String) -> String {
        if let cached = appNames[appPath] { return cached }
        var name = FileManager.default.displayName(atPath: appPath)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        appNames[appPath] = name
        return name
    }
}
