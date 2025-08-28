import SwiftUI

struct TestLoadingView: View {
    @Binding var message: String
    @State private var isAnimating = false
    @State private var dotCount = 0
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: DS.Spacing.xxl) {
                Spacer()
                
                // Loading animation
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(DS.Colors.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    // Animated ring
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [DS.Colors.white, DS.Colors.white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                    
                    // Center icon
                    DSIcon("brain", size: 32)
                        .foregroundStyle(DS.Colors.white)
                        .scaleEffect(isAnimating ? 1.1 : 0.9)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                }
                
                // Loading message
                VStack(spacing: DS.Spacing.sm) {
                    Text(message)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.white)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.3), value: message)
                    
                    // Animated dots
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(DS.Colors.white)
                                .frame(width: 6, height: 6)
                                .opacity(dotCount > index ? 1 : 0.3)
                                .animation(
                                    Animation.easeInOut(duration: 0.3)
                                        .delay(Double(index) * 0.1),
                                    value: dotCount
                                )
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
                
                // Progress indicators
                VStack(spacing: DS.Spacing.md) {
                    ProgressStep(icon: "1.circle.fill", text: "Easy questions", isActive: message.contains("easy"))
                    ProgressStep(icon: "2.circle.fill", text: "Medium questions", isActive: message.contains("medium"))
                    ProgressStep(icon: "3.circle.fill", text: "Hard questions", isActive: message.contains("hard") || message.contains("Finalizing"))
                }
                .padding(.horizontal, DS.Spacing.xxl)
                
                Spacer()
                
                // Tips section
                VStack(spacing: DS.Spacing.xs) {
                    Text("Quick Tip")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(DS.Colors.white.opacity(0.7))
                    
                    Text(getRandomTip())
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xl)
                }
                .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .onAppear {
            isAnimating = true
            startDotAnimation()
        }
    }
    
    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation {
                dotCount = (dotCount + 1) % 4
            }
        }
    }
    
    private func getRandomTip() -> String {
        let tips = [
            "Each question is tailored to your learning level",
            "You'll get immediate feedback after each answer",
            "Wrong answers can be retried immediately",
            "Complete all questions correctly to achieve mastery",
            "Questions progress from easy to hard difficulty"
        ]
        return tips.randomElement() ?? tips[0]
    }
}

struct ProgressStep: View {
    let icon: String
    let text: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isActive ? DS.Colors.white : DS.Colors.white.opacity(0.3))
                .frame(width: 24)
            
            Text(text)
                .font(DS.Typography.caption)
                .foregroundStyle(isActive ? DS.Colors.white : DS.Colors.white.opacity(0.3))
            
            Spacer()
            
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isActive)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var message = "Creating questions based on Atomic Habits..."
    return TestLoadingView(message: $message)
}