import Foundation
import IOKit.ps
import MacsterCore

/// Reads the internal battery and reports power source changes while started.
final class PowerSourceMonitor {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (() -> Void)?

    /// The internal battery, or nil on Macs without one.
    static func currentReading() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maximum > 0 ? Int((Double(current) * 100 / Double(maximum)).rounded()) : current
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return BatteryReading(percent: percent, isOnBatteryPower: onBattery, temperatureCelsius: batteryTemperature())
        }
        return nil
    }

    /// The battery's own temperature sensor, from its driver. IOPowerSources doesn't report temperature.
    private static func batteryTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
        else { return nil }
        return Safety.celsius(fromBatteryTemperature: raw)
    }

    /// Calls `onChange` whenever the charge or the power source changes, until `stop()`.
    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(powerSourcesChanged, context)?.takeRetainedValue() else {
            return
        }
        // Common modes, so changes still arrive while a menu in the panel is open.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        onChange = nil
    }

    fileprivate func handleChange() {
        onChange?()
    }
}

/// IOKit calls this on the main run loop, where the source was added.
private nonisolated func powerSourcesChanged(_ context: UnsafeMutableRawPointer?) {
    // Pass the address as an integer: raw pointers can't cross into the main actor's closure.
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let context = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().handleChange()
    }
}
