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
    // Attention
    let sessionPauses: Int
    let todayPauses: Int
    let todayAttentionPercent: Int
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

            ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                

                VStack(spacing: DS.Spacing.md) {
                    Text("Today’s Rings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.Colors.secondaryText)

                    TripleRingsView(
                        bcalProgress: min(Double(todayBCalTotal) / 200.0, 1.0),
                        accuracyProgress: min(todayAccuracyPercentRaw / Double(goalAccuracyPercent), 1.0),
                        attentionProgress: Double(todayAttentionPercent) / 100.0,
                        centerText: "\(sessionBCal)"
                    )
                    .frame(width: 220, height: 220)

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
                            .foregroundColor(.red)
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
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(DS.Colors.tertiaryBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, DS.Spacing.lg)

                // Accuracy (no ring)
                VStack(spacing: DS.Spacing.sm) {
                    HStack {
                        Text("Accuracy (session)")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                        Spacer()
                        Text("\(sessionCorrect)/\(sessionTotal) correct")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(DS.Colors.secondaryBackground)
                    .cornerRadius(12)

                    HStack {
                        Text("Accuracy (today)")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                        Spacer()
                        Text("\(todayCorrect)/\(todayTotal) • \(todayAccuracyPercentInt)%")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(DS.Colors.tertiaryBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, DS.Spacing.lg)

                // Attention (no ring)
                VStack(spacing: DS.Spacing.sm) {
                    HStack {
                        Text("Attention (session)")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                        Spacer()
                        Text("\(sessionPauses) distraction\(sessionPauses == 1 ? "" : "s")")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(DS.Colors.secondaryBackground)
                    .cornerRadius(12)

                    HStack {
                        Text("Attention (today)")
                            .font(DS.Typography.caption)
                            .foregroundColor(DS.Colors.secondaryText)
                        Spacer()
                        Text("\(todayPauses) distraction\(todayPauses == 1 ? "" : "s") • \(todayAttentionPercent)%")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(DS.Colors.tertiaryBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, DS.Spacing.lg)

                Button("Continue") { onContinue() }
                    .dsPrimaryButton()
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
            }
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

// MARK: - Triple Rings View

struct TripleRingsView: View {
    let bcalProgress: Double   // 0..1
    let accuracyProgress: Double
    let attentionProgress: Double
    let centerText: String

    var body: some View {
        ZStack {
            ring(progress: bcalProgress, color: .red, lineWidth: 18)
                .frame(width: 220, height: 220)
            ring(progress: accuracyProgress, color: .blue, lineWidth: 14)
                .frame(width: 180, height: 180)
            ring(progress: attentionProgress, color: .green, lineWidth: 10)
                .frame(width: 140, height: 140)
            Text(centerText)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(DS.Colors.black)
        }
    }

    private func ring(progress: Double, color: Color, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
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
