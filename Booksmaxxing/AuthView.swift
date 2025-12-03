import SwiftUI
import AuthenticationServices
import SwiftData

struct AuthView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                welcomeTitle
                    .multilineTextAlignment(.center)
                    .tracking(DS.Typography.tightTracking(for: welcomeTitleSize))
                Text("Sign in to sync with iCloud")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                // Attempt to capture name from Apple for first-time sign-in
                if case .success(let auth) = result, let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                    if let nameComponents = credential.fullName {
                        let formatter = PersonNameComponentsFormatter()
                        let composedName = formatter.string(from: nameComponents).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !composedName.isEmpty {
                            DispatchQueue.main.async {
                                do {
                                    let existing = try modelContext.fetch(FetchDescriptor<UserProfile>())
                                    let profile: UserProfile
                                    if let first = existing.first {
                                        profile = first
                                    } else {
                                        profile = UserProfile()
                                        modelContext.insert(profile)
                                    }
                                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        profile.name = composedName
                                        profile.updatedAt = Date.now
                                    }
                                } catch {
                                    // Swallow errors for minimal launch; name can be edited later
                                    print("DEBUG: Failed to prefill profile name: \(error)")
                                }
                            }
                        }
                    }
                }
                authManager.handleAuthorization(result: result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .padding(.horizontal)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("By continuing, you agree to our")
                        .foregroundStyle(.secondary)
                    Button(action: { openURL(URL(string: "https://booksmaxxing.com/termsofservice")!) }) {
                        Text("Terms")
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Text("&")
                        .foregroundStyle(.secondary)
                    Button(action: { openURL(URL(string: "https://booksmaxxing.com/privacypolicy")!) }) {
                        Text("Privacy Policy")
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button(action: { authManager.startGuestSession() }) {
                    Text("Explore Limited Preview")
                        .underline()
                }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.footnote)

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

private extension AuthView {
    var welcomeTitle: Text {
        Text("Welcome to\n")
            .font(DS.Typography.fraunces(size: welcomeTitleSize, weight: .light))
        + Text("Booksmaxxing")
            .font(DS.Typography.fraunces(size: welcomeTitleSize, weight: .black))
    }

    var welcomeTitleSize: CGFloat { 34 }
}

#if DEBUG
struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView(authManager: AuthManager())
    }
}
#endif
