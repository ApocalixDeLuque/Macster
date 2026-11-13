// Renders the panel in each state (light and dark) and the menu bar icons to PNG files.
//
//     swift run MacsterSnapshots <output-folder> [assets/macster.png]
//
// Development only; not part of the app bundle.

import AppKit
import MacsterCore
import SwiftUI
@testable import MacsterApp

let arguments = CommandLine.arguments
let outputFolder = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "snapshots", isDirectory: true)
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

/// Key windows draw controls in their active colors, the way the real panel looks.
final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.activate()
if arguments.count > 2, let logo = NSImage(contentsOfFile: arguments[2]) {
    app.applicationIconImage = logo
}

let ready = PanelState(
    power: .off,
    setup: .ready,
    notice: nil,
    autoOff: .never,
    batteryCutoff: .standard,
    heatGuard: true,
    showsBatteryCutoff: true,
    screenOffWhenClosed: true,
    showsLidOptions: true,
    launchAtLogin: false,
    loginItemNeedsApproval: false,
    shortcut: nil,
    isRecordingShortcut: false,
    version: "0.2.0"
)

func variant(_ change: (inout PanelState) -> Void) -> PanelState {
    var state = ready
    change(&state)
    return state
}

let twoHoursFromNow = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: .now) ?? .now

let states: [(String, PanelState)] = [
    ("off", ready),
    ("on", variant { $0.power = .on(until: nil) }),
    ("on-timer", variant {
        $0.power = .on(until: twoHoursFromNow)
        $0.autoOff = AutoOff(minutes: 120)
        $0.launchAtLogin = true
        $0.shortcut = "⌃⌥⌘L"
    }),
    ("turning-on", variant { $0.power = .turningOn }),
    ("recording-shortcut", variant {
        $0.isRecordingShortcut = true
        $0.notice = .error("Use two or more modifier keys, including ⌘ or ⌃, like ⌃⌥⌘L.")
    }),
    ("hot", variant {
        $0.notice = .info("Turned off because the battery reached 46 °C. Let your Mac cool down.")
        $0.batteryCutoff = BatteryCutoff(percent: 20)
    }),
    ("auto-off-notice", variant {
        $0.notice = .info("Turned off at 10% battery so your Mac can sleep instead of running out.")
    }),
    ("error", variant {
        $0.notice = .error("macOS didn’t apply the change. Try again.")
    }),
    ("setup-update", variant {
        $0.setup = .needed(updatingOldVersion: true)
        $0.power = .on(until: nil)
    }),
    ("setup-fresh", variant { $0.setup = .needed(updatingOldVersion: false) }),
    ("setup-waiting", variant { $0.setup = .inProgress(updatingOldVersion: true) }),
    ("desktop-login-approval", variant {
        $0.showsBatteryCutoff = false
        $0.showsLidOptions = false
        $0.launchAtLogin = true
        $0.loginItemNeedsApproval = true
    }),
]

for (name, state) in states {
    for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let appearance = NSAppearance(named: appearanceName)!
        let host = NSHostingView(
            rootView: PanelView(state: state, actions: PanelActions())
                .background(Color(nsColor: .windowBackgroundColor))
        )
        host.appearance = appearance
        let size = host.fittingSize

        // Off screen, but ordered in, so AppKit controls inside the SwiftUI view draw.
        let window = SnapshotWindow(
            contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let file = outputFolder.appendingPathComponent("panel-\(name)-\(suffix).png")
        try rep.representation(using: .png, properties: [:])!.write(to: file)
        window.orderOut(nil)
        print(file.path)
    }
}

// Menu bar icons next to a few system icons, on light and dark menu bars, at 2x.

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func png(size: NSSize, scale: CGFloat = 2, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let systemIcons = ["wifi", "battery.75percent", "magnifyingglass"].compactMap { name in
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
}
let barSize = NSSize(width: 170, height: 24)

for (suffix, background, foreground) in [
    ("light", NSColor(white: 0.92, alpha: 1), NSColor.black),
    ("dark", NSColor(white: 0.17, alpha: 1), NSColor.white),
] {
    let data = png(size: barSize) {
        background.setFill()
        NSRect(origin: .zero, size: barSize).fill()
        var x: CGFloat = 10
        for icon in [MenuBarIcon.off, MenuBarIcon.on] + systemIcons {
            let iconSize = icon.size
            let rect = NSRect(x: x, y: (barSize.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
            tinted(icon, foreground).draw(in: rect)
            x += iconSize.width + 16
        }
    }
    let file = outputFolder.appendingPathComponent("menubar-\(suffix).png")
    try data.write(to: file)
    print(file.path)
}
