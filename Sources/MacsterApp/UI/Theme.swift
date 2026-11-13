import SwiftUI

enum Theme {
    /// The green from Macster's logo.
    static let accent = Color(red: 0xB3 / 255, green: 0xDF / 255, blue: 0x51 / 255)
    /// Text and symbols drawn on top of `accent`.
    static let onAccent = Color(red: 0.11, green: 0.13, blue: 0.08)
    static let cardRadius: CGFloat = 12
}
