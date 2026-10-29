import SwiftUI
import UIKit

/// Design tokens. White + light-blue brand, with a deep-navy dark mode.
/// Text-on-fill pairs were chosen for >= 4.5:1 contrast (primary/onPrimary in both modes).
enum Theme {
    enum Colors {
        /// Buttons, links, selected states. Darker blue in light mode for text contrast on white.
        static let primary = Color(light: 0x1670BE, dark: 0x5BB8FF)
        static let onPrimary = Color(light: 0xFFFFFF, dark: 0x06223A)
        /// The "light blue" brand colour used for decoration (gradients, rings, glows).
        static let lightBlue = Color(light: 0x4DB3FF, dark: 0x4DB3FF)
        static let backgroundTop = Color(light: 0xDDF0FF, dark: 0x0E2236)
        static let background = Color(light: 0xFFFFFF, dark: 0x08131F)
        static let surface = Color(light: 0xFFFFFF, dark: 0x13283B)
        static let surfaceTint = Color(light: 0xEAF6FF, dark: 0x1A3550)
        static let textPrimary = Color(light: 0x0F2A40, dark: 0xF2F8FD)
        static let textSecondary = Color(light: 0x56718A, dark: 0xA3B8CC)
        static let border = Color(light: 0xCFE3F3, dark: 0x27425C)
        static let success = Color(light: 0x1E8E5A, dark: 0x4CD08B)
        static let danger = Color(light: 0xC0392B, dark: 0xFF7A6B)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 24
    }

    enum Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold, design: .rounded)
        static let title = Font.system(size: 24, weight: .bold, design: .rounded)
        static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .rounded)
        static let cardQuestion = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded, weight: .medium)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
