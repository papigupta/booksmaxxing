import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // App background color - light grey
            DS.Colors.appBackground
                .ignoresSafeArea()
            
            // "deepread" text
            Text("deepread")
                .font(DS.Typography.fraunces(size: 32, weight: .medium))
                .tracking(DS.Typography.tightTracking(for: 32)) // Using tighter -3% for title
                .foregroundColor(DS.Colors.primaryText)
        }
    }
}

#Preview {
    SplashScreenView()
} 