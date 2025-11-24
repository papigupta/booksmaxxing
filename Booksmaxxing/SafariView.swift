import SwiftUI
#if canImport(SafariServices)
import SafariServices
#endif

#if canImport(UIKit)
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor.label
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
struct SafariView: View {
    let url: URL

    var body: some View {
        Link("Open in Browser", destination: url)
            .padding()
    }
}
#endif
