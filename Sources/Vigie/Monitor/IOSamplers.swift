import Darwin
import Foundation
import IOKit
import IOKit.ps

// MARK: - Réseau

struct NetworkStats: Sendable, Equatable {
    /// Octets par seconde.
    var download: Double = 0
    var upload: Double = 0
    var totalReceived: UInt64 = 0
    var totalSent: UInt64 = 0
}

/// Compteurs 64 bits des interfaces physiques (`en*`) via `NET_RT_IFLIST2`.
final class NetworkSampler {
    private var last: (rx: UInt64, tx: UInt64, time: UInt64)?

    func sample() -> NetworkStats {
        let (rx, tx) = counters()
        let now = DispatchTime.now().uptimeNanoseconds
        defer { last = (rx, tx, now) }
        var stats = NetworkStats(totalReceived: rx, totalSent: tx)
        if let last, now > last.time {
            let seconds = Double(now - last.time) / 1e9
            stats.download = Double(rx &- last.rx) / seconds
            stats.upload = Double(tx &- last.tx) / seconds
            if rx < last.rx || tx < last.tx { stats.download = 0; stats.upload = 0 }
        }
        return stats
    }

    private func counters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if info.ifm_flags & IFF_LOOPBACK == 0,
                       if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil,
                       String(cString: nameBuffer).hasPrefix("en") {
                        rx += info.ifm_data.ifi_ibytes
                        tx += info.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (rx, tx)
    }
}

// MARK: - Disque

struct DiskStats: Sendable, Equatable {
    var read: Double = 0
    var write: Double = 0
    var capacity: UInt64 = 0
    var available: UInt64 = 0
    var volumeName = "Macintosh HD"
    var usage: Double { capacity > 0 ? Double(capacity - min(available, capacity)) / Double(capacity) : 0 }
}

final class DiskSampler {
    private var last: (read: UInt64, write: UInt64, time: UInt64)?
    private var cachedVolume: (capacity: UInt64, available: UInt64, name: String, time: UInt64)?

    /// `includeCapacity` : l'espace libre « utile » fait travailler CacheDelete (calcul du purgeable) ;
    /// on ne le demande que lorsque le panneau est affiché, au plus une fois par minute.
    func sample(includeCapacity: Bool) -> DiskStats {
        let (read, write) = ioCounters()
        let now = DispatchTime.now().uptimeNanoseconds
        defer { last = (read, write, now) }
        var stats = DiskStats()
        if let last, now > last.time, read >= last.read, write >= last.write {
            let seconds = Double(now - last.time) / 1e9
            stats.read = Double(read - last.read) / seconds
            stats.write = Double(write - last.write) / seconds
        }
        if includeCapacity, cachedVolume == nil || now - cachedVolume!.time > 60_000_000_000 {
            let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]
            if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
                cachedVolume = (UInt64(values.volumeTotalCapacity ?? 0),
                                UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0)),
                                values.volumeLocalizedName ?? "Macintosh HD", now)
            }
        }
        if let volume = cachedVolume {
            stats.capacity = volume.capacity
            stats.available = volume.available
            stats.volumeName = volume.name
        }
        return stats
    }

    private func ioCounters() -> (UInt64, UInt64) {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            if let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
        }
        return (read, write)
    }
}

// MARK: - Batterie

struct BatteryStats: Sendable, Equatable {
    var level: Double
    var isCharging: Bool
    var isPluggedIn: Bool
    /// Minutes avant vide (sur batterie) ou avant charge complète (sur secteur).
    var minutesRemaining: Int?
}

enum BatterySampler {
    static func sample() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(d[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int
            return BatteryStats(level: Double(current) / Double(maximum),
                                isCharging: charging,
                                isPluggedIn: plugged,
                                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil)
        }
        return nil
    }
}
