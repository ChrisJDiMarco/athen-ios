import SwiftUI

/// Full-screen petition viewer. Reads the freshest copy from the store, lets
/// the user sign / unsign / share / deliver (creator only). Sticky sign
/// button at bottom keeps the primary action one tap away from any scroll
/// position.
struct PetitionDetailView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let petitionID: String

    @State private var signerName: String = ""
    @State private var signerComment: String = ""
    @State private var showSignSheet: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var deliveryResult: CivicPetitionDeliveryResult?
    @State private var inlineError: String?

    private var petition: CivicPetition? {
        store.petition(with: petitionID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CivicTheme.screenBackground.ignoresSafeArea()
                if let petition {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            statusBar(petition)
                            heroBlock(petition)
                            progressCard(petition)
                            targetsCard(petition)
                            bodyCard(petition)
                            signerWall(petition)
                            if petition.status == .delivered {
                                deliveredCard(petition)
                            }
                            if store.createdPetitionIDs.contains(petition.id), petition.status == .open {
                                creatorActions(petition)
                            }
                            Color.clear.frame(height: 90)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    }
                    if petition.status == .open {
                        signActionBar(petition)
                    }
                } else {
                    notFound
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let petition {
                        ShareLink(item: shareText(petition)) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(CivicTheme.cyan)
                        }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.selection() })
                    }
                }
            }
            .task {
                // Pull latest detail in case state on this device is stale.
                _ = await store.loadPetitions(store.petitionFilter)
            }
            .sheet(isPresented: $showSignSheet) {
                signSheet
            }
        }
    }

    // MARK: - Header sections

    private func statusBar(_ petition: CivicPetition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: petition.status.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(petition.status.tint)
            Text(petition.status.label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(petition.status.tint)
            Spacer()
            if let issueTitle = petition.attachedIssueTitle {
                Text(issueTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .lineLimit(1)
            }
        }
    }

    private func heroBlock(_ petition: CivicPetition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(petition.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                Text(petition.ask)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Started by \(petition.creatorDisplayName) · \(relativeDate(petition.createdAt))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.quietInk)
                .padding(.top, 2)
            HStack {
                ReadAloudButton(text: { petitionReadAloudScript(petition) }, label: "Read petition")
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func petitionReadAloudScript(_ petition: CivicPetition) -> String {
        [
            petition.title,
            "The ask: \(petition.ask)",
            petition.body,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func progressCard(_ petition: CivicPetition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(petition.signerCount)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                    .monospacedDigit()
                Text("signature\(petition.signerCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                Spacer()
                if let days = petition.daysUntilDeadline, days >= 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(days)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(days <= 3 ? CivicTheme.red : CivicTheme.amber)
                            .monospacedDigit()
                        Text("DAYS LEFT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                }
            }
            if let progress = petition.thresholdProgress, let threshold = petition.threshold {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CivicTheme.violet.opacity(0.15))
                            Capsule().fill(CivicTheme.violet).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int(progress * 100))% of \(threshold)-signature threshold")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            } else {
                Text("No fixed threshold — every signature counts when this is delivered.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            zipBreakdown(petition)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func zipBreakdown(_ petition: CivicPetition) -> some View {
        let buckets = topZipBuckets(petition.signatures)
        if !buckets.isEmpty {
            HStack(spacing: 6) {
                ForEach(buckets, id: \.prefix) { bucket in
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(bucket.prefix)xx · \(bucket.count)")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(CivicTheme.violet)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CivicTheme.violet.opacity(0.10), in: Capsule())
                }
                Spacer()
            }
        }
    }

    private func topZipBuckets(_ signatures: [PetitionSignature]) -> [(prefix: String, count: Int)] {
        var counts: [String: Int] = [:]
        for sig in signatures where !sig.zip.isEmpty {
            let prefix = String(sig.zip.prefix(3))
            counts[prefix, default: 0] += 1
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map { (prefix: $0.key, count: $0.value) }
    }

    private func targetsCard(_ petition: CivicPetition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Delivered to", systemImage: "envelope.fill", tint: CivicTheme.cyan)
            ForEach(petition.targets, id: \.officialName) { target in
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                        .frame(width: 28, height: 28)
                        .background(CivicTheme.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.officialName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(target.jurisdiction)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }
                    Spacer()
                    Text(target.channel == .email ? "Email" : "Form")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CivicTheme.cyan.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private func bodyCard(_ petition: CivicPetition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("The petition", systemImage: "text.alignleft", tint: CivicTheme.violet)
            Text(petition.body)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private func signerWall(_ petition: CivicPetition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Signers (\(petition.signerCount))", systemImage: "person.3.fill", tint: CivicTheme.green)
            if petition.signatures.isEmpty {
                Text("No signatures yet. Be first.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(petition.signatures.prefix(40)) { signer in
                        HStack(spacing: 5) {
                            Text(signer.initials)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(CivicTheme.violet, in: Circle())
                            Text(signerLabel(signer))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CivicTheme.ink)
                        }
                        .padding(.leading, 3)
                        .padding(.trailing, 8)
                        .padding(.vertical, 3)
                        .background(CivicTheme.panelElevated, in: Capsule())
                    }
                }
                if petition.signatures.count > 40 {
                    Text("+\(petition.signatures.count - 40) more")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.green.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.green.opacity(0.15), lineWidth: 1))
    }

    private func signerLabel(_ signer: PetitionSignature) -> String {
        let parts = signer.name.split(separator: " ")
        if parts.count >= 2 {
            let first = String(parts[0])
            let lastInitial = String(parts[parts.count - 1].first ?? Character("?"))
            return "\(first) \(lastInitial)."
        }
        return signer.name
    }

    private func deliveredCard(_ petition: CivicPetition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(CivicTheme.green)
                Text("DELIVERED")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.green)
                Spacer()
                if let date = petition.deliveredAt {
                    Text(relativeDate(date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            }
            if let note = petition.deliveryNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.green.opacity(0.25), lineWidth: 1))
    }

    private func creatorActions(_ petition: CivicPetition) -> some View {
        VStack(spacing: 10) {
            sectionLabel("Creator actions", systemImage: "wand.and.stars", tint: CivicTheme.amber)
            HStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    Task {
                        do {
                            let result = try await store.deliverPetitionNow(petition.id)
                            deliveryResult = result
                        } catch {
                            inlineError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text("Deliver now")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    Haptics.selection()
                    Task { await store.deletePetition(petition.id); dismiss() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.red)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(CivicTheme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.red.opacity(0.20), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.red)
            }
            if let deliveryResult {
                Text("Delivered via \(deliveryResult.channel) to \(deliveryResult.deliveredTo).")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.amber.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Sign action

    private func signActionBar(_ petition: CivicPetition) -> some View {
        let alreadySigned = store.signedPetitionIDs.contains(petition.id)
        return HStack {
            if alreadySigned {
                Button {
                    Haptics.selection()
                    Task { await store.unsignPetition(petition.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Signed · tap to unsign")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.green)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(CivicTheme.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.green.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.selection()
                    prepareSignSheet()
                    showSignSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "signature")
                            .font(.system(size: 16, weight: .bold))
                        Text("Sign this petition")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: CivicTheme.violet.opacity(0.30), radius: 12, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(CivicTheme.hairline).frame(height: 1)
        }
    }

    private func prepareSignSheet() {
        if signerName.isEmpty {
            // Pre-fill from any prior signature on another petition.
            if let myPrior = store.petitions
                .flatMap({ $0.signatures })
                .first(where: { $0.entityId == store.integrationEntityID })
            {
                signerName = myPrior.name
            }
        }
        signerComment = ""
    }

    private var signSheet: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add your signature")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Text("Your name and ZIP appear on the petition packet delivered to officials. ZIP is used to verify you're a constituent.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        labeledField("YOUR NAME", text: $signerName, placeholder: "First Last")
                        labeledField("ZIP", text: zipBinding, placeholder: "19147", keyboard: .numberPad)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("OPTIONAL COMMENT")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(CivicTheme.quietInk)
                            TextEditor(text: $signerComment)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 14))
                                .frame(minHeight: 80)
                                .padding(10)
                                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                        }
                        if let inlineError {
                            Text(inlineError)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CivicTheme.red)
                        }
                        Button {
                            submitSignature()
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "signature")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                Text(isSubmitting ? "Signing…" : "Sign petition")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showSignSheet = false }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var zipBinding: Binding<String> {
        Binding(
            get: { store.profile?.zipCode ?? "" },
            set: { _ in } // We use the store's ZIP — petitions are constituent-locked.
        )
    }

    private var canSubmit: Bool {
        !signerName.trimmingCharacters(in: .whitespaces).isEmpty
            && (store.profile?.zipCode.count ?? 0) >= 5
            && !isSubmitting
    }

    private func submitSignature() {
        guard let petition else { return }
        guard let profile = store.profile else {
            inlineError = "Set your ZIP from Radar → profile first."
            return
        }
        Haptics.impact(.light)
        isSubmitting = true
        inlineError = nil
        Task {
            do {
                _ = try await store.signPetition(
                    petition.id,
                    name: signerName.trimmingCharacters(in: .whitespaces),
                    zip: profile.zipCode,
                    comment: signerComment.trimmingCharacters(in: .whitespaces).isEmpty ? nil : signerComment
                )
                Haptics.success()
                showSignSheet = false
            } catch {
                Haptics.error()
                inlineError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.quietInk)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                .keyboardType(keyboard)
                .autocapitalization(.words)
        }
    }

    // MARK: - Helpers

    private var notFound: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(CivicTheme.quietInk)
            Text("Petition not found")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
            Rectangle()
                .fill(tint.opacity(0.25))
                .frame(height: 1)
        }
    }

    private func shareText(_ petition: CivicPetition) -> String {
        """
        \(petition.title)

        \(petition.ask)

        \(petition.signerCount) signature\(petition.signerCount == 1 ? "" : "s") collected.

        Sign on via Athen.
        """
    }

    private func relativeDate(_ date: Date) -> String {
        let elapsed = -date.timeIntervalSinceNow
        switch elapsed {
        case ..<60: return "just now"
        case ..<3600: return "\(max(1, Int(elapsed / 60)))m ago"
        case ..<86400: return "\(max(1, Int(elapsed / 3600)))h ago"
        default: return "\(max(1, Int(elapsed / 86400)))d ago"
        }
    }
}
