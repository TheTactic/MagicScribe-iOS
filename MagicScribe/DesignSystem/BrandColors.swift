import SwiftUI

extension Color {
    static let magicNavy = Color(red: 26.0 / 255.0, green: 26.0 / 255.0, blue: 46.0 / 255.0)
    static let magicBlue = Color(red: 74.0 / 255.0, green: 144.0 / 255.0, blue: 226.0 / 255.0)
    static let magicGold = Color(red: 246.0 / 255.0, green: 199.0 / 255.0, blue: 82.0 / 255.0)

    /// Same hue/saturation as magicGold, darkened (WCAG contrast audit:
    /// magicGold is only 1.6:1 against white — far below the 4.5:1/3:1
    /// minimums). Use for gold text/icons on light backgrounds; magicGold
    /// itself stays reserved for use on dark backgrounds (e.g. navy), where
    /// it already passes.
    static let magicGoldOnLight = Color(red: 135.0 / 255.0, green: 109.0 / 255.0, blue: 45.0 / 255.0)

    /// Same hue/saturation as magicBlue, darkened (WCAG contrast audit:
    /// white text on magicBlue is only 3.3:1 — enough for icon-only
    /// contexts but below the 4.5:1 normal-text minimum). Use as the fill
    /// behind white button-label text; magicBlue itself stays fine for
    /// icon-only toggle states.
    static let magicBlueButton = Color(red: 56.0 / 255.0, green: 108.0 / 255.0, blue: 170.0 / 255.0)
}
