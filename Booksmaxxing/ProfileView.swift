import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navigationState: NavigationState
    @Query private var profiles: [UserProfile]
    @State private var currentProfile: UserProfile?
    @State private var emailDraft: String = ""
    @State private var emailErrorMessage: String?
    @State private var emailInfoMessage: String?
#if DEBUG
    @State private var showAnalyticsDashboard = false
#endif

    let authManager: AuthManager

    var body: some View {
        NavigationStack {
            Form {
                if let profile = currentProfile {
                    Section(header: Text("Profile")) {
                        TextField("Name", text: Binding(
                            get: { profile.name },
                            set: { newValue in
                                profile.name = newValue
                                profile.updatedAt = Date.now
                            }
                        ))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                    }

                    Section(header: Text("Feedback Email")) {
                        TextField("Email", text: $emailDraft)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        if let emailInfoMessage {
                            Text(emailInfoMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let emailErrorMessage {
                            Text(emailErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Button("Save email", action: saveEmail)
                            .disabled(!hasEmailChanges(profile: profile))
                    }
                }

                Section(header: Text("Legal")) {
                    Link("Terms of Service", destination: URL(string: "https://booksmaxxing.com/termsofservice")!)
                    Link("Privacy Policy", destination: URL(string: "https://booksmaxxing.com/privacypolicy")!)
                }

                if DebugFlags.enableDevControls, let profile = currentProfile {
                    Section(header: Text("Developer Tools")) {
                        Button("Force email capture prompt") {
                            forceEmailCapturePrompt(for: profile)
                        }
                        Button("Reset onboarding flow") {
                            resetOnboardingFlow(for: profile)
                        }
                    }
                }
#if DEBUG
                Section(header: Text("Analytics (Debug)")) {
                    Button("Open Analytics Dashboard") {
                        showAnalyticsDashboard = true
                    }
                }
#endif
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if let existing = profiles.first {
                currentProfile = existing
                emailDraft = existing.emailAddress ?? ""
            } else {
                let created = UserProfile()
                modelContext.insert(created)
                currentProfile = created
                emailDraft = ""
            }
        }
#if DEBUG
        .sheet(isPresented: $showAnalyticsDashboard) {
            AdminAnalyticsDashboardView()
        }
#endif
    }
}

private extension ProfileView {
    func hasEmailChanges(profile: UserProfile) -> Bool {
        let stored = profile.emailAddress ?? ""
        return stored.caseInsensitiveCompare(emailDraft) != .orderedSame
    }

    func saveEmail() {
        guard let profile = currentProfile else { return }
        let trimmed = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        emailErrorMessage = nil
        emailInfoMessage = nil

        if !trimmed.isEmpty && !isValidEmail(trimmed) {
            emailErrorMessage = "That doesn't look like a valid email."
            return
        }

        if trimmed.isEmpty {
            profile.emailAddress = nil
            profile.emailStatus = .unknown
            profile.lastEmailUpdate = nil
        } else {
            profile.emailAddress = trimmed.lowercased()
            profile.emailStatus = .provided
            profile.lastEmailUpdate = Date.now
            profile.shouldPromptForEmail = false
        }
        profile.updatedAt = Date.now

        do {
            try modelContext.save()
            if let userId = authManager.userIdentifier, !authManager.isGuestSession {
                UserProfileSyncService.shared.syncProfile(profile, userId: userId)
            }
            UserAnalyticsService.shared.markEmail(status: profile.emailStatus, hasEmail: profile.hasProvidedEmail)
            if trimmed.isEmpty {
                emailInfoMessage = "Email removed."
            } else {
                AnalyticsManager.shared.track(.emailSubmitted(method: .manual))
                emailInfoMessage = "Email saved."
            }
        } catch {
            emailErrorMessage = "Couldn't save right now."
            print("DEBUG: Failed to save email from ProfileView: \(error)")
        }
    }

    func isValidEmail(_ value: String) -> Bool {
        let detectorType: NSTextCheckingResult.CheckingType = .link
        guard let detector = try? NSDataDetector(types: detectorType.rawValue) else { return false }
        let range = NSRange(location: 0, length: value.utf16.count)
        let matches = detector.matches(in: value, options: [], range: range)
        return matches.contains { result in
            guard result.resultType == .link, let url = result.url else { return false }
            return url.absoluteString.hasPrefix("mailto:") && result.range.length == range.length
        }
    }

    func forceEmailCapturePrompt(for profile: UserProfile) {
        emailErrorMessage = nil
        emailInfoMessage = nil
        profile.emailAddress = nil
        profile.emailStatus = .unknown
        profile.lastEmailUpdate = nil
        profile.shouldPromptForEmail = true
        profile.onboardingStep = .emailCapture
        profile.updatedAt = Date.now
        persistProfileChange(profile: profile, successMessage: "Email capture step will appear again.")
    }

    func resetOnboardingFlow(for profile: UserProfile) {
        emailErrorMessage = nil
        emailInfoMessage = nil
        profile.hasCompletedInitialBookSelection = false
        profile.lastOpenedBookTitle = nil
        profile.onboardingStep = .bookSelection
        profile.updatedAt = Date.now
        persistProfileChange(profile: profile, successMessage: "Book selection will reopen.")
        navigationState.navigateToBookSelection()
    }

    func persistProfileChange(profile: UserProfile, successMessage: String) {
        do {
            try modelContext.save()
            if let userId = authManager.userIdentifier, !authManager.isGuestSession {
                UserProfileSyncService.shared.syncProfile(profile, userId: userId)
            }
            emailInfoMessage = successMessage
        } catch {
            emailErrorMessage = "Couldn't save right now."
            print("DEBUG: Failed to persist profile tweak: \(error)")
        }
    }
}

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(authManager: AuthManager())
            .environmentObject(NavigationState())
    }
}
#endif
