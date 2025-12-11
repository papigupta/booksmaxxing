import SwiftUI

struct BrainCaloriesView: View {
    // BCal
    let sessionBCal: Int
    let todayBCalTotal: Int
    // Accuracy (surfaced to users as "Clarity" – see PROJECT_OVERVIEW.md)
    let sessionCorrect: Int
    let sessionTotal: Int
    let todayCorrect: Int
    let todayTotal: Int
    let goalAccuracyPercent: Int
    // Attention
    let sessionPauses: Int
    let todayPauses: Int
    let todayAttentionPercent: Int
    let onContinue: () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var animatedBcalProgress: Double = 0
    @State private var animatedAccuracyProgress: Double = 0
    @State private var animatedAttentionProgress: Double = 0

    private let bcalGoal = 200

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                ringsHeroCard

                HStack {
                    Spacer()
                    Button("Continue") { onContinue() }
                        .dsPalettePrimaryButton()
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.xxl)
        }
        .background(practiceBackground.ignoresSafeArea())
        .onAppear {
            UserAnalyticsService.shared.markActivityRingsViewed()
            UserAnalyticsService.shared.markResultsViewed()
            animateRings()
        }
        .onChange(of: animationSignature) { _, _ in
            animateRings()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Today’s Rings")
                .font(DS.Typography.title2)
                .foregroundStyle(theme.onSurface)

            Text("Close every ring to keep your brain sharp—burn calories, stay clear, and remain distraction-free.")
                .font(DS.Typography.caption)
                .foregroundStyle(theme.onSurface.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ringsHeroCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
            header

            ActivityRingsView(
                bcalProgress: animatedBcalProgress,
                accuracyProgress: animatedAccuracyProgress,
                attentionProgress: animatedAttentionProgress
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                ActivityMetricRow(
                    iconName: "brain.head.profile",
                    color: .red,
                    title: "Brain Calories",
                    valueText: "\(todayBCalTotal) BCal",
                    detailLines: bcalDetailLines,
                    textColor: theme.onSurface,
                    secondaryColor: theme.onSurface.opacity(0.7)
                )

                ActivityMetricRow(
                    iconName: "dot.scope",
                    color: .blue,
                    title: "Clarity",
                    valueText: "\(todayAccuracyPercentInt)%",
                    detailLines: clarityDetailLines,
                    textColor: theme.onSurface,
                    secondaryColor: theme.onSurface.opacity(0.7)
                )

                ActivityMetricRow(
                    iconName: "bell.slash",
                    color: .green,
                    title: "Attention",
                    valueText: "\(todayAttentionPercent)%",
                    detailLines: attentionDetailLines,
                    textColor: theme.onSurface,
                    secondaryColor: theme.onSurface.opacity(0.7)
                )
            }
        }
        .padding(DS.Spacing.xl)
        .brainCardBackground(theme: theme, cornerRadius: 32, fill: theme.surface)
    }

    private var todayAccuracyPercentRaw: Double {
        guard todayTotal > 0 else { return 0 }
        return (Double(todayCorrect) / Double(todayTotal)) * 100.0
    }

    private var todayAccuracyPercentInt: Int {
        Int(round(min(todayAccuracyPercentRaw, 100)))
    }

    private var sessionAccuracyText: String {
        guard sessionTotal > 0 else { return "No questions yet" }
        return "\(sessionCorrect)/\(sessionTotal) correct"
    }

    private var todayAccuracyText: String {
        guard todayTotal > 0 else { return "No questions yet" }
        return "\(todayCorrect)/\(todayTotal) correct"
    }

    private var sessionAttentionText: String {
        "\(sessionPauses) distraction\(sessionPauses == 1 ? "" : "s")"
    }

    private var todayAttentionText: String {
        "\(todayPauses) distraction\(todayPauses == 1 ? "" : "s")"
    }

    private var todayAttentionSummary: String {
        "\(todayAttentionPercent)% focus • \(todayAttentionText)"
    }

    private func percentText(for progress: Double) -> String {
        let percentValue = Int(round(max(progress, 0) * 100))
        return "\(percentValue)%"
    }

    private var bcalDetailLines: [String] {
        var lines: [String] = [
            "\(todayBCalTotal) / \(bcalGoal) BCal today",
            "\(percentText(for: ringBcalProgress)) of your BCal goal"
        ]
        if sessionBCal > 0 {
            lines.append("This session \(sessionBCal) BCal")
        }
        return lines
    }

    private var clarityDetailLines: [String] {
        var lines: [String] = ["\(todayAccuracyPercentInt)% of \(goalAccuracyPercent)% clarity goal"]
        if todayTotal > 0 {
            lines.append(todayAccuracyText)
        }
        if sessionTotal > 0 {
            lines.append("Session: \(sessionAccuracyText)")
        }
        return lines
    }

    private var attentionDetailLines: [String] {
        var lines: [String] = [todayAttentionSummary]
        if sessionPauses > 0 {
            lines.append("Session: \(sessionAttentionText)")
        }
        return lines
    }

    private var cardBcalProgress: Double {
        min(ringBcalProgress, 1.0)
    }

    private var cardAccuracyProgress: Double {
        min(ringAccuracyProgress, 1.0)
    }

    private var cardAttentionProgress: Double {
        min(ringAttentionProgress, 1.0)
    }

    private var ringBcalProgress: Double {
        guard bcalGoal > 0 else { return 0 }
        return max(Double(todayBCalTotal) / Double(bcalGoal), 0)
    }

    private var ringAccuracyProgress: Double {
        guard goalAccuracyPercent > 0 else { return 0 }
        return max(todayAccuracyPercentRaw / Double(goalAccuracyPercent), 0)
    }

    private var ringAttentionProgress: Double {
        max(Double(todayAttentionPercent) / 100.0, 0)
    }

    private var animationSignature: String {
        "\(todayBCalTotal)-\(todayCorrect)-\(todayPauses)-\(todayAttentionPercent)"
    }

    private var theme: ThemeTokens {
        themeManager.currentTokens(for: colorScheme)
    }

    private var practiceBackground: Color {
        themeManager.activeRoles.practiceBackgroundColor(fallback: theme)
    }

    private func animateRings() {
        animatedBcalProgress = 0
        animatedAccuracyProgress = 0
        animatedAttentionProgress = 0

        let bcalTarget = ringBcalProgress
        let accuracyTarget = ringAccuracyProgress
        let attentionTarget = ringAttentionProgress

        withAnimation(.easeOut(duration: 0.65)) {
            animatedBcalProgress = bcalTarget
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.55)) {
                animatedAccuracyProgress = accuracyTarget
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.5)) {
                    animatedAttentionProgress = attentionTarget
                }
            }
        }
    }
}

