import AppKit
import MacsterCore

/// Entry point for the `Macster` executable: the menu bar app, or the `macster` command when given one.
public enum MacsterMain {
    static let showPanelNotification = Notification.Name("io.github.macster.show-panel")

    public static func run() -> Never {
        do {
            if let request = try CommandLineRequest.parse(Array(CommandLine.arguments.dropFirst())) {
                CommandLineTool.run(request)
            }
        } catch {
            FileHandle.standardError.write(Data("macster: \(error)\n".utf8))
            exit(64)
        }

        // `macster` on its own, through a symlink to the app: that's the command-line tool, not a second copy of the
        // menu bar app (which, outside its bundle, couldn't tell that the real one is already running).
        if !AppInfo.isRunningFromAppBundle, AppInfo.belongsToAppBundle {
            CommandLineTool.run(.help)
        }

        // A write to a watchdog that already exited must fail with EPIPE, not kill Macster.
        signal(SIGPIPE, SIG_IGN)

        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0 != .current }) {
            // Another copy is already in the menu bar: ask it to show its panel instead.
            DistributedNotificationCenter.default().postNotificationName(
                showPanelNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
        exit(0)
    }
}
