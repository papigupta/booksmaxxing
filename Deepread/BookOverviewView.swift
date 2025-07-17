import SwiftUI

struct BookOverviewView: View {
    let bookTitle: String
    @StateObject private var viewModel: IdeaExtractionViewModel

    init(bookTitle: String, openAIService: OpenAIService) {
        self.bookTitle = bookTitle
        self._viewModel = StateObject(wrappedValue: IdeaExtractionViewModel(openAIService: openAIService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(bookTitle)
                .font(.largeTitle)
                .bold()

            if viewModel.isLoading {
                ProgressView("Breaking book into core ideas…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.extractedIdeas, id: \.self) { idea in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.blue)
                                Text(idea)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear {
            print("DEBUG: BookOverviewView onAppear triggered")
            viewModel.extractIdeas(from: bookTitle)
        }
    }
}
