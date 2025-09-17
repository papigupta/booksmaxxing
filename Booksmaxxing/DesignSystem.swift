import SwiftUI

// MARK: - Design System
// This is the single source of truth for all UI styling in the app.
// Any UI changes should be made here first, then propagated throughout the app.

enum DS {
    
    // MARK: - Colors
    enum Colors {
        // Core palette - Pure and sophisticated
        static let black = Color(hex: "000000")
        static let white = Color(hex: "FFFFFF")
        static let gray950 = Color(hex: "0A0A0A")    // Near black - for depth
        static let gray900 = Color(hex: "171717")    // Rich dark
        static let gray800 = Color(hex: "262626")    // Dark accent
        static let gray700 = Color(hex: "404040")    // Medium dark
        static let gray600 = Color(hex: "525252")    // Balanced gray
        static let gray500 = Color(hex: "737373")    // True middle
        static let gray400 = Color(hex: "A3A3A3")    // Light medium
        static let gray300 = Color(hex: "D4D4D4")    // Light
        static let gray200 = Color(hex: "E5E5E5")    // Very light
        static let gray100 = Color(hex: "F5F5F5")    // Near white
        static let gray50 = Color(hex: "FAFAFA")     // Subtle background
        
        // App background
        static let appBackground = Color(hex: "DBDBDB")  // Light grey default app background
        
        // Semantic colors - Sophisticated hierarchy
        static let primaryText = gray950
        static let secondaryText = gray700
        static let tertiaryText = gray500
        static let disabledText = gray400
        static let primaryBackground = white
        static let secondaryBackground = gray50
        static let tertiaryBackground = gray100
        static let accentBackground = gray950
        static let border = gray950
        static let subtleBorder = gray300
        static let divider = gray200
        static let shadow = gray950.opacity(0.08)
        static let overlay = gray950.opacity(0.04)
    }
    
    // MARK: - Typography
    enum Typography {
        // Default letter spacing (-2% for all text)
        static func defaultTracking(for size: CGFloat) -> CGFloat {
            return size * -0.02
        }
        
        // Special letter spacing (for titles, can go more negative)
        static func tightTracking(for size: CGFloat) -> CGFloat {
            return size * -0.03  // -3% for tighter spacing
        }
        
        // Fraunces font helpers
        static func fraunces(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            return Font.custom("Fraunces", size: size).weight(weight)
        }
        
        static func frauncesItalic(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            return Font.custom("Fraunces", size: size).italic().weight(weight)
        }
        
        // Display hierarchy - Commanding presence with Fraunces
        static let hero = fraunces(size: 40, weight: .black)
        static let heroTracking = defaultTracking(for: 40)
        
        static let largeTitle = fraunces(size: 32, weight: .heavy)
        static let largeTitleTracking = defaultTracking(for: 32)
        
        static let title = fraunces(size: 24, weight: .bold)
        static let titleTracking = defaultTracking(for: 24)
        
        static let title2 = fraunces(size: 20, weight: .semibold)
        static let title2Tracking = defaultTracking(for: 20)
        
        // Content hierarchy - All using Fraunces now
        static let headline = fraunces(size: 18, weight: .semibold)
        static let headlineTracking = defaultTracking(for: 18)
        
        static let subheadline = fraunces(size: 16, weight: .medium)
        static let subheadlineTracking = defaultTracking(for: 16)
        
        static let body = fraunces(size: 16, weight: .regular)
        static let bodyTracking = defaultTracking(for: 16)
        
        static let bodyEmphasized = fraunces(size: 16, weight: .medium)
        static let bodyEmphasizedTracking = defaultTracking(for: 16)
        
        static let bodyBold = fraunces(size: 16, weight: .semibold)
        static let bodyBoldTracking = defaultTracking(for: 16)
        
        // Supporting hierarchy - Fraunces throughout
        static let callout = fraunces(size: 15, weight: .regular)
        static let calloutTracking = defaultTracking(for: 15)
        
        static let caption = fraunces(size: 14, weight: .regular)
        static let captionTracking = defaultTracking(for: 14)
        
        static let captionEmphasized = fraunces(size: 14, weight: .medium)
        static let captionEmphasizedTracking = defaultTracking(for: 14)
        
        static let captionBold = fraunces(size: 14, weight: .semibold)
        static let captionBoldTracking = defaultTracking(for: 14)
        
        static let footnote = fraunces(size: 13, weight: .regular)
        static let footnoteTracking = defaultTracking(for: 13)
        
        static let small = fraunces(size: 12, weight: .regular)
        static let smallTracking = defaultTracking(for: 12)
        
        static let micro = fraunces(size: 11, weight: .medium)
        static let microTracking = defaultTracking(for: 11)
        
        // Special purpose - Keep system fonts for code and numbers
        static let code = Font.system(size: 15, weight: .regular, design: .monospaced)
        static let codeTracking = CGFloat(0)  // No tracking for monospaced
        
