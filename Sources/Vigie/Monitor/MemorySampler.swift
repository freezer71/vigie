import Darwin
import Foundation

struct MemoryStats: Sendable, Equatable {
    enum Pressure: Sendable { case normal, warning, critical }

    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: Pressure = .normal

    /// Même définition que « Mémoire utilisée » dans le Moniteur d'activité.
    var used: UInt64 { app + wired + compressed }
    var usage: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

final class MemorySampler {
    private let host = mach_host_self()
    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    func sample() -> MemoryStats {
        var stats = MemoryStats()
        stats.total = ProcessInfo.processInfo.physicalMemory

        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let internalPages = UInt64(vm.internal_page_count)
            let purgeable = UInt64(vm.purgeable_count)
            stats.app = (internalPages - min(purgeable, internalPages)) * pageSize
            stats.wired = UInt64(vm.wire_count) * pageSize
            stats.compressed = UInt64(vm.compressor_page_count) * pageSize
            stats.cached = (UInt64(vm.external_page_count) + purgeable) * pageSize
            let taken = stats.used + stats.cached
            stats.free = stats.total > taken ? stats.total - taken : 0
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            stats.swapUsed = swap.xsu_used
            stats.swapTotal = swap.xsu_total
        }

        var level: Int32 = 1
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            stats.pressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }
        return stats
    }
}
