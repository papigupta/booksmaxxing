import SwiftUI
import SwiftData

struct OnboardingView: View {
    let openAIService: OpenAIService

    var body: some View {
        // The onboarding experience now mirrors BookSelectionView entirely.
        BookSelectionView(openAIService: openAIService)
    }
}

