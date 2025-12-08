import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        Image("onboardingBG")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
