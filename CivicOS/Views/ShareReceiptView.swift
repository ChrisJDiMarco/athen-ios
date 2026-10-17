import SwiftUI

struct ShareReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    let issue: CivicIssue
    let receipt: FilingReceipt
    let constituentLabel: String

    @State private var renderedImage: Image?
    @State private var renderedUIImage: UIImage?

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    posterPreview
                    shareRow
                }
                .padding(20)
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: renderPoster)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Share your filing")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Drop this in a group chat or post it. One tap installs \(AppBrand.name) and opens the same issue, ready to file.")
                .font(.system(size: 14))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var posterPreview: some View {
        FilingPoster(
            issue: issue,
            receipt: receipt,
            constituentLabel: constituentLabel
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var shareRow: some View {
        HStack(spacing: 12) {
            if let image = renderedImage {
                ShareLink(
                    item: image,
                    subject: Text("I just filed on \(issue.title)"),
                    message: Text(shareMessage),
                    preview: SharePreview("\(issue.title) — filed", image: image)
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                        Text("Share")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .shadow(color: CivicTheme.cyan.opacity(0.30), radius: 10, x: 0, y: 4)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
    }

    private var shareMessage: String {
        let link = "athen://issue/\(issue.id.uuidString)"
        return "I just filed \(receipt.action.rawValue.lowercased()) on \(issue.title). \(AppBrand.name) makes it 30 seconds — open the same issue: \(link)"
    }

    private func renderPoster() {
        let poster = FilingPoster(
            issue: issue,
            receipt: receipt,
            constituentLabel: constituentLabel
        )
        .frame(width: 380, height: 480)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            renderedUIImage = uiImage
            renderedImage = Image(uiImage: uiImage)
        }
    }
}

private struct FilingPoster: View {
    let issue: CivicIssue
    let receipt: FilingReceipt
    let constituentLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("CIVIC OS", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .tracking(1.2)
                Spacer()
                Text(receipt.confirmationCode)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CivicTheme.mutedInk)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: receipt.action == .endorse ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(receipt.action == .endorse ? CivicTheme.green : CivicTheme.red)
                    Text("Filed as \(receipt.action.rawValue.lowercased())")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(receipt.action == .endorse ? CivicTheme.green : CivicTheme.red)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Text(issue.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
            }

            HStack(spacing: 8) {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(CivicTheme.cyan)
                Text(issue.jurisdiction)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
            }

            Divider().overlay(CivicTheme.hairline)

            VStack(alignment: .leading, spacing: 6) {
                Text("FILED WITH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .tracking(0.8)
                Text(receipt.officialName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Text("by \(constituentLabel)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }

            Spacer(minLength: 0)

            HStack {
                Text("Join me on \(AppBrand.name)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(CivicTheme.cyan)
            }
            .padding(14)
            .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .stroke(CivicTheme.cyan.opacity(0.25), lineWidth: 1)
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
        .shadow(color: CivicTheme.cardShadowStrong, radius: 18, x: 0, y: 10)
    }
}
