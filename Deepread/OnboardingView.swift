import SwiftUI
import SwiftData

struct OnboardingView: View {
    let openAIService: OpenAIService
    @Environment(\.modelContext) private var modelContext
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

                TextField("Book title and author name (we'll find the correct details)", text: $bookTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button("Add Book") {
                    let trimmedTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedTitle.isEmpty else { return }
                    selectedBookTitle = trimmedTitle
                    bookTitle = ""
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.primary)
                .disabled(bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                // Navigation will be handled by navigationDestination
            }
            .padding()
            .navigationTitle("Deepread")
            .navigationDestination(isPresented: $isNavigatingToBookOverview) {
                BookOverviewView(bookTitle: selectedBookTitle, openAIService: openAIService, bookService: BookService(modelContext: modelContext))
            }
            .onChange(of: selectedBookTitle) { oldValue, newValue in
                if !newValue.isEmpty {
                    isNavigatingToBookOverview = true
                }
            }
        }
    }
}
