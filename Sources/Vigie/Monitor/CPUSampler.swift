import Darwin

struct CPUStats: Sendable, Equatable {
    /// Valeurs de 0 à 1.
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    var cores: [Double] = []
    var loadAverage: [Double] = [0, 0, 0]
}

/// Lit les compteurs de ticks par cœur (`host_processor_info`) et calcule l'usage
/// entre deux échantillons.
final class CPUSampler {
    private let host = mach_host_self()
    private var previous: [[UInt32]] = []

    func sample() -> CPUStats {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUStats() }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            current.append((0..<states).map { UInt32(bitPattern: info[core * states + $0]) })
        }
        defer { previous = current }

        var stats = CPUStats()
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) == 3 { stats.loadAverage = load }

        guard previous.count == current.count else {
            stats.cores = Array(repeating: 0, count: current.count)
            return stats
        }

        var sumUser = 0.0, sumSystem = 0.0, sumTotal = 0.0
        for (now, before) in zip(current, previous) {
            func delta(_ state: Int32) -> Double { Double(now[Int(state)] &- before[Int(state)]) }
            let user = delta(CPU_STATE_USER) + delta(CPU_STATE_NICE)
            let system = delta(CPU_STATE_SYSTEM)
            let idle = delta(CPU_STATE_IDLE)
            let total = user + system + idle
            stats.cores.append(total > 0 ? (user + system) / total : 0)
            sumUser += user; sumSystem += system; sumTotal += total
        }
        if sumTotal > 0 {
            stats.user = sumUser / sumTotal
            stats.system = sumSystem / sumTotal
            stats.total = (sumUser + sumSystem) / sumTotal
        }
        return stats
    }
}
