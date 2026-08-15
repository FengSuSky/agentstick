import Foundation

public enum OverlayAppearance {
    case light
    case dark
}

public enum OverlayThemeName: String, CaseIterable {
    case white
    case pink
    case green
    case yellow
    case blue
    case purple
}

public struct OverlayColorComponents: Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public enum OverlayColorScheme {
    public static func backgroundComponents(
        for theme: OverlayThemeName,
        appearance: OverlayAppearance
    ) -> OverlayColorComponents {
        switch (theme, appearance) {
        case (.white, .light): return OverlayColorComponents(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.86)
        case (.white, .dark): return OverlayColorComponents(red: 0.16, green: 0.16, blue: 0.17, alpha: 0.88)
        case (.pink, .light): return OverlayColorComponents(red: 1.0, green: 0.84, blue: 0.9, alpha: 0.86)
        case (.pink, .dark): return OverlayColorComponents(red: 0.32, green: 0.18, blue: 0.24, alpha: 0.88)
        case (.green, .light): return OverlayColorComponents(red: 0.84, green: 0.95, blue: 0.84, alpha: 0.86)
        case (.green, .dark): return OverlayColorComponents(red: 0.16, green: 0.26, blue: 0.18, alpha: 0.88)
        case (.yellow, .light): return OverlayColorComponents(red: 1.0, green: 0.94, blue: 0.72, alpha: 0.86)
        case (.yellow, .dark): return OverlayColorComponents(red: 0.3, green: 0.26, blue: 0.12, alpha: 0.88)
        case (.blue, .light): return OverlayColorComponents(red: 0.82, green: 0.91, blue: 1.0, alpha: 0.86)
        case (.blue, .dark): return OverlayColorComponents(red: 0.14, green: 0.2, blue: 0.3, alpha: 0.88)
        case (.purple, .light): return OverlayColorComponents(red: 0.9, green: 0.84, blue: 1.0, alpha: 0.86)
        case (.purple, .dark): return OverlayColorComponents(red: 0.24, green: 0.18, blue: 0.32, alpha: 0.88)
        }
    }

    public static func textAlpha(for appearance: OverlayAppearance) -> Double {
        appearance == .light ? 0.68 : 0.92
    }

    public static func hintAlpha(for appearance: OverlayAppearance) -> Double {
        appearance == .light ? 0.42 : 0.6
    }

    public static func indicatorAlpha(for appearance: OverlayAppearance) -> Double {
        appearance == .light ? 0.34 : 0.7
    }

    public static func isLightText(for appearance: OverlayAppearance) -> Bool {
        appearance == .dark
    }
}
