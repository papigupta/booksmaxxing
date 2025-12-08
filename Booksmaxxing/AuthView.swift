import SwiftUI
import AuthenticationServices
import SwiftData

struct AuthView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    var logoNamespace: Namespace.ID? = nil

    private let pageMargin: CGFloat = 60
    private let primaryColor = Color(hex: "262626")
    private let heroSize: CGFloat = 56
    private let subtitleSize: CGFloat = 20
    private let detailSize: CGFloat = 12
    private let heroLineSpacing: CGFloat = -18

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom

            VStack(spacing: 0) {
                onboardingLogo
                    .padding(.top, safeTop)

                Spacer()

                VStack(spacing: 20) {
                    heroCopy
                    subtitle
                    signInWithAppleButton
                    finePrint

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

                    if let message = authManager.authErrorMessage {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, safeBottom + 24)
            }
            .padding(.horizontal, pageMargin)
            .background {
                OnboardingBackground()
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            authManager.checkICloudAccountStatus()
        }
    }
}

private extension AuthView {
    @ViewBuilder
    var onboardingLogo: some View {
        let view = Image("appLogoMedium")
            .resizable()
            .scaledToFit()
            .frame(width: 52)
            .accessibilityLabel("Booksmaxxing")
        if let logoNamespace {
            view.matchedGeometryEffect(id: "onboardingLogo", in: logoNamespace)
        } else {
            view
        }
    }
}

private extension AuthView {
    var heroCopy: some View {
        VStack(spacing: heroLineSpacing) {
            Text("remember")
            Text("what you")
            Text("read")
        }
        .font(DS.Typography.frauncesItalic(size: heroSize, weight: .black))
        .tracking(heroSize * -0.04)
        .multilineTextAlignment(.center)
        .foregroundColor(primaryColor)
    }

    var subtitle: some View {
        Text("Sign in to save your progress")
            .font(DS.Typography.fraunces(size: subtitleSize, weight: .regular))
            .tracking(subtitleSize * -0.03)
            .multilineTextAlignment(.center)
            .foregroundColor(primaryColor)
    }

    var signInWithAppleButton: some View {
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
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(primaryColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .foregroundColor(.white)
        .font(DS.Typography.fraunces(size: subtitleSize, weight: .regular))
        .tracking(subtitleSize * -0.03)
    }

    var finePrint: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("By continuing, you agree to our")
                Button(action: { openURL(URL(string: "https://booksmaxxing.com/termsofservice")!) }) {
                    Text("Terms")
                        .underline()
                }
                .buttonStyle(.plain)
                Text("&")
                Button(action: { openURL(URL(string: "https://booksmaxxing.com/privacypolicy")!) }) {
                    Text("Privacy Policy")
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .font(DS.Typography.fraunces(size: detailSize, weight: .regular))
            .tracking(detailSize * -0.03)
            .foregroundColor(primaryColor)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Button(action: { authManager.startGuestSession() }) {
                Text("Explore Limited Preview")
                    .underline()
                    .font(DS.Typography.fraunces(size: detailSize, weight: .regular))
                    .tracking(detailSize * -0.03)
                    .foregroundColor(primaryColor)
            }
            .buttonStyle(.plain)
        }
        .multilineTextAlignment(.center)
    }
}

#if DEBUG
struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView(authManager: AuthManager())
    }
}
#endif
