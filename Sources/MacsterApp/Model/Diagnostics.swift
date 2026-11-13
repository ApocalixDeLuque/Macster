import Foundation
import MacsterCore

/// `Macster --diagnose`: prints what Macster sees and what setup would do, without changing anything.
enum Diagnostics {
    static func report() async -> String {
        let rootDomain = RootDomain()
        let legacy = await LegacyScanner.scan()
        let current = await LegacyScanner.currentSettings()
        let hasAccess = await SleepControl.hasPasswordlessAccess(probe: nil)

        func describe(_ profile: PowerProfile?) -> String {
            profile.map { $0.pmsetArguments.joined(separator: " ") } ?? "none"
        }
        func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
        func describe(_ battery: BatteryReading?) -> String {
            guard let battery else { return "none" }
            let source = battery.isOnBatteryPower ? "on battery" : "on power adapter"
            let temperature = battery.temperatureCelsius.map { String(format: ", %.1f °C", $0) } ?? ""
            return "\(battery.percent)%, \(source)\(temperature)"
        }

        var lines = [
            "Macster \(AppInfo.version)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "",
            "Sleep disabled (kernel): \(yesNo(rootDomain.isSleepDisabled))",
            "Lid closed: \(rootDomain.isLidClosed.map(yesNo) ?? "no lid")",
            "Other displays: \(yesNo(Screens.hasOtherDisplay))",
            "Battery: \(describe(PowerSourceMonitor.currentReading()))",
            "Thermal state: \(ProcessInfo.processInfo.thermalState.name)",
            "Passwordless permission: \(yesNo(hasAccess))",
            "",
            "Current settings, battery: \(describe(current.battery))",
            "Current settings, power adapter: \(describe(current.powerAdapter))",
            "",
            "Macster 0.1 helper: \(yesNo(legacy.helperInstalled))",
            "Macster 0.1 caffeinate job: \(yesNo(legacy.keepAwakeJobLoaded))",
            "Macster 0.1 backup, battery: \(describe(legacy.backup?.battery))",
            "Macster 0.1 backup, power adapter: \(describe(legacy.backup?.powerAdapter))",
        ]

        if let rule = try? SudoRule(userName: NSUserName()) {
            let plan = SetupPlan(rule: rule, userID: getuid(), legacy: legacy, currentSettings: current)
            lines += ["", hasAccess && !legacy.isPresent ? "Setup is done. Running it again would:" : "Setup would:"]
            lines += plan.steps.map { "  - \($0)" }
            lines += ["", "Setup script (runs as root after the password prompt):", plan.script]
        }
        return lines.joined(separator: "\n")
    }
}

enum AppInfo {
    static var version: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    /// The app bundle this executable lives in. Started through a symlink such as `/usr/local/bin/macster`,
    /// `Bundle.main` describes the symlink's folder instead, so this follows the link back to `Macster.app`.
    static let bundle: Bundle = {
        if isAppBundle(Bundle.main) { return Bundle.main }
        guard let executable = realExecutableURL else { return Bundle.main }
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if app.pathExtension == "app", let bundle = Bundle(url: app) { return bundle }
        return Bundle.main
    }()

    /// Whether this process was started from inside an app bundle, rather than through a symlink to it.
    static var isRunningFromAppBundle: Bool { isAppBundle(Bundle.main) }

    /// Whether the executable belongs to an app bundle at all. False for `swift run` development builds.
    static var belongsToAppBundle: Bool { isAppBundle(bundle) }

    private static func isAppBundle(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app"
    }

    private static var realExecutableURL: URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var path = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&path, &size) == 0, let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
}

private extension ProcessInfo.ThermalState {
    var name: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
