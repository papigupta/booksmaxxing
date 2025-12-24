import Foundation
import SwiftData

enum EmailStatus: String, Codable, CaseIterable {
    case unknown
    case provided
    case skipped
    case error
}

enum OnboardingStep: String, Codable, CaseIterable {
    case unknown
    case splash
    case authentication
    case emailCapture
    case bookSelection
    case dailyPractice
}

@Model
final class UserProfile {
    // Provide default values at declaration for CloudKit compatibility
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var starterLibraryVersion: Int = 0
    var hasCompletedInitialBookSelection: Bool = false
    var lastOpenedBookTitle: String?
    var emailAddress: String?
    var emailStatusRaw: String = EmailStatus.unknown.rawValue
    var lastEmailUpdate: Date?
    var shouldPromptForEmail: Bool = false
    var onboardingStepRaw: String = OnboardingStep.unknown.rawValue

    init(
        id: UUID = UUID(),
        name: String = "",
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        starterLibraryVersion: Int = 0,
        hasCompletedInitialBookSelection: Bool = false,
        lastOpenedBookTitle: String? = nil,
        emailAddress: String? = nil,
        emailStatusRaw: String = EmailStatus.unknown.rawValue,
        lastEmailUpdate: Date? = nil,
        shouldPromptForEmail: Bool = false,
        onboardingStepRaw: String = OnboardingStep.unknown.rawValue
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.starterLibraryVersion = starterLibraryVersion
        self.hasCompletedInitialBookSelection = hasCompletedInitialBookSelection
        self.lastOpenedBookTitle = lastOpenedBookTitle
        self.emailAddress = emailAddress
        self.emailStatusRaw = emailStatusRaw
        self.lastEmailUpdate = lastEmailUpdate
        self.shouldPromptForEmail = shouldPromptForEmail
        self.onboardingStepRaw = onboardingStepRaw
    }

    var emailStatus: EmailStatus {
        get { EmailStatus(rawValue: emailStatusRaw) ?? .unknown }
        set { emailStatusRaw = newValue.rawValue }
    }

    var onboardingStep: OnboardingStep {
        get { OnboardingStep(rawValue: onboardingStepRaw) ?? .unknown }
        set { onboardingStepRaw = newValue.rawValue }
    }

    var hasProvidedEmail: Bool {
        guard emailStatus == .provided else { return false }
        return !(emailAddress?.isEmpty ?? true)
    }
}
