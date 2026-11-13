import AppKit
import MacsterCore
import Observation
import SwiftUI

/// The menu bar icon and the panel it opens. Left click opens the panel; right click shows a short menu.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var lastClosed = Date.distantPast
    private var shortcutRecorder: Any?

    init(model: AppModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        model.showPanel = { [weak self] in self?.showPanel() }
        updateIcon()
    }

    func showPanel() {
        guard let button = statusItem.button, !popover.isShown else { return }
        model.panelWillAppear()
        if popover.contentViewController == nil {
            // Built on demand and released on close: the SwiftUI view graph costs memory only while you look at it.
            let host = NSHostingController(rootView: LivePanel(model: model, actions: makeActions()))
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosed = .now
        stopListeningForShortcut()
        statusItem.button?.highlight(false)
        model.panelDidDisappear()
        popover.contentViewController = nil
    }

    /// Redraws the icon now and again whenever the state it reads changes.
    private func updateIcon() {
        withObservationTracking {
            let keepsAwake = model.phase == .on || model.phase == .turningOff
            let deadline = model.autoOffDeadline
            guard let button = statusItem.button else { return }
            button.image = keepsAwake ? MenuBarIcon.on : MenuBarIcon.off
            button.toolTip = switch (keepsAwake, deadline) {
            case (true, let deadline?): "Macster: on until \(deadline.formatted(date: .omitted, time: .shortened))"
            case (true, nil): "Macster: your Mac won’t sleep, even with the lid closed"
            case (false, _): "Macster: your Mac sleeps normally"
            }
            button.setAccessibilityLabel(keepsAwake ? "Macster, on" : "Macster, off")
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if Date.now.timeIntervalSince(lastClosed) > 0.3 {
            // A click on the icon while the panel is open closes it on mouse-down, before this runs on mouse-up.
            showPanel()
        }
    }

    // MARK: - Quick menu

    private func showQuickMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if model.access == .ready {
            let isChanging = model.phase.isChanging
            let toggle = NSMenuItem(title: "Stay Awake with Lid Closed", action: #selector(quickToggle), keyEquivalent: "")
            toggle.target = self
            toggle.state = model.phase == .on || model.phase == .turningOn ? .on : .off
            toggle.isEnabled = !isChanging
            if let equivalent = model.toggleShortcut?.menuKeyEquivalent {
                // Shown as a reminder; the shortcut itself works from any app.
                toggle.keyEquivalent = equivalent.key
                toggle.keyEquivalentModifierMask = equivalent.modifiers
            }
            menu.addItem(toggle)

            let durations = NSMenu()
            for minutes in [30, 60, 120, 240, 480, 0] {
                if minutes == 0 { durations.addItem(.separator()) }
                let title = minutes == 0 ? "Until Turned Off" : AutoOff(minutes: minutes).title.capitalized
                let item = NSMenuItem(title: title, action: #selector(stayAwakeFor), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                durations.addItem(item)
            }
            let stayAwakeFor = NSMenuItem(title: model.phase == .on ? "Keep Awake For" : "Stay Awake For", action: nil, keyEquivalent: "")
            stayAwakeFor.submenu = durations
            stayAwakeFor.isEnabled = !isChanging
            menu.addItem(stayAwakeFor)

            if model.phase == .on, let deadline = model.autoOffDeadline {
                let until = NSMenuItem(title: "On until \(deadline.formatted(date: .omitted, time: .shortened))", action: nil, keyEquivalent: "")
                until.isEnabled = false
                menu.addItem(until)
            }
        } else {
            let setUp = NSMenuItem(title: "Set Up Macster…", action: #selector(openPanel), keyEquivalent: "")
            setUp.target = self
            menu.addItem(setUp)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Macster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Pop the menu up directly. Attaching it to the status item and calling performClick replays a click, which
        // can land on the first item and toggle sleep from a plain right click.
        guard let button = statusItem.button else { return }
        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        button.highlight(popover.isShown)
    }

    @objc private func quickToggle() {
        model.setOn(model.phase == .off)
    }

    @objc private func stayAwakeFor(_ sender: NSMenuItem) {
        model.perform(.on(minutes: sender.tag, pid: nil))
    }

    @objc private func openPanel() {
        showPanel()
    }

    // MARK: - Recording the keyboard shortcut

    private func toggleShortcutRecording() {
        if model.isRecordingShortcut {
            stopListeningForShortcut()
            model.cancelRecordingShortcut()
            return
        }
        model.beginRecordingShortcut()
        // The panel is the key window, so its key presses come through here first, before any menu sees them.
        shortcutRecorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, model.isRecordingShortcut else { return event }
            handleRecordedKey(event)
            return nil
        }
    }

    private func handleRecordedKey(_ event: NSEvent) {
        let shortcut = KeyboardShortcut(event: event)
        if shortcut.modifiers.isEmpty, shortcut.keyCode == KeyboardShortcut.escapeKeyCode {
            stopListeningForShortcut()
            model.cancelRecordingShortcut()
        } else if shortcut.modifiers.isEmpty, KeyboardShortcut.deleteKeyCodes.contains(shortcut.keyCode) {
            stopListeningForShortcut()
            model.clearShortcut()
        } else if model.recordShortcut(shortcut) {
            stopListeningForShortcut()
        }
    }

    private func stopListeningForShortcut() {
        if let shortcutRecorder {
            NSEvent.removeMonitor(shortcutRecorder)
        }
        shortcutRecorder = nil
    }

    // MARK: - Panel actions

    private func makeActions() -> PanelActions {
        PanelActions(
            setOn: { [model] in model.setOn($0) },
            setUp: { [model] in model.setUp() },
            setAutoOff: { [model] in model.chooseAutoOff($0) },
            setBatteryCutoff: { [model] in model.batteryCutoff = $0 },
            setHeatGuard: { [model] in model.heatGuard = $0 },
            setScreenOffWhenClosed: { [model] in model.screenOffWhenClosed = $0 },
            setLaunchAtLogin: { [model] in model.setLaunchAtLogin($0) },
            openLoginItemSettings: { LoginItem.openSystemSettings() },
            recordShortcut: { [weak self] in self?.toggleShortcutRecording() },
            clearShortcut: { [model] in model.clearShortcut() },
            showAbout: { [weak self] in self?.showAbout() },
            removeAccess: { [model] in model.removeAccess() },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func showAbout() {
        popover.performClose(nil)
        NSApp.activate()
        let credits = NSAttributedString(
            string: "Keeps your Mac awake with the lid closed, only while you want it to.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