        static let number = fraunces(size: 16, weight: .medium)
        static let numberTracking = defaultTracking(for: 16)
        
        // Additional Fraunces variants for special use
        static let frauncesBody = fraunces(size: 16, weight: .regular)
        static let frauncesBodyTracking = defaultTracking(for: 16)
        
        static let frauncesBodyBold = fraunces(size: 16, weight: .semibold)
        static let frauncesBodyBoldTracking = defaultTracking(for: 16)
        
        static let frauncesHeadline = fraunces(size: 18, weight: .semibold)
        static let frauncesHeadlineTracking = defaultTracking(for: 18)
        
        static let frauncesCaption = fraunces(size: 14, weight: .regular)
        static let frauncesCaptionTracking = defaultTracking(for: 14)
    }
    
    // MARK: - Spacing
    enum Spacing {
        // Micro spacing - Precision details
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        
        // Standard spacing - Comfortable rhythm
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        
        // Macro spacing - Generous breathing room
        static let xxxl: CGFloat = 48
        static let huge: CGFloat = 64
        static let massive: CGFloat = 96
        
        // Layout spacing - Structural harmony
        static let section: CGFloat = 40
        static let page: CGFloat = 20
        static let container: CGFloat = 16
        static let gutter: CGFloat = 8
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let none: CGFloat = 0 // Sharp edges everywhere
    }
    
    // MARK: - Border Width
    enum BorderWidth {
        static let hairline: CGFloat = 0.5
        static let thin: CGFloat = 1
        static let medium: CGFloat = 2
        static let thick: CGFloat = 3
        static let bold: CGFloat = 4
    }
    
    // MARK: - Elevation & Depth
    enum Shadow {
        // Subtle depth without breaking monochrome
        static let subtle = (
            color: DS.Colors.shadow,
            radius: CGFloat(2),
            x: CGFloat(0),
            y: CGFloat(1)
        )
        
        static let soft = (
            color: DS.Colors.shadow,
            radius: CGFloat(4),
            x: CGFloat(0),
            y: CGFloat(2)
        )
        
        static let medium = (
            color: DS.Colors.shadow,
            radius: CGFloat(8),
            x: CGFloat(0),
            y: CGFloat(4)
        )
        
        static let strong = (
            color: DS.Colors.shadow,
            radius: CGFloat(16),
            x: CGFloat(0),
            y: CGFloat(8)
        )
    }
    
    // MARK: - Animation
    enum Animation {
        static let quick = 0.2
        static let smooth = 0.3
        static let gentle = 0.4
        static let slow = 0.6
        
        static let spring = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
        static let easeOut = SwiftUI.Animation.easeOut(duration: 0.3)
        static let easeIn = SwiftUI.Animation.easeIn(duration: 0.2)
    }
}

// MARK: - Button Styles

struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyEmphasized)
            .foregroundColor(isEnabled ? DS.Colors.white : DS.Colors.disabledText)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(
                Rectangle()
                    .fill(isEnabled ? DS.Colors.accentBackground : DS.Colors.gray200)
                    .shadow(
                        color: isEnabled ? DS.Shadow.soft.color : Color.clear,
                        radius: DS.Shadow.soft.radius,
                        x: DS.Shadow.soft.x,
                        y: DS.Shadow.soft.y
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DS.Animation.spring, value: configuration.isPressed)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyEmphasized)
            .foregroundColor(isEnabled ? DS.Colors.primaryText : DS.Colors.disabledText)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(
                Rectangle()
                    .fill(DS.Colors.primaryBackground)
                    .shadow(
                        color: DS.Shadow.subtle.color,
                        radius: DS.Shadow.subtle.radius,
                        x: DS.Shadow.subtle.x,
                        y: DS.Shadow.subtle.y
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(
                        isEnabled ? DS.Colors.border : DS.Colors.subtleBorder,
                        lineWidth: DS.BorderWidth.medium
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DS.Animation.spring, value: configuration.isPressed)
    }
}

struct DSTertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyEmphasized)
            .foregroundColor(isEnabled ? DS.Colors.primaryText : DS.Colors.disabledText)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(
                Rectangle()
                    .fill(DS.Colors.overlay)
                    .opacity(configuration.isPressed ? 1.0 : 0.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DS.Animation.easeOut, value: configuration.isPressed)
    }
}

struct DSSmallButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.captionEmphasized)
            .foregroundColor(isEnabled ? DS.Colors.primaryText : DS.Colors.disabledText)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: 32)
            .background(
                Rectangle()
                    .fill(DS.Colors.primaryBackground)
                    .shadow(
                        color: DS.Shadow.subtle.color,
                        radius: DS.Shadow.subtle.radius,
                        x: DS.Shadow.subtle.x,
                        y: DS.Shadow.subtle.y
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(
                        isEnabled ? DS.Colors.subtleBorder : DS.Colors.gray200,
                        lineWidth: DS.BorderWidth.thin
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DS.Animation.spring, value: configuration.isPressed)
    }
}

