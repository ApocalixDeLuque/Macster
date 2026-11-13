import AppKit

/// The menu bar icon: a laptop whose screen is outlined while the Mac sleeps normally and lit (filled) while
/// Macster keeps it awake. Template images, so macOS tints them for light and dark menu bars.
enum MenuBarIcon {
    static let off = make(isOn: false)
    static let on = make(isOn: true)

    private static func make(isOn: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()

            let screen = NSRect(x: 2.5, y: 3.5, width: 13, height: 9)
            if isOn {
                NSBezierPath(roundedRect: screen, xRadius: 2, yRadius: 2).fill()
            } else {
                let outline = NSBezierPath(roundedRect: screen.insetBy(dx: 0.75, dy: 0.75), xRadius: 1.25, yRadius: 1.25)
                outline.lineWidth = 1.5
                outline.stroke()
            }

            let base = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 13.5, width: 17, height: 2), xRadius: 1, yRadius: 1)
            base.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = isOn ? "Macster, keeping your Mac awake" : "Macster, off"
        return image
    }
}
