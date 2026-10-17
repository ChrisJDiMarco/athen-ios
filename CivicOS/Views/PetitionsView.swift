import SwiftUI

/// Top-level browse surface for petitions. Reachable from Home pulse strip
/// (when local petitions exist), IssueDetailView, and the You tab. Filter
/// chips at top, sticky "Start a petition" CTA at bottom-right.
struct PetitionsView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var presentedDetail: CivicPetition?
    @State private var showComposer: Bool = false
    @State private var activeFilter: PetitionFilter = .openOnly

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                CivicTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        header
                            .padding(.horizontal, 18)
                            .padding(.top, 14)

                        BackendOfflineBanner()
                            .padding(.horizontal, 18)

                        filterStrip
                            .padding(.horizontal, 18)

                        if store.isLoadingPetitions && store.petitions.isEmpty {
                            loadingState
                        } else if filteredPetitions.isEmpty {
                            emptyState
                                .padding(.horizontal, 18)
                                .padding(.top, 10)
                        } else {
                            ForEach(filteredPetitions) { petition in
                                Button {
                                    Haptics.selection()
                                    presentedDetail = petition
                                } label: {
                                    petitionRow(petition)
                                        .padding(.horizontal, 18)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let err = store.lastPetitionError {
                            errorBanner(err)
                                .padding(.horizontal, 18)
                                .padding(.top, 8)
                        }

                        Color.clear.frame(height: 90)
                    }
                }
                .refreshable {
                    _ = await store.loadPetitions(activeFilter)
                }

                startButton
                    .padding(.trailing, 18)
                    .padding(.bottom, 22)
            }
            .navigationTitle("Petitions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .task {
                if store.petitions.isEmpty {
                    _ = await store.loadPetitions(activeFilter)
                }
            }
            .onChange(of: activeFilter) { _, newValue in
                Task { _ = await store.loadPetitions(newValue) }
            }
            .sheet(item: $presentedDetail) { petition in
                PetitionDetailView(petitionID: petition.id)
                    .environment(store)
            }
            .sheet(isPresented: $showComposer) {
                PetitionComposerView()
                    .environment(store)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("COLLECTIVE VOICE", systemImage: "person.3.sequence.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("Demands & petitions")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerSubtitle: String {
        guard let stats = store.petitionStats else {
            return "Sign on, start your own, or rally your crew. One signature stacks with thousands."
        }
        if stats.total == 0 {
            return "Be first — start a petition on any civic issue."
        }
        return "\(stats.open) open · \(stats.totalSignatures) signatures collected · \(stats.delivered) delivered to officials"
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Open", active: activeFilter == .openOnly) { activeFilter = .openOnly }
                filterChip("All", active: activeFilter.status == nil && !activeFilter.mine) {
                    activeFilter = .everything
                }
                filterChip("Delivered", active: activeFilter.status == .delivered) {
                    activeFilter = PetitionFilter(status: .delivered, zip: nil, topicId: nil, mine: false)
                }
                filterChip("Mine", active: activeFilter.mine) { activeFilter = .mine }
                if let zip = store.profile?.zipCode, !zip.isEmpty {
                    filterChip("Near \(zip)", active: activeFilter.zip != nil) {
                        var next = activeFilter
                        next.zip = next.zip == nil ? zip : nil
                        activeFilter = next
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func filterChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? .white : CivicTheme.violet)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(active ? CivicTheme.violet : CivicTheme.violet.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(CivicTheme.violet.opacity(active ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var filteredPetitions: [CivicPetition] {
        store.petitions
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView().tint(CivicTheme.violet)
            Text("Loading petitions…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CivicTheme.quietInk)
            Text(activeFilter.mine ? "You haven't signed or started a petition yet" : "No petitions match this filter")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .multilineTextAlignment(.center)
            Text("Tap the violet button below to start one. It takes about a minute and Claude drafts the body for you.")
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func petitionRow(_ petition: CivicPetition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: petition.status.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(petition.status.tint)
                Text(petition.status.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(petition.status.tint)
                Spacer()
                if store.signedPetitionIDs.contains(petition.id) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Signed")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(CivicTheme.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CivicTheme.green.opacity(0.12), in: Capsule())
                }
            }
            Text(petition.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(petition.ask)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            progressLine(for: petition)
            HStack(spacing: 8) {
                ForEach(petition.targets.prefix(3), id: \.officialName) { target in
                    HStack(spacing: 4) {
                        Image(systemName: "person.text.rectangle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(target.officialName)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(CivicTheme.mutedInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CivicTheme.panelElevated, in: Capsule())
                }
                if petition.targets.count > 3 {
                    Text("+\(petition.targets.count - 3)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
        .shadow(color: CivicTheme.cardShadow, radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private func progressLine(for petition: CivicPetition) -> some View {
        if let progress = petition.thresholdProgress, let threshold = petition.threshold {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(petition.signerCount) of \(threshold) signatures")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Spacer()
                    if let days = petition.daysUntilDeadline, days >= 0 {
                        Text("\(days)d left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(days <= 3 ? CivicTheme.red : CivicTheme.mutedInk)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CivicTheme.violet.opacity(0.15))
                        Capsule().fill(CivicTheme.violet).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
        } else {
            HStack {
                Text("\(petition.signerCount) signature\(petition.signerCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                Spacer()
                if let days = petition.daysUntilDeadline, days >= 0 {
                    Text("\(days)d left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(days <= 3 ? CivicTheme.red : CivicTheme.mutedInk)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            Haptics.selection()
            showComposer = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Start a petition")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(CivicTheme.violet, in: Capsule())
            .shadow(color: CivicTheme.violet.opacity(0.35), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CivicTheme.amber)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
