import AppKit
import MacsterCore
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: StatusItemController?
    private let log = Logger(subsystem: "io.github.macster", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        let statusItem = StatusItemController(model: model)
        self.statusItem = statusItem

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPanelRequested),
            name: MacsterMain.showPanelNotification,
            object: nil
        )

        Task {
            await model.start()
            if model.shouldShowPanelAtLaunch {
                statusItem.showPanel()
            }
        }
    }

    /// `macster://` URLs from Shortcuts, other apps, and the `macster` command. Commands that arrive while Macster is
    /// still starting wait for it.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = MacsterCommand(url: url) else {
                log.error("Ignored a URL Macster doesn't understand: \(url.absoluteString, privacy: .public)")
                continue
            }
            model.perform(command)
        }
    }

    /// Opening Macster again from Finder or Spotlight while it's running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPanel()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.needsCleanupBeforeQuit else { return .terminateNow }
        Task {
            await model.prepareToQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func showPanelRequested() {
        statusItem?.showPanel()
    }

    /// Menu bar apps have no visible main menu, but its key equivalents (⌘Q) still work while the panel is open.
    private static func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Macster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        return mainMenu
    }
}
