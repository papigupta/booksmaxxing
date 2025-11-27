import SwiftUI

struct StreakView: View {
    let onContinue: () -> Void

    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    private let heroIconSize: CGFloat = 64
    private let haloSize: CGFloat = 128
    private let haloBlur: CGFloat = 100
    private let horizontalPadding: CGFloat = 28

    private var tokens: ThemeTokens { themeManager.currentTokens(for: colorScheme) }
    private var backgroundColor: Color { themeManager.activeRoles.practiceBackgroundColor(fallback: tokens) }
    private var accentColor: Color {
        themeManager.activeRoles.color(role: .tertiary, tone: 40)
            ?? themeManager.activeRoles.color(role: .tertiary, tone: 50)
            ?? themeManager.activeRoles.color(role: .primary, tone: 40)
            ?? tokens.primary
    }
    private var cardBackgroundColor: Color {
        themeManager.activeRoles.color(role: .primary, tone: 95)
            ?? themeManager.activeRoles.color(role: .primary, tone: 98)
            ?? tokens.surface
    }
    private var secondaryTextColor: Color { tokens.onSurface.opacity(0.65) }
    private var currentStreakCount: Int { max(streakManager.currentStreak, 0) }
    private var bestStreakCount: Int { max(streakManager.bestStreak, 0) }
    private var streakHeadline: String {
        let suffix = currentStreakCount == 1 ? "day" : "days"
        return "\(currentStreakCount) \(suffix) streak"
    }
    private var heroCopy: String {
        if currentStreakCount <= 1 {
            return "You logged practice today. Get another session in before midnight tomorrow to start a run."
        } else {
            return "That's \(currentStreakCount) consecutive day\(currentStreakCount == 1 ? "" : "s"). Make time tomorrow before midnight to keep it alive."
        }
    }
    private var currentRunDetail: String {
        currentStreakCount == 1 ? "day in a row" : "days in a row"
    }
    private var bestRunValue: String {
        bestStreakCount > 0 ? "\(bestStreakCount)" : "—"
    }
    private var bestRunDetail: String {
        bestStreakCount > 0 ? "Personal best" : "No record yet"
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer(minLength: DS.Spacing.xxxl)

            heroSection

            VStack(spacing: DS.Spacing.lg) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Spacing.lg) {
                        statCard(title: "Current run", value: "\(currentStreakCount)", detail: currentRunDetail)
                        statCard(title: "Best run", value: bestRunValue, detail: bestRunDetail)
                    }
                    VStack(spacing: DS.Spacing.lg) {
                        statCard(title: "Current run", value: "\(currentStreakCount)", detail: currentRunDetail)
                        statCard(title: "Best run", value: bestRunValue, detail: bestRunDetail)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Continue") { onContinue() }
                    .dsPalettePrimaryButton()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, horizontalPadding)
        .padding(.bottom, horizontalPadding)
        .background(backgroundColor.ignoresSafeArea())
    }

    private var heroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: heroIconSize + 56, height: heroIconSize + 56)
                Circle()
                    .fill(accentColor.opacity(0.7))
                    .frame(width: haloSize, height: haloSize)
                    .blur(radius: haloBlur)

                Image(systemName: "flame.fill")
                    .font(.system(size: heroIconSize, weight: .bold))
                    .foregroundColor(accentColor)
            }
            .frame(width: haloSize, height: haloSize)

            Text(streakHeadline)
                .font(DS.Typography.title)
                .tracking(DS.Typography.titleTracking)
                .foregroundColor(tokens.onSurface)

            Text(heroCopy)
                .font(DS.Typography.body)
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalPadding)
        }
        .frame(maxWidth: .infinity)
    }

    private func statCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .center, spacing: DS.Spacing.xs) {
            Text(title.uppercased())
                .font(DS.Typography.caption)
                .tracking(DS.Typography.captionTracking)
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)

            Text(value)
                .font(DS.Typography.title2)
                .tracking(DS.Typography.title2Tracking)
                .foregroundColor(tokens.onSurface)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(DS.Typography.caption)
                .foregroundColor(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, DS.Spacing.lg)
        .padding(.horizontal, DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(color: DS.Colors.shadow, radius: 16, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(cardBackgroundColor.opacity(0.5), lineWidth: 1)
        )
    }
}

#Preview {
    StreakView(onContinue: {})
        .environmentObject(StreakManager())
        .environmentObject(ThemeManager())
}
