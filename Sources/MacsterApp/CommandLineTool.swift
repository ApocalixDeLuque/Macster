import Foundation
import MacsterCore

/// `macster <command>` in Terminal. Talks to the menu bar app through its `macster://` URLs, which launches it if it
/// isn't running, and reads the result straight from the kernel. Never starts the app's UI in this process.
enum CommandLineTool {
    static func run(_ request: CommandLineRequest) -> Never {
        switch request {
        case .help:
            print(CommandLineRequest.usage)
            exit(0)
        case .version:
            print("Macster \(AppInfo.version)")
            exit(0)
        case .status:
            print(statusLine(sleepDisabled: RootDomain().isSleepDisabled))
            exit(0)
        case .diagnose:
            Task {
                print(await Diagnostics.report())
                exit(0)
            }
            dispatchMain()
        case .send(let command):
            exit(send(command))
        case .run(let command):
            runKeepingAwake(command)
        }
    }

    private static func statusLine(sleepDisabled: Bool) -> String {
        sleepDisabled ? "on: your Mac won’t sleep, even with the lid closed" : "off: your Mac sleeps normally"
    }

    /// Hands `command` to Macster and waits until the kernel shows the result.
    private static func send(_ command: MacsterCommand) -> Int32 {
        let rootDomain = RootDomain()
        let before = rootDomain.isSleepDisabled
        let turnsOn = switch command {
        case .on: true
        case .toggle: !before
        case .off, .open: false
        }
        if turnsOn, !before {
            // Macster would refuse; say why now instead of waiting to see nothing happen.
            guard FileManager.default.fileExists(atPath: SudoRule.path) else {
                printError("Macster isn’t set up yet. Opening it so you can set it up.")
                _ = open(.open)
                return 1
            }
            if let reason = safetyStopReason() {
                printError(reason.refusal.replacingOccurrences(of: " below.", with: " in Macster’s panel."))
                return 1
            }
        }
        guard open(command) else { return 1 }

        let expected: Bool
        switch command {
        case .open: return 0
        case .on: expected = true
        case .off: expected = false
        case .toggle: expected = !before
        }
        if wait(until: expected, rootDomain) {
            print(statusLine(sleepDisabled: expected))
            return 0
        }
        printError("Macster didn’t turn \(expected ? "on" : "off"). Open its panel to see why: macster open")
        return 1
    }

    /// Turns Macster on for this process, then becomes `command`: `exec` keeps the process ID, so Macster stays on
    /// until the command exits.
    private static func runKeepingAwake(_ command: [String]) -> Never {
        // Fail like a shell would, before keeping the Mac awake for a program that can't start.
        guard let program = executablePath(for: command[0]) else {
            printError("\(command[0]): command not found")
            exit(127)
        }
        if !FileManager.default.fileExists(atPath: SudoRule.path) {
            printError("Macster isn’t set up yet, so your Mac may still sleep. Open Macster once to set it up.")
        }
        let rootDomain = RootDomain()
        if !rootDomain.isSleepDisabled, let reason = safetyStopReason() {
            let why = reason.refusal.replacingOccurrences(of: " below.", with: " in Macster’s panel.")
            printError("Macster won’t keep your Mac awake: \(why) Running the command anyway.")
        } else if open(.on(minutes: nil, pid: getpid())), !wait(until: true, rootDomain) {
            printError("Macster didn’t turn on, so your Mac may still sleep. Running the command anyway.")
        }

        signal(SIGPIPE, SIG_DFL)
        let arguments = command.map { strdup($0) } + [nil]
        execv(program, arguments)
        let reason = String(cString: strerror(errno))
        printError("\(command[0]): \(reason)")
        exit(errno == ENOENT ? 127 : 126)
    }

    /// `name` itself if it contains a slash, otherwise the first executable match on `PATH`, the way shells look it up.
    private static func executablePath(for name: String) -> String? {
        let files = FileManager.default
        if name.contains("/") {
            return files.isExecutableFile(atPath: name) ? name : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":", omittingEmptySubsequences: false) {
            let candidate = (directory.isEmpty ? "." : String(directory)) + "/" + name
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue,
               files.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// What the app's safeties would say right now, from the settings it saved. Same rules, same defaults.
    private static func safetyStopReason() -> TurnOffReason? {
        let domain = "io.github.macster.Macster" as CFString
        func saved<Value>(_ key: String, as type: Value.Type) -> Value? {
            CFPreferencesCopyAppValue(key as CFString, domain) as? Value
        }
        return Safety.stopReason(
            battery: PowerSourceMonitor.currentReading(),
            cutoff: saved(AppModel.Keys.lowBatteryPercent, as: Int.self).map(BatteryCutoff.init(percent:)) ?? .standard,
            heatGuard: saved(AppModel.Keys.heatGuard, as: Bool.self) ?? true,
            isOverheating: ProcessInfo.processInfo.thermalState == .critical
        )
    }

    /// `open -g` hands the URL to Macster through Launch Services without bringing anything to the front.
    private static func open(_ command: MacsterCommand) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", command.url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            printError("Couldn’t run /usr/bin/open: \(error.localizedDescription)")
            return false
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            printError("Couldn’t reach Macster. Put Macster.app in Applications and open it once.")
            return false
        }
        return true
    }

    /// Long enough for macOS to launch Macster and for Macster to check its permission.
    private static func wait(until sleepDisabled: Bool, _ rootDomain: RootDomain, timeout: Duration = .seconds(10)) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while rootDomain.isSleepDisabled != sleepDisabled {
            guard clock.now < deadline else { return false }
            usleep(50_000)
        }
        return true
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("macster: \(message)\n".utf8))
    }
}
