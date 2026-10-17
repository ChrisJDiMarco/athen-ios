import SwiftUI
import UIKit

/// Thin UIActivityViewController bridge for sharing arbitrary items
/// (file URLs, text, etc.) via SwiftUI `.sheet`. Used by the CSV export
/// flow in DashboardView; reusable for anything that wants the system
/// share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
