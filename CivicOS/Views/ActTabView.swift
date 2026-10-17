import SwiftUI

/// Combined "Act" tab — single home for every action surface in the app.
///
/// Sub-tabs:
///   - Vote      → VoterHubView (ballot, registration, scorecard)
///   - Petitions → PetitionsView (browse + sign + start)
///   - Officials → OfficialsDirectoryView (federal + state)
///   - Filings   → FilingHistoryView (your sent receipts)
///
/// One persistent segmented control at the top swaps the body view. Each
/// section keeps its own NavigationStack via the view it owns.
struct ActTabView: View {
    @Environment(CivicOSStore.self) private var store
    @AppStorage("athen.act.section.v1") private var sectionRaw: String = ActSection.vote.rawValue

    enum ActSection: String, CaseIterable, Identifiable {
        case vote, petitions, officials, filings

        var id: String { rawValue }
        var label: String {
            switch self {
            case .vote: "Vote"
            case .petitions: "Petitions"
            case .officials: "Officials"
            case .filings: "Filings"
            }
        }
        var icon: String {
            switch self {
            case .vote: "checkmark.seal.fill"
            case .petitions: "person.3.sequence.fill"
            case .officials: "person.crop.rectangle.fill"
            case .filings: "tray.full.fill"
            }
        }
        var tint: Color {
            switch self {
            case .vote: CivicTheme.green
            case .petitions: CivicTheme.violet
            case .officials: CivicTheme.cyan
            case .filings: CivicTheme.amber
            }
        }
    }

    private var section: ActSection {
        get { ActSection(rawValue: sectionRaw) ?? .vote }
        nonmutating set { sectionRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionSwitcher
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(CivicTheme.screenBackground)

            Group {
                switch section {
                case .vote: VoterHubView()
                case .petitions: PetitionsView()
                case .officials: OfficialsDirectoryView()
                case .filings: FilingHistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CivicTheme.screenBackground.ignoresSafeArea())
    }

    private var sectionSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(ActSection.allCases) { option in
                let active = section == option
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        section = option
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(option.label)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(active ? .white : CivicTheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        Group {
                            if active { Capsule().fill(option.tint) } else { Color.clear }
                        }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label) section")
            }
        }
        .padding(4)
        .background(CivicTheme.panelElevated, in: Capsule())
        .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
    }
}
