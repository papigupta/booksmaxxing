import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        Image("appLogoMedium")
            .resizable()
            .scaledToFit()
            .frame(width: 64)
            .accessibilityLabel("Booksmaxxing")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            OnboardingBackground()
        }
    }
}

#Preview {
    SplashScreenView()
} 
