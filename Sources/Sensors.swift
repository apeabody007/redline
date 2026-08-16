import Foundation

/// Reads on-die temperature sensors through IOHIDEventSystem.
///
/// There is no public API for this on Apple Silicon (`powermetrics` needs
/// root), so we resolve the symbols at runtime. Nothing here is hardcoded to
/// a chip generation: we enumerate whatever temperature sensors the machine
/// advertises and take the hottest one that is not a peripheral. On a Mac
/// where the lookup fails, every call returns nil and the HUD drops the
/// reading instead of showing a wrong number.
final class TemperatureSensors {

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject?, CFDictionary?) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject?) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject?, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject?, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValueFn = @convention(c) (AnyObject?, Int32) -> Double

    private var copyProperty: CopyPropertyFn?
    private var copyEvent: CopyEventFn?
    private var floatValue: FloatValueFn?

    /// The service handles below are only valid while their parent client is
    /// alive, so this reference has to be held for the life of the object.
    private var client: AnyObject?

    private struct Sensor {
        let service: AnyObject
        let name: String
    }

    /// Names are resolved once at startup rather than on every tick. They never
    /// change, and copying 39 strings a second across the HID boundary cost
    /// more than reading the temperatures did.
    private var sensors: [Sensor] = []

    /// Pre-filtered so the once-a-second path touches only the sensors that can
    /// actually win `max`, instead of walking the peripherals every time.
    private var dieSensors: [Sensor] = []

    /// kIOHIDEventTypeTemperature. The value field is that type shifted into
    /// the high half of the field identifier.
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    /// Sensors that report a real temperature, just not the one we want.
    /// `tcal` is the PMU's calibration reference: it sits ~12°C above the die
    /// and barely moves under load, so it would peg the readout high forever.
    private static let ignored = ["battery", "gas gauge", "charger", "ambient", "nand", "tcal"]

    var isAvailable: Bool { client != nil && !sensors.isEmpty }

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let matchSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let servicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let propertySym = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let eventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let floatSym = dlsym(handle, "IOHIDEventGetFloatValue")
        else { return }

        copyProperty = unsafeBitCast(propertySym, to: CopyPropertyFn.self)
        copyEvent = unsafeBitCast(eventSym, to: CopyEventFn.self)
        floatValue = unsafeBitCast(floatSym, to: FloatValueFn.self)

        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let setMatching = unsafeBitCast(matchSym, to: SetMatchingFn.self)
        let copyServices = unsafeBitCast(servicesSym, to: CopyServicesFn.self)

        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        self.client = client

        // PrimaryUsagePage 0xff00 / PrimaryUsage 5 is the temperature sensor page.
        setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []

        sensors = services.map { service in
            let name = (copyProperty?(service, "Product" as CFString)?
                .takeRetainedValue() as? String) ?? "(unnamed)"
            return Sensor(service: service, name: name)
        }
        dieSensors = sensors.filter { sensor in
            let name = sensor.name.lowercased()
            return !Self.ignored.contains(where: name.contains)
        }
    }

    /// Hottest die sensor in degrees Celsius, or nil if this Mac will not say.
    /// This runs once a second, so it does nothing but read the pre-filtered
    /// set: no matching, no string copies, no allocation per sensor.
    func peakDieTemperature() -> Double? {
        var peak: Double?
        for sensor in dieSensors {
            guard let celsius = read(sensor) else { continue }
            peak = max(peak ?? celsius, celsius)
        }
        return peak
    }

    /// Every readable sensor, for the `--sensors` diagnostic dump. Run it on a
    /// new machine to confirm the readings survived the move.
    func allReadings() -> [(name: String, celsius: Double)] {
        sensors.compactMap { sensor in
            read(sensor).map { (name: sensor.name, celsius: $0) }
        }
        .sorted { $0.celsius > $1.celsius }
    }

    private func read(_ sensor: Sensor) -> Double? {
        guard let copyEvent, let floatValue,
              let event = copyEvent(sensor.service, Self.temperatureEventType, 0, 0)?
                .takeRetainedValue() else { return nil }
        let celsius = floatValue(event, Self.temperatureField)
        // Unused sensors read at or below zero, disconnected ones read wild.
        return (celsius > 1 && celsius < 130) ? celsius : nil
    }
}