// MARK: - Card Styles

struct DSCardModifier: ViewModifier {
    var padding: CGFloat = DS.Spacing.lg
    var borderColor: Color = DS.Colors.subtleBorder
    var backgroundColor: Color = DS.Colors.primaryBackground
    var elevation: Bool = true
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Rectangle()
                    .fill(backgroundColor)
                    .shadow(
                        color: elevation ? DS.Shadow.soft.color : Color.clear,
                        radius: elevation ? DS.Shadow.soft.radius : 0,
                        x: elevation ? DS.Shadow.soft.x : 0,
                        y: elevation ? DS.Shadow.soft.y : 0
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: DS.BorderWidth.hairline)
            )
    }
}

struct DSSubtleCardModifier: ViewModifier {
    var padding: CGFloat = DS.Spacing.lg
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Rectangle()
                    .fill(DS.Colors.secondaryBackground)
                    .shadow(
                        color: DS.Shadow.subtle.color,
                        radius: DS.Shadow.subtle.radius,
                        x: DS.Shadow.subtle.x,
                        y: DS.Shadow.subtle.y
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(DS.Colors.gray200, lineWidth: DS.BorderWidth.hairline)
            )
    }
}

// MARK: - Enhanced Card Variants

struct DSAccentCardModifier: ViewModifier {
    var padding: CGFloat = DS.Spacing.lg
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Rectangle()
                    .fill(DS.Colors.accentBackground)
                    .shadow(
                        color: DS.Shadow.medium.color,
                        radius: DS.Shadow.medium.radius,
                        x: DS.Shadow.medium.x,
                        y: DS.Shadow.medium.y
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(DS.Colors.gray800, lineWidth: DS.BorderWidth.thin)
            )
    }
}

struct DSElevatedCardModifier: ViewModifier {
    var padding: CGFloat = DS.Spacing.xl
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Rectangle()
                    .fill(DS.Colors.primaryBackground)
                    .shadow(
                        color: DS.Shadow.strong.color,
                        radius: DS.Shadow.strong.radius,
                        x: DS.Shadow.strong.x,
                        y: DS.Shadow.strong.y
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(DS.Colors.border, lineWidth: DS.BorderWidth.medium)
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
    
    func dsCard(padding: CGFloat = DS.Spacing.lg, borderColor: Color = DS.Colors.subtleBorder, backgroundColor: Color = DS.Colors.primaryBackground, elevation: Bool = true) -> some View {
        self.modifier(DSCardModifier(padding: padding, borderColor: borderColor, backgroundColor: backgroundColor, elevation: elevation))
    }
    
    func dsSubtleCard(padding: CGFloat = DS.Spacing.lg) -> some View {
        self.modifier(DSSubtleCardModifier(padding: padding))
    }
    
    func dsAccentCard(padding: CGFloat = DS.Spacing.lg) -> some View {
        self.modifier(DSAccentCardModifier(padding: padding))
    }
    
    func dsElevatedCard(padding: CGFloat = DS.Spacing.xl) -> some View {
        self.modifier(DSElevatedCardModifier(padding: padding))
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
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Sophisticated loading animation
            ZStack {
                Circle()
                    .stroke(DS.Colors.gray200, lineWidth: 2)
                    .frame(width: 48, height: 48)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        DS.Colors.accentBackground,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1.2).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            
            VStack(spacing: DS.Spacing.sm) {
                Text(message)
                    .font(DS.Typography.subheadline)
                    .foregroundColor(DS.Colors.primaryText)
                    .multilineTextAlignment(.center)
                
                Text("Please wait")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.primaryBackground)
        .onAppear {
            isAnimating = true
        }
    }
}

struct DSErrorView: View {
    let title: String
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: DS.Spacing.xxxl) {
            // Sophisticated error icon
            ZStack {
                Circle()
                    .fill(DS.Colors.gray100)
                    .frame(width: 80, height: 80)
                    .shadow(
                        color: DS.Shadow.subtle.color,
                        radius: DS.Shadow.subtle.radius,
                        x: DS.Shadow.subtle.x,
                        y: DS.Shadow.subtle.y
                    )
                
                DSIcon("exclamationmark.triangle.fill", size: 32)
                    .foregroundStyle(DS.Colors.accentBackground)
            }
            
            VStack(spacing: DS.Spacing.lg) {
                VStack(spacing: DS.Spacing.sm) {
                    Text(title)
                        .font(DS.Typography.title2)
                        .foregroundColor(DS.Colors.primaryText)
                        .multilineTextAlignment(.center)
                    
                    Text(message)
                        .font(DS.Typography.body)
                        .foregroundColor(DS.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
                
                Button("Try Again", action: retryAction)
                    .dsSecondaryButton()
                    .frame(maxWidth: 200)
            }
        }
        .dsElevatedCard()
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.secondaryBackground)
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
    }
}