// MARK: - Triple Rings View

private struct ActivityRingsView: View {
    let bcalProgress: Double
    let accuracyProgress: Double
    let attentionProgress: Double

    private let outerSize: CGFloat = 250
    private let ringLineWidth: CGFloat = 26
    private let laneSpacing: CGFloat = 12
    private let startAngle = Angle(degrees: -90)

    private var ringOffset: CGFloat { (ringLineWidth + laneSpacing) * 2 }
    private var middleSize: CGFloat { outerSize - ringOffset }
    private var innerSize: CGFloat { middleSize - ringOffset }

    var body: some View {
        ZStack {
            ActivityRingLayer(
                progress: bcalProgress,
                style: .brainCalories,
                diameter: outerSize,
                lineWidth: ringLineWidth,
                startAngle: startAngle
            )

            ActivityRingLayer(
                progress: accuracyProgress,
                style: .clarity,
                diameter: middleSize,
                lineWidth: ringLineWidth,
                startAngle: startAngle
            )

            ActivityRingLayer(
                progress: attentionProgress,
                style: .attention,
                diameter: innerSize,
                lineWidth: ringLineWidth,
                startAngle: startAngle
            )
        }
        .frame(width: outerSize, height: outerSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today’s rings progress")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Shows progress for Brain Calories, Clarity, and Attention goals today.")
    }

    private var accessibilitySummary: String {
        "Brain Calories \(percentString(for: bcalProgress)), Clarity \(percentString(for: accuracyProgress)), Attention \(percentString(for: attentionProgress))"
    }

    private func percentString(for progress: Double) -> String {
        let percent = Int(round(max(progress, 0) * 100))
        return "\(percent)%"
    }
}

private struct ActivityRingLayer: View {
    let progress: Double
    let style: ActivityRingStyle
    let diameter: CGFloat
    let lineWidth: CGFloat
    let startAngle: Angle

    private var trimmedProgress: Double { min(max(progress, 0), 1) }
    private var overflow: Double { max(progress - 1, 0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(style.trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: CGFloat(trimmedProgress))
                .stroke(style.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(startAngle)
                .frame(width: diameter, height: diameter)
                .shadow(color: style.shadowColor, radius: 9, x: 0, y: 4)

            ActivityRingTip(
                progress: trimmedProgress,
                diameter: diameter,
                lineWidth: lineWidth,
                startAngle: startAngle,
                color: style.tipColor
            )

            if overflow > 0 {
                Circle()
                    .stroke(style.gradient, lineWidth: lineWidth * 0.6)
                    .frame(width: diameter + 12, height: diameter + 12)
                    .blur(radius: 14)
                    .opacity(min(0.45, 0.25 + overflow * 0.2))
            }
        }
    }
}

private struct ActivityRingTip: View {
    let progress: Double
    let diameter: CGFloat
    let lineWidth: CGFloat
    let startAngle: Angle
    let color: Color

    var body: some View {
        Group {
            if progress > 0 {
                Circle()
                    .fill(color)
                    .frame(width: lineWidth * 0.7, height: lineWidth * 0.7)
                    .shadow(color: color.opacity(0.6), radius: 5, x: 0, y: 2)
                    .offset(tipOffset)
            }
        }
    }

