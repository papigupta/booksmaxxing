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
    @State private var heroVisible = false
    @State private var emailSectionVisible = false
    @State private var finePrintVisible = false

    private let pageMargin: CGFloat = 60
    private let primaryColor = Color(hex: "262626")
    private let heroSize: CGFloat = 56
    private let subtitleSize: CGFloat = 20
    private let detailSize: CGFloat = 12
    private let finePrintSize: CGFloat = 14
    private let heroLineSpacing: CGFloat = -18

    let onFinish: (EmailCaptureResult) -> Void

    init(profile: UserProfile, onFinish: @escaping (EmailCaptureResult) -> Void) {
        self.profile = profile
        _email = State(initialValue: profile.emailAddress ?? "")
        self.onFinish = onFinish
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    completionIcon
                        .padding(.top, safeTop)

                    Spacer()

                    VStack(spacing: 28) {
                        heroCopy
                            .opacity(heroVisible ? 1 : 0)
                            .scaleEffect(heroVisible ? 1 : 0.8)

                        VStack(spacing: 0) {
                            emailSection
                                .opacity(emailSectionVisible ? 1 : 0)
                                .scaleEffect(emailSectionVisible ? 1 : 0.86)

                            Group {
                                if showCTA {
                                    continueButton
                                        .disabled(!isContinueEnabled)
                                        .padding(.top, 12)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                } else {
                                    finePrint
                                        .padding(.top, 28)
                                        .opacity(finePrintVisible ? 1 : 0)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .padding(.bottom, safeBottom + 24)
                }
                .padding(.horizontal, pageMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                OnboardingBackground()
                    .ignoresSafeArea()
            }
        }
        .onAppear(perform: startPresentation)
        .onChange(of: email) { _ in
            if errorMessage != nil {
                errorMessage = nil
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showCTA)
    }

    private var isContinueEnabled: Bool {
        !isSaving && isValidEmail(trimmedEmail)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showCTA: Bool {
        !trimmedEmail.isEmpty
    }

    private var completionIcon: some View {
        ZStack {
            Circle()
                .fill(primaryColor)
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }

    private var heroCopy: some View {
        VStack(spacing: heroLineSpacing) {
            Text("you're")
            Text("all set!")
        }
        .font(DS.Typography.frauncesItalic(size: heroSize, weight: .black))
        .tracking(heroSize * -0.04)
        .multilineTextAlignment(.center)
        .foregroundColor(primaryColor)
    }

    private var emailSection: some View {
        VStack(spacing: 20) {
            Text("Do you want to share your email?")
                .font(DS.Typography.fraunces(size: subtitleSize, weight: .regular))
                .tracking(subtitleSize * -0.03)
                .multilineTextAlignment(.center)
                .foregroundColor(primaryColor)

            emailInput
        }
    }

    private var emailInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textContentType(.emailAddress)
                .disabled(isSaving)
                .font(DS.Typography.fraunces(size: subtitleSize, weight: .regular))
                .foregroundColor(primaryColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(primaryColor.opacity(0.15), lineWidth: 1)
                )

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typography.fraunces(size: detailSize, weight: .regular))
                    .foregroundColor(.red)
            }
        }
    }

    private var continueButton: some View {
        Button(action: submitEmail) {
            Text("Continue")
                .font(DS.Typography.fraunces(size: subtitleSize, weight: .regular))
                .tracking(subtitleSize * -0.03)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(primaryColor.opacity(isContinueEnabled ? 1 : 0.35))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var finePrint: some View {
        VStack(spacing: 8) {
            Text("We are in testing phase, and the only way to reach out to you for feedback is through email.")
                .font(DS.Typography.fraunces(size: finePrintSize, weight: .regular))
                .tracking(finePrintSize * -0.03)
                .foregroundColor(primaryColor)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: skip) {
                Text("Skip")
                    .underline()
                    .font(DS.Typography.fraunces(size: finePrintSize, weight: .bold))
                    .tracking(finePrintSize * -0.03)
                    .foregroundColor(primaryColor)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .multilineTextAlignment(.center)
    }

    private func startPresentation() {
        heroVisible = false
        emailSectionVisible = false
        finePrintVisible = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interpolatingSpring(stiffness: 140, damping: 14)) {
                heroVisible = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.25)) {
                emailSectionVisible = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeOut(duration: 0.25)) {
                finePrintVisible = true
            }
        }
    }

    private func submitEmail() {
        let trimmed = trimmedEmail
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
                notifyEmailSaved()
                onFinish(.submitted)
            } catch {
                errorMessage = "Couldn't save your email. Please try again."
                print("DEBUG: Failed to save email: \(error)")
            }
            isSaving = false
        }
    }

    private func notifyEmailSaved() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
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
