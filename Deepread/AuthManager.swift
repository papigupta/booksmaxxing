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
        checkICloudAccountStatus()
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
                self.iCloudAccountAvailable = (status == .available)
            }
        }
    }
}

