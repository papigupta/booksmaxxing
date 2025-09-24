import SwiftUI

// MARK: - Theme Presets

enum ThemePreset: String, CaseIterable, Identifiable {
    case system = "System" // treated as System Light
    case systemDark = "System Dark"
    case eInk = "E‑Ink"
    case classicMac = "Classic Mac"
    case paper = "Paper"

    var id: String { rawValue }

    // Preferred system color scheme mapping
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return .light
        case .systemDark: return .dark
        default: return nil
        }
    }

    // Visual filter parameters applied globally for quick experimentation
    var saturation: Double {
        switch self {
        case .system: return 1.0
        case .systemDark: return 1.0
        case .eInk: return 0.0
        case .classicMac: return 0.0
        case .paper: return 0.0
        }
    }

    var contrast: Double {
        switch self {
        case .system: return 1.0
        case .systemDark: return 1.0
        case .eInk: return 1.18
        case .classicMac: return 1.35
        case .paper: return 0.95
        }
    }

    var brightness: Double {
        switch self {
        case .system: return 0.0
        case .systemDark: return 0.0
        case .eInk: return 0.02
        case .classicMac: return 0.04
        case .paper: return 0.05
        }
    }

    // Optional color multiply to push the background tone (e.g., paper tint)
    var multiplyColor: Color {
        switch self {
        case .system: return .white
        case .systemDark: return .white
        case .eInk: return .white
        case .classicMac: return Color(hex: "F0F0F0")
        case .paper: return Color(hex: "F8F5E7")
        }
    }
}

// MARK: - Global Theme Filter

struct ThemeFilter: ViewModifier {
    let preset: ThemePreset

    func body(content: Content) -> some View {
        if preset == .system || preset == .systemDark {
            content
        } else {
            content
                .saturation(preset.saturation)
                .contrast(preset.contrast)
                .brightness(preset.brightness)
                .colorMultiply(preset.multiplyColor)
        }
    }
}

extension View {
    func applyTheme(_ preset: ThemePreset) -> some View {
        self.modifier(ThemeFilter(preset: preset))
    }
}
