import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // Background color (you can customize this)
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // "deepread" text
            Text("deepread")
                .font(.system(size: 24, weight: .regular))
                .tracking(-0.72) // -3% letter spacing (24 * 0.03 = 0.72)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    SplashScreenView()
} 