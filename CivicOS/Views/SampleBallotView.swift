import SwiftUI

/// Renders the user's personalized sample ballot for the next election, with
/// Claude-written plain-English briefs per race + measure. Lets the user
/// pre-mark positions ("my ballot plan") and save them as a checklist they
/// can pull up at the polls.
struct SampleBallotView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var planMarks: [String: PlanMark] = [:]
    @State private var isReloading: Bool = false

    enum PlanMark: String, Hashable {
        case yes, no, candidate, skip
        var label: String {
            switch self {
            case .yes: "Lean YES"
            case .no: "Lean NO"
            case .candidate: "Plan to support"
            case .skip: "Skip"
            }
        }
        var tint: Color {
            switch self {
            case .yes, .candidate: CivicTheme.green
            case .no: CivicTheme.red
            case .skip: CivicTheme.quietInk
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        electionHeader
                        notice
                        if let ballot = store.sampleBallotResponse?.ballot {
                            ForEach(ballot.contests) { contest in
                                contestCard(contest)
                            }
                            if ballot.contests.isEmpty {
                                emptyState
                            }
                        } else {
                            emptyState
                        }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
                .refreshable {
                    isReloading = true
                    await store.loadSampleBallot(electionId: store.nextElection?.id)
                    isReloading = false
                }
            }
            .navigationTitle("My ballot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        isReloading = true
                        Task {
                            await store.loadSampleBallot(electionId: store.nextElection?.id)
                            isReloading = false
                        }
                    } label: {
                        if isReloading {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(CivicTheme.cyan)
                        }
                    }
                    .disabled(isReloading)
                }
            }
            .task {
                if store.sampleBallotResponse?.ballot == nil {
                    await store.loadSampleBallot(electionId: store.nextElection?.id)
                }
            }
        }
    }

    @ViewBuilder
    private var electionHeader: some View {
        let ballot = store.sampleBallotResponse?.ballot
        VStack(alignment: .leading, spacing: 6) {
            Label("MY SAMPLE BALLOT", systemImage: "doc.text.image.fill")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.violet)
            Text(ballot?.electionName ?? store.nextElection?.name ?? "Upcoming election")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let day = ballot?.electionDay ?? store.nextElection?.electionDay {
                Text("Election day: \(day)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let n = store.sampleBallotResponse?.notice, !n.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(CivicTheme.violet)
                Text(n)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        if store.sampleBallotResponse?.enabled == false {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CivicTheme.amber)
                Text(store.sampleBallotResponse?.notice ?? "Sample ballots become available 4–6 weeks before your next election. Check back closer to election day.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CivicTheme.quietInk)
            Text("No ballot returned yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Google Civic typically posts sample ballots 2–4 weeks before election day. Pull to refresh closer to the election.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(CivicTheme.mutedInk)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func contestCard(_ contest: BallotContest) -> some View {
        let mark = planMarks[contest.id]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: contest.kind.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(contest.kind.tint)
                    .frame(width: 24, height: 24)
                    .background(contest.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                Text(contest.kind.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(contest.kind.tint)
                Spacer()
                if let mark {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(mark.label)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(mark.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(mark.tint.opacity(0.12), in: Capsule())
                }
            }
            Text(contest.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let district = contest.district {
                Text(district)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            Text(contest.plainEnglish)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            if let yes = contest.whatYesMeans {
                yesNoRow(label: "YES does", text: yes, tint: CivicTheme.green)
            }
            if let no = contest.whatNoMeans {
                yesNoRow(label: "NO does", text: no, tint: CivicTheme.red)
            }
            if let candidates = contest.candidates, !candidates.isEmpty {
                VStack(spacing: 6) {
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
            }
            if !contest.considerations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONSIDER")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(CivicTheme.quietInk)
                    ForEach(contest.considerations, id: \.self) { line in
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
            planControls(for: contest)
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

    private func candidateRow(_ candidate: BallotBriefCandidate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                HStack(spacing: 6) {
                    if let party = candidate.party {
                        Text(party)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(partyTint(party), in: Capsule())
                    }
                    if let blurb = candidate.blurb {
                        Text(blurb)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    private func partyTint(_ party: String) -> Color {
        let lower = party.lowercased()
        if lower.contains("democrat") { return Color(red: 0.10, green: 0.40, blue: 0.85) }
        if lower.contains("republican") { return Color(red: 0.85, green: 0.20, blue: 0.20) }
        if lower.contains("green") { return CivicTheme.green }
        if lower.contains("libertarian") { return CivicTheme.amber }
        return CivicTheme.quietInk
    }

    private func planControls(for contest: BallotContest) -> some View {
        let options: [PlanMark] = contest.kind == .measure ? [.yes, .no, .skip] : [.candidate, .skip]
        return HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let active = planMarks[contest.id] == option
                Button {
                    Haptics.selection()
                    planMarks[contest.id] = active ? nil : option
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(active ? .white : option.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(active ? option.tint : option.tint.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(option.tint.opacity(active ? 0 : 0.20), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
