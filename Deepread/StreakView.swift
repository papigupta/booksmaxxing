import SwiftUI

struct StreakView: View {
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var streakManager: StreakManager
    
    // Static bonus data (can be wired later)
    private let xpGained = 50
    private let achievement = "Quick Learner"
    
    @State private var animateStreak = false
    @State private var animateXP = false
    @State private var animateAchievement = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.1),
                    Color.yellow.opacity(0.1),
                    DS.Colors.primaryBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: DS.Spacing.xl) {
                Spacer()
                
                // Celebration animation area
                VStack(spacing: DS.Spacing.lg) {
                    // Streak fire icon with animation
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .scaleEffect(animateStreak ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animateStreak)
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                            .rotationEffect(.degrees(animateStreak ? 5 : -5))
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animateStreak)
                    }
                    
                    // Streak count
                    VStack(spacing: DS.Spacing.xs) {
                        Text("\(streakManager.currentStreak) Day Streak!")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(DS.Colors.black)
                            .scaleEffect(animateStreak ? 1.0 : 0.8)
                            .animation(.bouncy(duration: 0.6).delay(0.2), value: animateStreak)
                        
                        Text("You're on fire!")
                            .font(DS.Typography.headline)
                            .foregroundColor(DS.Colors.secondaryText)
                            .opacity(animateStreak ? 1.0 : 0.0)
                            .animation(.easeIn(duration: 0.5).delay(0.4), value: animateStreak)
                    }
                }
                
                // Stats section
                VStack(spacing: DS.Spacing.md) {
                    // XP Gained
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)
                            .rotationEffect(.degrees(animateXP ? 360 : 0))
                            .animation(.easeInOut(duration: 1.0).delay(0.6), value: animateXP)
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("+\(xpGained) XP")
                                .font(DS.Typography.headline)
                                .foregroundColor(DS.Colors.black)
                            Text("Experience Points")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.secondaryText)
                        }
                        
                        Spacer()
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Colors.secondaryBackground)
                    .cornerRadius(12)
                    .scaleEffect(animateXP ? 1.0 : 0.9)
                    .opacity(animateXP ? 1.0 : 0.0)
                    .animation(.bouncy(duration: 0.5).delay(0.8), value: animateXP)
                    
                    // Achievement
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color.orange)
                            .scaleEffect(animateAchievement ? 1.2 : 1.0)
                            .animation(.bouncy(duration: 0.6).delay(1.0), value: animateAchievement)
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("Achievement Unlocked!")
                                .font(DS.Typography.caption)
                                .foregroundColor(DS.Colors.secondaryText)
                            Text(achievement)
                                .font(DS.Typography.bodyBold)
                                .foregroundColor(DS.Colors.black)
                        }
                        
                        Spacer()
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Colors.tertiaryBackground)
                    .cornerRadius(12)
                    .scaleEffect(animateAchievement ? 1.0 : 0.9)
                    .opacity(animateAchievement ? 1.0 : 0.0)
                    .animation(.bouncy(duration: 0.5).delay(1.2), value: animateAchievement)
                }
                .padding(.horizontal, DS.Spacing.lg)
                
                Spacer()
                
                // Continue button
                Button("Continue") {
                    onContinue()
                }
                .dsPrimaryButton()
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xl)
                .opacity(animateAchievement ? 1.0 : 0.5)
                .disabled(!animateAchievement)
                .animation(.easeIn(duration: 0.3).delay(1.5), value: animateAchievement)
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        withAnimation {
            animateStreak = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation {
                animateXP = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                animateAchievement = true
            }
        }
    }
}

#Preview {
    StreakView(onContinue: {})
}
