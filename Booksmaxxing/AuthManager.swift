import Foundation
import AuthenticationServices
import Combine
import CloudKit

final class AuthManager: NSObject, ObservableObject {
    @Published private(set) var userIdentifier: String?
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var isGuestSession: Bool = false
    @Published var iCloudAccountAvailable: Bool = true
    @Published var authErrorMessage: String?
    @Published var pendingAppleEmail: String?

    private let userIdKey = "appleUserId"
    private let guestSessionKey = "guestSessionActive"
    private let defaults: UserDefaults

    override init() {
        self.defaults = .standard
        super.init()
        self.userIdentifier = KeychainHelper.shared.get(userIdKey)
        let storedGuestSession = defaults.bool(forKey: guestSessionKey)
        self.isGuestSession = storedGuestSession
        self.isSignedIn = (self.userIdentifier != nil) || storedGuestSession
        startAccountStatusMonitoring()
    }

    func signOut() {
        KeychainHelper.shared.delete(userIdKey)
        defaults.set(false, forKey: guestSessionKey)
        userIdentifier = nil
        isSignedIn = false
        isGuestSession = false
        authErrorMessage = nil
        pendingAppleEmail = nil
    }

    func handleAuthorization(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                let userID = credential.user
                let appleEmail = credential.email
                KeychainHelper.shared.set(userID, forKey: userIdKey)
                defaults.set(false, forKey: guestSessionKey)
                DispatchQueue.main.async {
                    self.userIdentifier = userID
                    self.isSignedIn = true
                    self.isGuestSession = false
                    self.authErrorMessage = nil
                    self.pendingAppleEmail = appleEmail
                }
            } else {
                DispatchQueue.main.async { self.authErrorMessage = "Invalid Apple credential." }
            }
        case .failure(let error):
            DispatchQueue.main.async { self.authErrorMessage = error.localizedDescription }
        }
    }

    func startGuestSession() {
        defaults.set(true, forKey: guestSessionKey)
        KeychainHelper.shared.delete(userIdKey)
        DispatchQueue.main.async {
            self.userIdentifier = nil
            self.isGuestSession = true
            self.isSignedIn = true
            self.authErrorMessage = nil
            self.pendingAppleEmail = nil
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
