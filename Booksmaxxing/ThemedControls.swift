import SwiftUI

struct ThemedPrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return configuration.label
            .font(DS.Typography.bodyEmphasized)
            .foregroundColor(theme.onPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .background(Rectangle().fill(theme.primary))
            .overlay(Rectangle().stroke(theme.primary, lineWidth: DS.BorderWidth.thin))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct ThemedSecondaryButtonStyle: ButtonStyle {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return configuration.label
            .font(DS.Typography.bodyEmphasized)
            .foregroundColor(theme.onSurface)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .background(Rectangle().fill(theme.surface))
            .overlay(Rectangle().stroke(theme.outline, lineWidth: DS.BorderWidth.thin))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct ThemedTertiaryButtonStyle: ButtonStyle {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return configuration.label
            .font(DS.Typography.captionEmphasized)
            .foregroundColor(theme.onSurface)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(Rectangle().fill(theme.surface))
            .overlay(Rectangle().stroke(theme.outline, lineWidth: DS.BorderWidth.hairline))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct ThemedCardModifier: ViewModifier {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return content
            .padding(DS.Spacing.md)
            .background(theme.surfaceVariant)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.outline, lineWidth: DS.BorderWidth.thin))
            .cornerRadius(8)
    }
}

extension View {
    func themePrimaryButton() -> some View { self.buttonStyle(ThemedPrimaryButtonStyle()) }
    func themeSecondaryButton() -> some View { self.buttonStyle(ThemedSecondaryButtonStyle()) }
    func themeTertiaryButton() -> some View { self.buttonStyle(ThemedTertiaryButtonStyle()) }
    func themedCard() -> some View { self.modifier(ThemedCardModifier()) }
}

