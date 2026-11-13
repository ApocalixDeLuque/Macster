import IOKit
import MacsterCore

/// Reports when the lid opens or closes, from IOPMrootDomain's clamshell messages. The kernel pushes them over a Mach
/// port, so watching costs nothing between changes.
///
/// Lives as long as the app: the IOKit callback keeps an unretained pointer to it.
final class LidMonitor {
    private var port: IONotificationPortRef?
    private var notification: io_object_t = IO_OBJECT_NULL
    private var onChange: ((_ isClosed: Bool) -> Void)?
    private var lastIsClosed: Bool?

    /// Calls `onChange` each time the lid opens or closes, until `stop()`. False if this Mac has no lid to watch.
    @discardableResult
    func start(isClosed: Bool, onChange: @escaping (_ isClosed: Bool) -> Void) -> Bool {
        self.onChange = onChange
        lastIsClosed = isClosed
        guard port == nil else { return true }

        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, rootDomainMessage, context, &notification)
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return false
        }
        // Common modes, so lid changes still arrive while a menu is open.
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        self.port = port
        return true
    }

    func stop() {
        if notification != IO_OBJECT_NULL {
            IOObjectRelease(notification)
            notification = IO_OBJECT_NULL
        }
        if let port {
            IONotificationPortDestroy(port) // Also removes its run loop source.
        }
        port = nil
        onChange = nil
        lastIsClosed = nil
    }

    fileprivate func received(_ messageType: UInt32, argument: UInt) {
        guard messageType == Clamshell.stateChangeMessage else { return }
        let isClosed = Clamshell.isClosed(messageArgument: argument)
        // The same message also reports changes to whether closing causes sleep; only the lid itself matters here.
        guard isClosed != lastIsClosed else { return }
        lastIsClosed = isClosed
        onChange?(isClosed)
    }
}

/// IOKit calls this on the main run loop, where the notification port's source was added.
private nonisolated func rootDomainMessage(
    _ context: UnsafeMutableRawPointer?,
    _ service: io_service_t,
    _ messageType: UInt32,
    _ argument: UnsafeMutableRawPointer?
) {
    let address = UInt(bitPattern: context)
    let bits = UInt(bitPattern: argument)
    MainActor.assumeIsolated {
        guard let context = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue().received(messageType, argument: bits)
    }
}
