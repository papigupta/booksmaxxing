import SwiftUI

struct SplashScreenView: View {
    var logoNamespace: Namespace.ID? = nil

    var body: some View {
        logo
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                OnboardingBackground()
            }
    }
    
    @ViewBuilder
    private var logo: some View {
        let view = Image("appLogoMedium")
            .resizable()
            .scaledToFit()
            .frame(width: 64)
            .accessibilityLabel("Booksmaxxing")
        if let logoNamespace {
            view.matchedGeometryEffect(id: "onboardingLogo", in: logoNamespace)
        } else {
            view
        }
    }
}

#Preview {
    SplashScreenView()
} 
