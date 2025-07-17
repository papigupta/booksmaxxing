import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @State private var title: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Which book do you want to master?")
                    .font(.title2)

                TextField("Book title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button("Add Book") {
                    let book = Book(title: title)
                    context.insert(book)
                    title = ""
                }
                .buttonStyle(.borderedProminent)

                List(books) { book in
                    Text(book.title)
                }
            }
            .padding()
            .navigationTitle("Deepread")
        }
    }
}


import Foundation
