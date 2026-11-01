import Foundation

struct TemperatureStats: Sendable, Equatable {
    /// Moyenne des capteurs de la puce (°C).
    var soc: Double?
    /// Point le plus chaud de la puce (°C).
    var socMax: Double?
    var ssd: Double?
    var battery: Double?
}

/// Capteurs de température via IOHIDEventSystemClient (API privée d'IOKit, lisible sans droits admin).
/// Chargée dynamiquement : si elle disparaît dans une future version de macOS, les valeurs restent vides.
final class TemperatureSampler {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias SetMatchingFn = @convention(c) (OpaquePointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (OpaquePointer) -> OpaquePointer?
    private typealias CopyPropertyFn = @convention(c) (OpaquePointer, CFString) -> OpaquePointer?
    private typealias CopyEventFn = @convention(c) (OpaquePointer, Int64, Int32, Int64) -> OpaquePointer?
    private typealias FloatValueFn = @convention(c) (OpaquePointer, Int32) -> Double

    private enum Kind { case soc, ssd, battery }
    private struct Sensor { let service: OpaquePointer; let kind: Kind }

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private var sensors: [Sensor] = []
    private var services: CFArray?          // garde les services en vie
    private var copyEvent: CopyEventFn?
    private var floatValue: FloatValueFn?

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = Self.symbol(handle, "IOHIDEventSystemClientCreate", as: CreateFn.self),
              let setMatching = Self.symbol(handle, "IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
              let copyServices = Self.symbol(handle, "IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self),
              let copyProperty = Self.symbol(handle, "IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self),
              let copyEvent = Self.symbol(handle, "IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
              let floatValue = Self.symbol(handle, "IOHIDEventGetFloatValue", as: FloatValueFn.self),
              let client = create(kCFAllocatorDefault) else { return }

        // Page « vendor » 0xff00, usage 5 = capteurs de température.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let raw = copyServices(client) else { return }
        let array = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(raw)).takeRetainedValue()
        services = array
        self.copyEvent = copyEvent
        self.floatValue = floatValue

        for index in 0..<CFArrayGetCount(array) {
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { continue }
            let service = OpaquePointer(pointer)
            guard let nameRef = copyProperty(service, "Product" as CFString),
                  let name = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(nameRef)).takeRetainedValue() as? String
            else { continue }
            if let kind = Self.kind(for: name) { sensors.append(Sensor(service: service, kind: kind)) }
        }
    }

    func sample() -> TemperatureStats {
        guard let copyEvent, let floatValue else { return TemperatureStats() }
        var soc: [Double] = [], ssd: [Double] = [], battery: [Double] = []
        for sensor in sensors {
            guard let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0) else { continue }
            let value = floatValue(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release()
            guard value > 1, value < 150 else { continue }   // certains capteurs renvoient des valeurs absurdes
            switch sensor.kind {
            case .soc: soc.append(value)
            case .ssd: ssd.append(value)
            case .battery: battery.append(value)
            }
        }
        return TemperatureStats(soc: soc.isEmpty ? nil : soc.reduce(0, +) / Double(soc.count),
                                socMax: soc.max(),
                                ssd: ssd.max(),
                                battery: battery.max())
    }

    private static func kind(for name: String) -> Kind? {
        // « PMU tdie* » : capteurs de la puce (M2 et suivantes) ; « MTR Temp » : noms des M1.
        if name.hasPrefix("PMU tdie") || name.contains("MTR Temp") { return .soc }
        if name.hasPrefix("NAND") { return .ssd }
        if name.hasPrefix("gas gauge") { return .battery }
        return nil
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
