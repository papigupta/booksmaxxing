import Foundation
import AuthenticationServices
import Combine
import CloudKit

final class AuthManager: NSObject, ObservableObject {
    @Published private(set) var userIdentifier: String?
    @Published private(set) var isSignedIn: Bool = false
    @Published var iCloudAccountAvailable: Bool = true
    @Published var authErrorMessage: String?

    private let userIdKey = "appleUserId"

    override init() {
        super.init()
        self.userIdentifier = KeychainHelper.shared.get(userIdKey)
        self.isSignedIn = (self.userIdentifier != nil)
        startAccountStatusMonitoring()
    }

    func signOut() {
        KeychainHelper.shared.delete(userIdKey)
        userIdentifier = nil
        isSignedIn = false
    }

    func handleAuthorization(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                let userID = credential.user
                KeychainHelper.shared.set(userID, forKey: userIdKey)
                DispatchQueue.main.async {
                    self.userIdentifier = userID
                    self.isSignedIn = true
                    self.authErrorMessage = nil
                }
            } else {
                DispatchQueue.main.async { self.authErrorMessage = "Invalid Apple credential." }
            }
        case .failure(let error):
            DispatchQueue.main.async { self.authErrorMessage = error.localizedDescription }
        }
    }

    func checkICloudAccountStatus() {
        let container = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        container.accountStatus { status, _ in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self.iCloudAccountAvailable = true
                case .couldNotDetermine, .temporarilyUnavailable:
                    // Treat transient states as available to avoid false negatives on launch
                    self.iCloudAccountAvailable = true
                default:
                    // Fall back to default container in case the specific container hasn’t finished provisioning
                    CKContainer.default().accountStatus { fallback, _ in
                        DispatchQueue.main.async {
                            switch fallback {
                            case .available, .couldNotDetermine, .temporarilyUnavailable:
                                self.iCloudAccountAvailable = true
                            default:
                                self.iCloudAccountAvailable = false
                            }
                        }
                    }
                }
            }
        }
    }

    private func startAccountStatusMonitoring() {
        // Initial check
        checkICloudAccountStatus()
        // React to iCloud account changes
        NotificationCenter.default.addObserver(
            forName: Notification.Name.CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkICloudAccountStatus()
        }
        // Re-check on foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkICloudAccountStatus()
        }
    }
}