    private var tipOffset: CGSize {
        let angle = startAngle + .degrees(progress * 360)
        let radius = (diameter / 2) - (lineWidth / 2)
        let x = CGFloat(cos(angle.radians)) * radius
        let y = CGFloat(sin(angle.radians)) * radius
        return CGSize(width: x, height: y)
    }
}

private struct ActivityRingStyle {
    let gradient: AngularGradient
    let trackColor: Color
    let shadowColor: Color
    let tipColor: Color

    static let brainCalories = ActivityRingStyle(
        gradient: AngularGradient(
            gradient: Gradient(colors: [
                Color(red: 1.0, green: 0.47, blue: 0.36),
                Color(red: 0.94, green: 0.17, blue: 0.33),
                Color(red: 1.0, green: 0.47, blue: 0.36)
            ]),
            center: .center,
            startAngle: .degrees(-120),
            endAngle: .degrees(240)
        ),
        trackColor: Color(red: 1.0, green: 0.41, blue: 0.34).opacity(0.22),
        shadowColor: Color(red: 0.88, green: 0.12, blue: 0.31).opacity(0.4),
        tipColor: .white
    )

    static let clarity = ActivityRingStyle(
        gradient: AngularGradient(
            gradient: Gradient(colors: [
                Color(red: 0.45, green: 0.76, blue: 1.0),
                Color(red: 0.14, green: 0.44, blue: 0.93),
                Color(red: 0.45, green: 0.76, blue: 1.0)
            ]),
            center: .center,
            startAngle: .degrees(-120),
            endAngle: .degrees(240)
        ),
        trackColor: Color(red: 0.18, green: 0.45, blue: 0.93).opacity(0.18),
        shadowColor: Color(red: 0.1, green: 0.32, blue: 0.75).opacity(0.35),
        tipColor: .white
    )

    static let attention = ActivityRingStyle(
        gradient: AngularGradient(
            gradient: Gradient(colors: [
                Color(red: 0.45, green: 0.92, blue: 0.47),
                Color(red: 0.0, green: 0.66, blue: 0.36),
                Color(red: 0.45, green: 0.92, blue: 0.47)
            ]),
            center: .center,
            startAngle: .degrees(-120),
            endAngle: .degrees(240)
        ),
        trackColor: Color(red: 0.0, green: 0.62, blue: 0.31).opacity(0.16),
        shadowColor: Color(red: 0.0, green: 0.58, blue: 0.28).opacity(0.45),
        tipColor: .white
    )
}

private struct RingIconBadge: View {
    let systemName: String
    let color: Color
    let size: CGFloat

    init(systemName: String, color: Color, size: CGFloat = 44) {
        self.systemName = systemName
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

private struct ActivityMetricRow: View {
    let iconName: String
    let color: Color
    let title: String
    let valueText: String
    let detailLines: [String]
    let textColor: Color
    let secondaryColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.lg) {
            RingIconBadge(systemName: iconName, color: color)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(DS.Typography.bodyEmphasized)
                        .foregroundStyle(textColor)

                    Spacer()

                    Text(valueText)
                        .font(DS.Typography.bodyBold)
                        .foregroundStyle(textColor)
                }

                ForEach(detailLines, id: \.self) { line in
                    Text(line)
                        .font(DS.Typography.caption)
                        .foregroundStyle(secondaryColor)
                }
            }
        }
    }
}

private extension View {
    func brainCardBackground(theme: ThemeTokens, cornerRadius: CGFloat = 28, fill: Color? = nil) -> some View {
        let backgroundColor = fill ?? theme.surface
        return self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .shadow(
                        color: DS.Shadow.medium.color,
                        radius: DS.Shadow.medium.radius,
                        x: DS.Shadow.medium.x,
                        y: DS.Shadow.medium.y
                    )
            )
    }
}

#Preview {
    BrainCaloriesView(
        sessionBCal: 220,
        todayBCalTotal: 420,
        sessionCorrect: 7,
        sessionTotal: 8,
        todayCorrect: 16,
        todayTotal: 20,
        goalAccuracyPercent: 80,
        sessionPauses: 1,
        todayPauses: 2,
        todayAttentionPercent: 50,
        onContinue: {}
    )
    .environmentObject(ThemeManager())
}

#Preview("BrainCaloriesView – Dark") {
    BrainCaloriesView(
        sessionBCal: 120,
        todayBCalTotal: 180,
        sessionCorrect: 6,
        sessionTotal: 10,
        todayCorrect: 12,
        todayTotal: 18,
        goalAccuracyPercent: 90,
        sessionPauses: 0,
        todayPauses: 1,
        todayAttentionPercent: 85,
        onContinue: {}
    )
    .environmentObject(ThemeManager())
    .preferredColorScheme(.dark)
}
