import IOKit

/// Reads power-management state straight from the kernel's `IOPMrootDomain`, without launching any process.
///
/// `SleepDisabled` here is what actually keeps the Mac awake: `pmset disablesleep` sets it, and while it is true the
/// Mac doesn't sleep for any reason — idle, closing the lid, or the Sleep menu item.
final class RootDomain {
    private let service: io_service_t

    init() {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    }

    deinit {
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
        }
    }

    var isSleepDisabled: Bool {
        bool(for: "SleepDisabled") ?? false
    }

    /// Whether the lid is closed, or nil on Macs without one.
    var isLidClosed: Bool? {
        bool(for: "AppleClamshellState")
    }

    private func bool(for key: String) -> Bool? {
        guard service != IO_OBJECT_NULL,
              let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        else { return nil }
        return value as? Bool
    }
}
