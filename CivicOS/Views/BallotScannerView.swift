import SwiftUI
import PhotosUI
import Vision
import UIKit

/// Lets the operator photograph their sample ballot, runs on-device Vision
/// OCR to extract the text, then sends that text to the backend for a
/// per-item plain-English brief. Neutral throughout — never tells anyone how
/// to vote. Scaffold-level: single image, no PDF, no multi-page stitching yet.
struct BallotScannerView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var extractedText: String = ""
    @State private var analysis: BallotAnalysis?
    @State private var phase: Phase = .pickPhoto
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case pickPhoto
        case extracting
        case extracted
        case analyzing
        case results
        case failed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        switch phase {
                        case .pickPhoto:
                            picker
                        case .extracting:
                            statusCard("Reading your ballot", systemImage: "doc.text.viewfinder")
                        case .extracted:
                            previewCard
                            analyzeButton
                        case .analyzing:
                            statusCard("Athen is reading the items", systemImage: "sparkles")
                        case .results:
                            if let analysis {
                                resultsView(analysis)
                                retryRow
                            }
                        case .failed:
                            failedCard
                            retryRow
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Ballot scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadAndExtract(item) }
            }
        }
    }

    // MARK: - Phase views

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("BALLOT SCANNER", systemImage: "doc.text.image.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("Snap your sample ballot")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Athen reads each race or measure and explains in plain English what YES and NO actually do. We don't tell you how to vote — that's yours.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var picker: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Text("Pick a photo of your ballot")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text("Library only for now. Take the photo in the Camera app, then come back.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(CivicTheme.violet.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
            }
            .buttonStyle(.plain)
        }
    }

    private func statusCard(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(CivicTheme.violet.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                ProgressView().tint(CivicTheme.violet)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CivicTheme.green)
                Text("EXTRACTED \(extractedText.count) CHARS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.green)
                Spacer()
            }
            if let img = capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
            }
            ScrollView {
                Text(extractedText.isEmpty ? "(no text detected)" : extractedText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var analyzeButton: some View {
        Button {
            Haptics.selection()
            Task { await runAnalysis() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                Text("Generate plain-English briefs")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: CivicTheme.violet.opacity(0.25), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(extractedText.count < 20)
    }

    private func resultsView(_ analysis: BallotAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(CivicTheme.violet)
                Text(analysis.notice)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            ForEach(analysis.items) { item in
                ballotItemCard(item)
            }
        }
    }

    private func ballotItemCard(_ item: BallotItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.itemKind.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(item.itemKind.tint)
                    .frame(width: 24, height: 24)
                    .background(item.itemKind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                Text(item.itemKind.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(item.itemKind.tint)
                Spacer()
            }
            Text(item.itemTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.plainEnglish)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            if let yes = item.whatYesMeans, !yes.isEmpty {
                yesNoRow(label: "YES does", text: yes, tint: CivicTheme.green)
            }
            if let no = item.whatNoMeans, !no.isEmpty {
                yesNoRow(label: "NO does", text: no, tint: CivicTheme.red)
            }
            if !item.considerations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONSIDER")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(CivicTheme.quietInk)
                    ForEach(item.considerations, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(CivicTheme.quietInk).frame(width: 4, height: 4).padding(.top, 7)
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private func yesNoRow(label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.20), lineWidth: 1))
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CivicTheme.amber)
                Text("Something went sideways")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var retryRow: some View {
        Button {
            Haptics.selection()
            reset()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                Text("Scan another")
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(CivicTheme.cyan)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(CivicTheme.cyan.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - OCR + analysis

    private func loadAndExtract(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        phase = .extracting
        errorMessage = nil
        analysis = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                throw NSError(domain: "BallotScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't load that image."])
            }
            capturedImage = img
            let text = try await Self.recognizeText(in: img)
            extractedText = text
            phase = .extracted
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func runAnalysis() async {
        phase = .analyzing
        errorMessage = nil
        do {
            let result = try await store.analyzeBallot(text: extractedText)
            analysis = result
            phase = .results
        } catch {
            errorMessage = (error as? CivicFilingError)?.localizedDescription ?? error.localizedDescription
            phase = .failed
        }
    }

    private func reset() {
        selectedPhoto = nil
        capturedImage = nil
        extractedText = ""
        analysis = nil
        errorMessage = nil
        phase = .pickPhoto
    }

    private static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

#Preview {
    BallotScannerView()
        .environment(CivicOSStore())
}
