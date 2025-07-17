import SwiftUI

struct OnboardingView: View {
    @State private var bookTitle: String = ""
    @State private var isNavigatingToBookOverview = false
    @State private var selectedBookTitle: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Which book do you want to master?")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                TextField("Book title", text: $bookTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button("Add Book") {
                    let trimmedTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedTitle.isEmpty else { return }
                    selectedBookTitle = trimmedTitle
                    bookTitle = ""
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                NavigationLink(
                    destination: BookOverviewView(bookTitle: selectedBookTitle, openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)),
                    isActive: $isNavigatingToBookOverview
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .padding()
            .navigationTitle("Deepread")
            .onChange(of: selectedBookTitle) { newValue in
                if !newValue.isEmpty {
                    isNavigatingToBookOverview = true
                }
            }
        }
    }
}
