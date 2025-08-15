import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // Background color
            DS.Colors.primaryBackground
                .ignoresSafeArea()
            
            // "deepread" text
            Text("deepread")
                .font(.system(size: 24, weight: .regular))
                .tracking(-0.72) // -3% letter spacing (24 * 0.03 = 0.72)
                .foregroundColor(DS.Colors.primaryText)
        }
    }
}

#Preview {
    SplashScreenView()
} 