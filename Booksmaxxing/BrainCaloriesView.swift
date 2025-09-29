import SwiftUI

struct BrainCaloriesView: View {
    let sessionBCal: Int
    let todayTotal: Int
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
                        Text("\(todayTotal) BCal")
                            .font(DS.Typography.bodyBold)
                            .foregroundColor(DS.Colors.black)
                    }
                    .padding()
                    .background(DS.Colors.tertiaryBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, DS.Spacing.lg)

                Spacer()

                Button("Continue") { onContinue() }
                    .dsPrimaryButton()
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
            }
        }
        .onAppear { animate = true }
    }
}

#Preview {
    BrainCaloriesView(sessionBCal: 220, todayTotal: 420, onContinue: {})
}

