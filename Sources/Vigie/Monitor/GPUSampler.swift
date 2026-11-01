import Foundation
import IOKit

struct GPUStats: Sendable, Equatable {
    /// Valeurs de 0 à 1.
    var utilization: Double = 0
    var renderer: Double = 0
    var tiler: Double = 0
    var memoryUsed: UInt64 = 0
}

/// Lit `PerformanceStatistics` sur les services `IOAccelerator` (fonctionne sans droits admin).
final class GPUSampler {
    func sample() -> GPUStats {
        var stats = GPUStats()
        forEachAccelerator { entry in
            guard let perf = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { return }
            func number(_ key: String) -> Double { (perf[key] as? NSNumber)?.doubleValue ?? 0 }
            stats.utilization = max(stats.utilization, number("Device Utilization %") / 100)
            stats.renderer = max(stats.renderer, number("Renderer Utilization %") / 100)
            stats.tiler = max(stats.tiler, number("Tiler Utilization %") / 100)
            stats.memoryUsed += UInt64(number("In use system memory"))
        }
        return stats
    }

    /// Nom du GPU et nombre de cœurs, lus une seule fois au démarrage.
    static func staticInfo() -> (model: String, cores: Int) {
        var model = "", cores = 0
        GPUSampler().forEachAccelerator { entry in
            if let value = IORegistryEntryCreateCFProperty(entry, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                if let s = value as? String { model = s }
                else if let d = value as? Data { model = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
            }
            if let n = IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                cores = n.intValue
            }
        }
        return (model, cores)
    }

    private func forEachAccelerator(_ body: (io_registry_entry_t) -> Void) {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            body(entry)
            IOObjectRelease(entry)
        }
    }
}
