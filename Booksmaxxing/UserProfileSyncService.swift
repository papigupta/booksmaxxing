import Foundation
import FirebaseFirestore

final class UserProfileSyncService {
    static let shared = UserProfileSyncService()

    private let db: Firestore
    private let queue = DispatchQueue(label: "com.booksmaxxing.userprofilesync", qos: .utility)

    init(database: Firestore = Firestore.firestore()) {
        self.db = database
    }

    func syncProfile(_ profile: UserProfile, userId: String) {
        guard !userId.isEmpty else { return }
        let payload = makePayload(from: profile, userId: userId)
        queue.async {
            self.db.collection("users").document(userId).setData(payload, merge: true) { error in
                if let error {
                    print("DEBUG: Failed to sync user profile to Firestore: \(error)")
                }
            }
        }
    }

    func markOnboardingStep(_ step: OnboardingStep, profile: UserProfile, userId: String) {
        guard profile.onboardingStep != step else { return }
        profile.onboardingStep = step
        profile.updatedAt = Date.now
        syncProfile(profile, userId: userId)
    }

    private func makePayload(from profile: UserProfile, userId: String) -> [String: Any] {
        var payload: [String: Any] = [
            "appleUserId": userId,
            "emailStatus": profile.emailStatus.rawValue,
            "shouldPromptForEmail": profile.shouldPromptForEmail,
            "onboardingStep": profile.onboardingStep.rawValue,
            "hasCompletedInitialBookSelection": profile.hasCompletedInitialBookSelection,
            "updatedAt": FieldValue.serverTimestamp(),
            "profileCreatedAt": Timestamp(date: profile.createdAt),
            "profileUpdatedAt": Timestamp(date: profile.updatedAt)
        ]

        if let email = profile.emailAddress, !email.isEmpty {
            payload["email"] = email
        }

        if let lastOpenedBookTitle = profile.lastOpenedBookTitle {
            payload["lastOpenedBookTitle"] = lastOpenedBookTitle
        }

        if let lastEmailUpdate = profile.lastEmailUpdate {
            payload["lastEmailUpdate"] = Timestamp(date: lastEmailUpdate)
        }

        return payload
    }
}
