import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Welcome to Deepread")
                    .font(.largeTitle).bold()
                Text("Sign in to sync with iCloud")
                    .foregroundStyle(.secondary)
            }

            if !authManager.iCloudAccountAvailable {
                VStack(spacing: 8) {
                    Text("iCloud is not available")
                        .font(.headline)
                    Text("Please sign into iCloud in Settings to enable syncing.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                authManager.handleAuthorization(result: result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .padding(.horizontal)

            if let message = authManager.authErrorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            authManager.checkICloudAccountStatus()
        }
    }
}

#if DEBUG
struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView(authManager: AuthManager())
    }
}
#endif

