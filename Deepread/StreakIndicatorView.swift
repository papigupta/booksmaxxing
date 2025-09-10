import SwiftUI

struct StreakIndicatorView: View {
    @EnvironmentObject var streakManager: StreakManager

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: streakManager.isLitToday ? "flame.fill" : "flame")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(streakManager.isLitToday ? .orange : DS.Colors.secondaryText)
            Text("\(streakManager.currentStreak)")
                .font(DS.Typography.captionBold)
                .foregroundColor(DS.Colors.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.Colors.secondaryBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.Colors.subtleBorder, lineWidth: DS.BorderWidth.thin)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .opacity(streakManager.isTestingActive ? 0.0 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: streakManager.isTestingActive)
    }
}

