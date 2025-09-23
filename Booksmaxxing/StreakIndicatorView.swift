import SwiftUI

struct StreakIndicatorView: View {
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.currentTokens(for: colorScheme)
        return HStack(spacing: 6) {
            Image(systemName: streakManager.isLitToday ? "flame.fill" : "flame")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(streakManager.isLitToday ? theme.primary : theme.onSurface.opacity(0.6))
            Text("\(streakManager.currentStreak)")
                .font(DS.Typography.captionBold)
                .foregroundColor(theme.onSurface)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.surfaceVariant)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.outline, lineWidth: DS.BorderWidth.thin)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .opacity(streakManager.isTestingActive ? 0.0 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: streakManager.isTestingActive)
    }
}
