import SwiftUI
import SafariServices

/// SwiftUI bridge for SFSafariViewController. Used to open citation URLs and
/// source links without kicking the user out to Safari.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(red: 0.078, green: 0.722, blue: 0.651, alpha: 1.0)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_: SFSafariViewController, context: Context) {}
}

/// Helper to make presenting safer with optional URLs.
struct SafariURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
