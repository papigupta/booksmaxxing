import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // App background color - light grey
            DS.Colors.appBackground
                .ignoresSafeArea()
            
            // Tagline and app name
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Books don't owe")
                        .font(DS.Typography.fraunces(size: 24, weight: .light))
                        .tracking(DS.Typography.tightTracking(for: 24))
                        .foregroundColor(DS.Colors.primaryText)
                    
                    Text("you knowledge,")
                        .font(DS.Typography.fraunces(size: 24, weight: .light))
                        .tracking(DS.Typography.tightTracking(for: 24))
                        .foregroundColor(DS.Colors.primaryText)
                    
                    Text("You owe them work.")
                        .font(DS.Typography.fraunces(size: 24, weight: .light))
                        .tracking(DS.Typography.tightTracking(for: 24))
                        .foregroundColor(DS.Colors.primaryText)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Put in the work with")
                        .font(DS.Typography.fraunces(size: 24, weight: .light))
                        .tracking(DS.Typography.tightTracking(for: 24))
                        .foregroundColor(DS.Colors.primaryText)
                    
                    Text("Booksmaxxing.")
                        .font(.custom("Fraunces", size: 24).bold().italic())
                        .tracking(DS.Typography.tightTracking(for: 24))
                        .foregroundColor(DS.Colors.primaryText)
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
} 