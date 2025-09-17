import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var currentProfile: UserProfile?

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
                }

                Section(header: Text("Legal")) {
                    Link("Terms of Service", destination: URL(string: "https://booksmaxxing.com/termsofservice")!)
                    Link("Privacy Policy", destination: URL(string: "https://booksmaxxing.com/privacypolicy")!)
                }

                // Logout is now available under the kebab menu; remove from here per request.
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if let existing = profiles.first {
                currentProfile = existing
            } else {
                let created = UserProfile()
                modelContext.insert(created)
                currentProfile = created
            }
        }
    }
}
