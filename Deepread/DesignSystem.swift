import SwiftUI

// MARK: - Design System
// This is the single source of truth for all UI styling in the app.
// Any UI changes should be made here first, then propagated throughout the app.

enum DS {
    
    // MARK: - Colors
    enum Colors {
        static let black = Color.black
        static let white = Color.white
        static let gray900 = Color(hex: "1A1A1A")
        static let gray700 = Color(hex: "4A4A4A")
        static let gray500 = Color(hex: "7A7A7A")
        static let gray300 = Color(hex: "BABABA")
        static let gray100 = Color(hex: "F0F0F0")
        static let gray50 = Color(hex: "FAFAFA")
        
        // Semantic colors
        static let primaryText = black
        static let secondaryText = gray700
        static let tertiaryText = gray500
        static let disabledText = gray500
        static let primaryBackground = white
        static let secondaryBackground = gray50
        static let tertiaryBackground = gray100
        static let border = black
        static let subtleBorder = gray300
        static let divider = gray300
    }
    
    // MARK: - Typography
    enum Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold, design: .default)
        static let title = Font.system(size: 24, weight: .bold, design: .default)
        static let headline = Font.system(size: 18, weight: .semibold, design: .default)
        static let body = Font.system(size: 16, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 16, weight: .semibold, design: .default)
        static let caption = Font.system(size: 14, weight: .regular, design: .default)
        static let captionBold = Font.system(size: 14, weight: .semibold, design: .default)
        static let small = Font.system(size: 12, weight: .regular, design: .default)
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let none: CGFloat = 0 // Sharp edges everywhere
    }
    
    // MARK: - Border Width
    enum BorderWidth {
        static let thin: CGFloat = 1
        static let medium: CGFloat = 2
        static let thick: CGFloat = 3
    }
}

// MARK: - Button Styles

struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyBold)
            .foregroundColor(isEnabled ? DS.Colors.white : DS.Colors.disabledText)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? DS.Colors.black : DS.Colors.gray100)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyBold)
            .foregroundColor(isEnabled ? DS.Colors.black : DS.Colors.disabledText)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(DS.Colors.white)
            .overlay(
                Rectangle()
                    .stroke(isEnabled ? DS.Colors.black : DS.Colors.gray300, lineWidth: DS.BorderWidth.thin)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct DSTertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.body)
            .foregroundColor(isEnabled ? DS.Colors.black : DS.Colors.disabledText)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

struct DSSmallButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.caption)
            .foregroundColor(isEnabled ? DS.Colors.black : DS.Colors.disabledText)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Colors.white)
            .overlay(
                Rectangle()
                    .stroke(isEnabled ? DS.Colors.black : DS.Colors.gray300, lineWidth: DS.BorderWidth.thin)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Card Styles

struct DSCardModifier: ViewModifier {
    var padding: CGFloat = DS.Spacing.md
    var borderColor: Color = DS.Colors.border
    var backgroundColor: Color = DS.Colors.white
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: DS.BorderWidth.thin)
            )
    }
}

struct DSSubtleCardModifier: ViewModifier {
    var padding: CGFloat = DS.Spacing.md
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DS.Colors.secondaryBackground)
            .overlay(
                Rectangle()
                    .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
            )
    }
}

// MARK: - Text Field Style

struct DSTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Typography.body)
            .padding(DS.Spacing.sm)
            .background(DS.Colors.white)
            .overlay(
                Rectangle()
                    .stroke(DS.Colors.border, lineWidth: DS.BorderWidth.thin)
            )
    }
}

// MARK: - View Extensions

extension View {
    func dsPrimaryButton() -> some View {
        self.buttonStyle(DSPrimaryButtonStyle())
    }
    
    func dsSecondaryButton() -> some View {
        self.buttonStyle(DSSecondaryButtonStyle())
    }
    
    func dsTertiaryButton() -> some View {
        self.buttonStyle(DSTertiaryButtonStyle())
    }
    
    func dsSmallButton() -> some View {
        self.buttonStyle(DSSmallButtonStyle())
    }
    
    func dsCard(padding: CGFloat = DS.Spacing.md, borderColor: Color = DS.Colors.border, backgroundColor: Color = DS.Colors.white) -> some View {
        self.modifier(DSCardModifier(padding: padding, borderColor: borderColor, backgroundColor: backgroundColor))
    }
    
    func dsSubtleCard(padding: CGFloat = DS.Spacing.md) -> some View {
        self.modifier(DSSubtleCardModifier(padding: padding))
    }
    
    func dsTextField() -> some View {
        self.modifier(DSTextFieldModifier())
    }
}

// MARK: - Helper Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Common Components

struct DSDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Colors.divider)
            .frame(height: DS.BorderWidth.thin)
    }
}

struct DSLoadingView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                .scaleEffect(1.2)
            Text(message)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DSErrorView: View {
    let title: String
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(DS.Colors.black)
            
            VStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Typography.headline)
                    .foregroundColor(DS.Colors.primaryText)
                
                Text(message)
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Again", action: retryAction)
                .dsSecondaryButton()
                .frame(width: 160)
        }
        .padding(DS.Spacing.xl)
    }
}

// MARK: - Icon System

struct DSIcon: View {
    let systemName: String
    let size: CGFloat
    
    init(_ systemName: String, size: CGFloat = 20) {
        self.systemName = systemName
        self.size = size
    }
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundColor(DS.Colors.black)
    }
}