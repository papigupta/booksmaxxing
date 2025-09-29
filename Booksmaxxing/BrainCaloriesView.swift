import SwiftUI

struct BrainCaloriesView: View {
    // BCal
    let sessionBCal: Int
    let todayBCalTotal: Int
    // Accuracy
    let sessionCorrect: Int
    let sessionTotal: Int
    let todayCorrect: Int
    let todayTotal: Int
    let goalAccuracyPercent: Int
    let onContinue: () -> Void

    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.pink.opacity(0.12),
                    Color.red.opacity(0.08),
                    DS.Colors.primaryBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: DS.Spacing.xl) {
                Spacer()

                VStack(spacing: DS.Spacing.md) {
                    Text("Brain Calories")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.Colors.secondaryText)

                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.25), lineWidth: 16)
                            .frame(width: 180, height: 180)
                            .scaleEffect(animate ? 1.02 : 0.98)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animate)
                        Text("\(sessionBCal)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(DS.Colors.black)
                    }

                    Text("How much mental strain you burned")
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)
                }

                VStack(spacing: DS.Spacing.sm) {
                    HStack {
                        Text("This session")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                        Spacer()
                        Text("\(sessionBCal) BCal")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(DS.Colors.black)
                    }
                    .padding()
                    .background(DS.Colors.secondaryBackground)
                    .cornerRadius(12)

                    HStack {
                        Text("Today total")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                        Spacer()
                        Text("\(todayBCalTotal) BCal")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(DS.Colors.black)
                    }
                    .padding()
                    .background(DS.Colors.tertiaryBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, DS.Spacing.lg)

                // Accuracy Section
                VStack(spacing: DS.Spacing.md) {
                    Text("Accuracy")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.Colors.secondaryText)

                    AccuracyRingView(
                        valuePercent: todayAccuracyPercentRaw,
                        goalPercent: Double(goalAccuracyPercent)
                    )
                    .frame(width: 160, height: 160)

                    Text("Goal: \(goalAccuracyPercent)%")
                        .font(DS.Typography.caption)
                        .foregroundColor(DS.Colors.secondaryText)

                    VStack(spacing: DS.Spacing.sm) {
                        HStack {
                            Text("This session")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.secondaryText)
                            Spacer()
                            Text("\(sessionCorrect)/\(sessionTotal) correct")
                                .font(DS.Typography.bodyBold)
                                .foregroundColor(DS.Colors.black)
                        }
                        .padding()
                        .background(DS.Colors.secondaryBackground)
                        .cornerRadius(12)

                        HStack {
                            Text("Today")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.secondaryText)
                            Spacer()
                            Text("\(todayCorrect)/\(todayTotal) correct • \(todayAccuracyPercentInt)%")
                                .font(DS.Typography.bodyBold)
                                .foregroundColor(DS.Colors.black)
                        }
                        .padding()
                        .background(DS.Colors.tertiaryBackground)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }

                Spacer()

                Button("Continue") { onContinue() }
                    .dsPrimaryButton()
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
            }
        }
        .onAppear { animate = true }
    }

    private var todayAccuracyPercentRaw: Double {
        guard todayTotal > 0 else { return 0 }
        return (Double(todayCorrect) / Double(todayTotal)) * 100.0
    }
    private var todayAccuracyPercentInt: Int {
        Int(round(min(todayAccuracyPercentRaw, 100)))
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
        onContinue: {}
    )
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
