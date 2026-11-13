import CoreGraphics
import IOKit.pwr_mgt
import MacsterCore

/// Turns the screens off and on. Neither needs privileges.
enum Screens {
    /// Puts every display to sleep, like `pmset displaysleepnow`. Apple silicon Macs have no IODisplayWrangler to ask
    /// directly, so this goes through pmset, which works for any user. If the Mac requires a password once the screen
    /// turns off, it locks too, as it would when sleeping.
    static func turnOff() async throws {
        let output = try await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: .seconds(5))
        guard output.succeeded else {
            throw SleepControlError.commandFailed(output.stderr.isEmpty ? "pmset exited with status \(output.status)." : output.stderr)
        }
    }

    /// Wakes the displays the way a key press would. macOS also does this when the lid opens; this makes sure.
    static func turnOn() {
        var assertion: IOPMAssertionID = 0
        if IOPMAssertionDeclareUserActivity("Macster: lid opened" as CFString, kIOPMUserActiveLocal, &assertion) == kIOReturnSuccess {
            IOPMAssertionRelease(assertion)
        }
    }

    /// Whether any active display isn't the built-in one: a monitor, AirPlay, Sidecar, or a virtual display.
    static var hasOtherDisplay: Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
