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
                header

                ringsSection

                VStack(spacing: DS.Spacing.lg) {
                    metricCard(
                        iconName: "brain.head.profile",
                        title: "Brain Calories",
                        subtitle: "Mental load burned today",
                        valueText: "\(todayBCalTotal) BCal",
                        goalText: "Goal \(bcalGoal) BCal",
                        progress: cardBcalProgress,
                        progressDescription: "\(todayBCalTotal) / \(bcalGoal) BCal",
                        color: .red,
                        rows: [
                            ("This session", "\(sessionBCal) BCal"),
                            ("Today total", "\(todayBCalTotal) BCal")
                        ]
                    )

                    metricCard(
                        iconName: "dot.scope",
                        title: "Clarity",
                        subtitle: "Knowledge retained",
                        valueText: "\(todayAccuracyPercentInt)%",
                        goalText: "Goal \(goalAccuracyPercent)% Clarity",
                        progress: cardAccuracyProgress,
                        progressDescription: "\(todayAccuracyPercentInt)% of \(goalAccuracyPercent)% clarity target",
                        color: .blue,
                        rows: [
                            ("This session", sessionAccuracyText),
                            ("Today total", todayAccuracyText)
                        ]
                    )

                    metricCard(
                        iconName: "bell.slash",
                        title: "Attention",
                        subtitle: "Stay in the zone",
                        valueText: "\(todayAttentionPercent)%",
                        goalText: "0 distractions",
                        progress: cardAttentionProgress,
                        progressDescription: "\(todayAttentionPercent)% focus today",
                        color: .green,
                        rows: [
                            ("This session", sessionAttentionText),
                            ("Today total", todayAttentionText)
                        ]
                    )
                }

                HStack {
                    Spacer()
                    Button("Continue") { onContinue() }
                        .dsPalettePrimaryButton()
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.xxl)
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear { animateRings() }
        .onChange(of: animationSignature) { _ in animateRings() }
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

    private var ringsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            TripleRingsView(
                bcalProgress: animatedBcalProgress,
                accuracyProgress: animatedAccuracyProgress,
                attentionProgress: animatedAttentionProgress
            )
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Spacing.md)

            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                RingLegendItem(
                    iconName: "brain.head.profile",
                    color: .red,
                    title: "Brain Calories",
                    detail: "\(todayBCalTotal) / \(bcalGoal) BCal",
                    textColor: theme.onSurface,
                    secondaryColor: theme.onSurface.opacity(0.7)
                )

                RingLegendItem(
                    iconName: "dot.scope",
                    color: .blue,
                    title: "Clarity",
                    detail: "\(todayAccuracyPercentInt)% of \(goalAccuracyPercent)% clarity goal",
                    textColor: theme.onSurface,
                    secondaryColor: theme.onSurface.opacity(0.7)
                )

                RingLegendItem(
                    iconName: "bell.slash",
                    color: .green,
                    title: "Attention",
                    detail: todayAttentionSummary,
                    textColor: theme.onSurface,
                    secondaryColor: theme.onSurface.opacity(0.7)
                )
            }
        }
        .padding(DS.Spacing.xl)
        .brainCardBackground(theme: theme, cornerRadius: 32, fill: theme.surface)
    }

    private func metricCard(
        iconName: String,
        title: String,
        subtitle: String,
        valueText: String,
        goalText: String,
        progress: Double,
        progressDescription: String,
        color: Color,
        rows: [(label: String, value: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            HStack(alignment: .top, spacing: DS.Spacing.lg) {
                RingIconBadge(systemName: iconName, color: color)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(title)
                        .font(DS.Typography.headline)
                        .foregroundStyle(theme.onSurface)

                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(theme.onSurface.opacity(0.7))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                    Text(valueText)
                        .font(DS.Typography.title2)
                        .foregroundStyle(theme.onSurface)

                    Text(goalText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(theme.onSurface.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                MetricProgressBar(progress: progress, color: color, trackColor: theme.divider.opacity(0.4))

                Text(progressDescription)
                    .font(DS.Typography.caption)
                    .foregroundStyle(theme.onSurface.opacity(0.6))
            }

            VStack(spacing: DS.Spacing.sm) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack {
                        Text(row.label)
                            .font(DS.Typography.caption)
                            .foregroundStyle(theme.onSurface.opacity(0.6))
                        Spacer()
                        Text(row.value)
                            .font(DS.Typography.bodyBold)
                            .foregroundStyle(theme.onSurface)
                    }

                    if index != rows.count - 1 {
                        DSDivider()
                    }
                }
            }
        }
        .padding(DS.Spacing.xl)
        .brainCardBackground(theme: theme)
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

struct TripleRingsView: View {
    let bcalProgress: Double
    let accuracyProgress: Double
    let attentionProgress: Double

    private let outerSize: CGFloat = 210
    private let middleSize: CGFloat = 170
    private let innerSize: CGFloat = 130
    private let ringLineWidth: CGFloat = 26
    private let startAngle = Angle(degrees: -10) // start near 350° like Apple rings

    var body: some View {
        ZStack {
            ringView(progress: bcalProgress, color: .red, circleSize: outerSize, iconName: "brain.head.profile")
                .frame(width: outerSize, height: outerSize)

            ringView(progress: accuracyProgress, color: .blue, circleSize: middleSize, iconName: "dot.scope")
                .frame(width: middleSize, height: middleSize)

            ringView(progress: attentionProgress, color: .green, circleSize: innerSize, iconName: "bell.slash")
                .frame(width: innerSize, height: innerSize)
        }
        .frame(height: outerSize)
    }

    private func ringView(progress: Double, color: Color, circleSize: CGFloat, iconName: String) -> some View {
        MultiLoopRing(progress: progress, color: color, lineWidth: ringLineWidth, startAngle: startAngle)
            .overlay(alignment: .center) {
                RingGlyph(
                    systemName: iconName,
                    ringColor: color,
                    circleSize: circleSize,
                    lineWidth: ringLineWidth,
                    angle: .degrees(-90)
                )
            }
    }
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

private struct RingGlyph: View {
    let systemName: String
    let ringColor: Color
    let circleSize: CGFloat
    let lineWidth: CGFloat
    let angle: Angle

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.white)
            .shadow(color: ringColor.opacity(0.7), radius: 3, x: 0, y: 0)
            .offset(iconOffset)
    }

    private var iconOffset: CGSize {
        let radius = Double((circleSize / 2) - (lineWidth / 2) - 6)
        let radians = angle.radians
        let x = cos(radians) * radius
        let y = sin(radians) * radius
        return CGSize(width: CGFloat(x), height: CGFloat(y))
    }
}

private struct RingTipHighlight: View {
    let radius: CGFloat
    let lineWidth: CGFloat
    let color: Color
    let progress: Double
    let startAngle: Angle

    @ViewBuilder
    var body: some View {
        let loops = max(progress, 0)
        if loops > 0 {
            let fractional = loops - floor(loops)
            let tipFraction = fractional > 0 ? fractional : 1
            let tipAngle = startAngle.degrees + (tipFraction * 360)
            let radians = tipAngle * .pi / 180
            let offsetRadius = max(radius - (lineWidth / 2), 0)
            let offset = CGSize(
                width: CGFloat(cos(radians) * Double(offsetRadius)),
                height: CGFloat(sin(radians) * Double(offsetRadius))
            )

            Circle()
                .fill(color)
                .frame(width: lineWidth, height: lineWidth)
                .shadow(color: color.opacity(0.65), radius: 5, x: 0, y: 0)
                .offset(offset)
        }
    }
}

private struct MultiLoopRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let startAngle: Angle

    private var loops: Double { max(progress, 0) }
    private var fullLoops: Int { Int(loops) }
    private var remainder: Double { loops - Double(fullLoops) }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = diameter / 2
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: lineWidth)

                if fullLoops > 0 {
                    ForEach(0..<fullLoops, id: \.self) { index in
                        ringStroke(amount: 1)
                            .opacity(loopOpacity(for: index))
                    }
                }

                if remainder > 0 {
                    ringStroke(amount: remainder)
                }
            }
            .overlay(
                RingTipHighlight(
                    radius: radius,
                    lineWidth: lineWidth,
                    color: color,
                    progress: loops,
                    startAngle: startAngle
                )
            )
        }
    }

    private func ringStroke(amount: Double) -> some View {
        let gradient = AngularGradient(
            gradient: Gradient(colors: [color.opacity(0.8), color]),
            center: .center,
            startAngle: startAngle,
            endAngle: startAngle + .degrees(360)
        )

        return Circle()
            .trim(from: 0, to: min(amount, 1.0))
            .stroke(
                gradient,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(startAngle)
            .shadow(color: color.opacity(0.55), radius: 6, x: 0, y: 0)
    }

    private func loopOpacity(for index: Int) -> Double {
        let base: Double = 0.6
        return min(1.0, base + (Double(index) * 0.15))
    }
}

private struct RingLegendItem: View {
    let iconName: String
    let color: Color
    let title: String
    let detail: String
    let textColor: Color
    let secondaryColor: Color

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            RingIconBadge(systemName: iconName, color: color)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Typography.bodyEmphasized)
                    .foregroundStyle(textColor)

                Text(detail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(secondaryColor)
            }

            Spacer()
        }
    }
}

private struct MetricProgressBar: View {
    let progress: Double
    let color: Color
    let trackColor: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(trackColor)
                    .frame(height: 8)

                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(clampedProgress), height: 8)
            }
        }
        .frame(height: 8)
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

// MARK: - Accuracy Ring View

struct AccuracyRingView: View {
    let valuePercent: Double   // 0–100
    let goalPercent: Double    // e.g., 80

    var progress: Double { min(valuePercent / max(goalPercent, 1.0), 1.0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.Colors.tertiaryBackground, lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(round(min(valuePercent, 100))))%")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DS.Colors.black)
        }
    }
}
