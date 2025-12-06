import SwiftUI
import SwiftData
import Foundation

enum EmailCaptureResult {
    case submitted
    case skipped
}

struct EmailCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authManager: AuthManager
    @Bindable var profile: UserProfile

    @State private var email: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onFinish: (EmailCaptureResult) -> Void

    init(profile: UserProfile, onFinish: @escaping (EmailCaptureResult) -> Void) {
        self.profile = profile
        _email = State(initialValue: profile.emailAddress ?? "")
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Where should we send feedback invites?")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text("We’ll reach out occasionally to learn how Booksmaxxing can improve.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Email address", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            VStack(spacing: 12) {
                Button(action: submitEmail) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isContinueEnabled ? Color.accentColor : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isContinueEnabled)

                Button("Skip for now", action: skip)
                    .buttonStyle(.plain)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    private var isContinueEnabled: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private func submitEmail() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmed) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            profile.emailAddress = trimmed.lowercased()
            profile.emailStatus = .provided
            profile.lastEmailUpdate = Date.now
            profile.shouldPromptForEmail = false
            profile.updatedAt = Date.now

            do {
                try modelContext.save()
                if let userId = authManager.userIdentifier, !authManager.isGuestSession {
                    UserProfileSyncService.shared.syncProfile(profile, userId: userId)
                }
                AnalyticsManager.shared.track(.emailSubmitted(method: .manual))
                authManager.pendingAppleEmail = nil
                onFinish(.submitted)
            } catch {
                errorMessage = "Couldn't save your email. Please try again."
                print("DEBUG: Failed to save email: \(error)")
            }
            isSaving = false
        }
    }

    private func skip() {
        guard !isSaving else { return }
        Task { @MainActor in
            profile.emailStatus = .skipped
            profile.shouldPromptForEmail = false
            profile.updatedAt = Date.now
            do {
                try modelContext.save()
                if let userId = authManager.userIdentifier, !authManager.isGuestSession {
                    UserProfileSyncService.shared.syncProfile(profile, userId: userId)
                }
                AnalyticsManager.shared.track(.emailSkipped)
                authManager.pendingAppleEmail = nil
                onFinish(.skipped)
            } catch {
                print("DEBUG: Failed to mark email skip: \(error)")
                errorMessage = "Couldn't skip right now. Please try again."
            }
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let detectorType: NSTextCheckingResult.CheckingType = .link
        guard let detector = try? NSDataDetector(types: detectorType.rawValue) else { return false }
        let range = NSRange(location: 0, length: value.utf16.count)
        let matches = detector.matches(in: value, options: [], range: range)
        return matches.contains { result in
            guard result.resultType == .link, let url = result.url else { return false }
            return url.absoluteString.hasPrefix("mailto:") && result.range.length == range.length
        }
    }
}
