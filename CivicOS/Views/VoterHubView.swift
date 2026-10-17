import SwiftUI

/// Top-level surface for everything voter-related: countdown to next
/// election, sample ballot preview, polling place, registration status, and
/// rep scorecard. Reachable from Home + You tab. All sections gracefully
/// degrade when the backend lacks GOOGLE_CIVIC_API_KEY.
struct VoterHubView: View {
    @Environment(CivicOSStore.self) private var store

    @State private var showSampleBallot: Bool = false
    @State private var showRegistration: Bool = false
    @State private var showScorecard: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        intro
                        ZipChangedBanner(hasFreshData: !store.isLoadingVoterRail && (store.registrationInfo != nil || store.pollingPlaceInfo != nil))
                        electionHero
                        if store.profile == nil {
                            zipPromptCard
                        } else {
                            sampleBallotCard
                            pollingPlaceCard
                            registrationCard
                            scorecardCard
                        }
                        if let err = store.lastVoterRailError {
                            errorCard(err)
                        }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
                .refreshable {
                    await store.loadVoterRail(force: true)
                }
            }
            .navigationTitle("Vote")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.upcomingElections.isEmpty {
                    await store.loadVoterRail()
                }
            }
            .sheet(isPresented: $showSampleBallot) {
                SampleBallotView()
                    .environment(store)
            }
            .sheet(isPresented: $showRegistration) {
                VoterRegistrationView()
                    .environment(store)
            }
            .sheet(isPresented: $showScorecard) {
                RepScorecardView()
                    .environment(store)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("VOTER RAIL", systemImage: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("From registration to ballot to accountability")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Athen tracks your voter status, prep your ballot before election day, and shows you whether your reps voted with you.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var electionHero: some View {
        if let next = store.nextElection {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: next.isToday ? "checkmark.seal.fill" : "calendar.badge.clock")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                    Text(next.isToday ? "ELECTION DAY" : "NEXT ELECTION")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.88))
                }
                Text(next.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let days = next.daysUntil {
                        Text(days == 0 ? "TODAY" : "\(days)")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        if days != 0 {
                            Text(days == 1 ? "day to go" : "days to go")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer()
                    Text(next.electionDay)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: next.isToday
                        ? [CivicTheme.red, Color(red: 0.55, green: 0.10, blue: 0.30)]
                        : [CivicTheme.violet, Color(red: 0.20, green: 0.12, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: CivicTheme.violet.opacity(0.30), radius: 12, x: 0, y: 5)
        } else if !store.upcomingElections.isEmpty {
            disabledHero(title: "No upcoming elections in the next 30 days", systemImage: "calendar")
        } else {
            disabledHero(title: store.isLoadingVoterRail ? "Loading elections…" : "No upcoming elections found for your ZIP yet. Athen checks daily.", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private func disabledHero(title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .frame(width: 48, height: 48)
                .background(CivicTheme.panelElevated, in: Circle())
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    // MARK: - Cards

    private var sampleBallotCard: some View {
        Button {
            Haptics.selection()
            showSampleBallot = true
        } label: {
            actionRow(
                title: ballotCardTitle,
                subtitle: ballotCardSubtitle,
                systemImage: "doc.text.image.fill",
                tint: CivicTheme.violet,
                badge: ballotCardBadge
            )
        }
        .buttonStyle(.plain)
    }

    private var ballotCardTitle: String {
        guard let ballot = store.sampleBallotResponse?.ballot, !ballot.contests.isEmpty else {
            return "Preview my ballot"
        }
        return "My ballot · \(ballot.contests.count) item\(ballot.contests.count == 1 ? "" : "s")"
    }

    private var ballotCardSubtitle: String {
        guard store.sampleBallotResponse?.enabled == true else {
            return "Sample ballots become available 4–6 weeks before your next election. Athen will let you know."
        }
        if let ballot = store.sampleBallotResponse?.ballot, !ballot.contests.isEmpty {
            return "Every race + measure on your next ballot, with plain-English briefs."
        }
        return "Generates plain-English briefs for every race + measure on your next ballot."
    }

    private var ballotCardBadge: String? {
        guard let ballot = store.sampleBallotResponse?.ballot, !ballot.contests.isEmpty else { return nil }
        return "Ready"
    }

    private var pollingPlaceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Where you vote", systemImage: "mappin.circle.fill", tint: CivicTheme.cyan)
            if let places = store.pollingPlaceInfo?.pollingPlaces, !places.isEmpty {
                ForEach(places.prefix(2)) { place in
                    pollingPlaceRow(place)
                }
            } else if store.pollingPlaceInfo?.enabled == false {
                Text(store.pollingPlaceInfo?.notice ?? "Visit vote.gov to find your polling place.")
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No polling place returned for your ZIP yet. Try again closer to election day.")
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.cyan.opacity(0.18), lineWidth: 1))
    }

    private func pollingPlaceRow(_ place: PollingPlace) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(place.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(place.address)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let hours = place.pollingHours {
                Text("Hours: \(hours)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
            }
            if let lat = place.latitude, let lon = place.longitude {
                Link(destination: URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Open in Maps")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(CivicTheme.cyan)
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var registrationCard: some View {
        Button {
            Haptics.selection()
            showRegistration = true
        } label: {
            actionRow(
                title: registrationTitle,
                subtitle: registrationSubtitle,
                systemImage: "person.text.rectangle.fill",
                tint: CivicTheme.amber,
                badge: nil
            )
        }
        .buttonStyle(.plain)
    }

    private var registrationTitle: String {
        guard let reg = store.registrationInfo else { return "Voter registration" }
        return "Voter registration · \(reg.stateName)"
    }

    private var registrationSubtitle: String {
        guard let reg = store.registrationInfo else {
            return "Look up registration requirements + deadlines for your state."
        }
        var features: [String] = []
        if reg.online { features.append("online") }
        if reg.sameDay { features.append("same-day") }
        if reg.automaticAtDMV { features.append("auto at DMV") }
        let feat = features.isEmpty ? "" : " · \(features.joined(separator: " · "))"
        return "\(reg.deadlineLabel)\(feat)"
    }

    private var scorecardCard: some View {
        Button {
            Haptics.selection()
            Task { await store.loadRepScorecard() }
            showScorecard = true
        } label: {
            actionRow(
                title: scorecardTitle,
                subtitle: scorecardSubtitle,
                systemImage: "chart.bar.xaxis",
                tint: CivicTheme.green,
                badge: nil
            )
        }
        .buttonStyle(.plain)
    }

    private var scorecardTitle: String {
        let count = store.repScorecard?.scorecards.count ?? 0
        if count == 0 { return "Rep scorecard" }
        return "Rep scorecard · \(count) official\(count == 1 ? "" : "s")"
    }

    private var scorecardSubtitle: String {
        guard let card = store.repScorecard, !card.scorecards.isEmpty else {
            return "Track how your reps actually voted on the bills you filed about."
        }
        let totalFilings = card.scorecards.reduce(0) { $0 + $1.totalFilings }
        return "\(totalFilings) filings tracked · vote alignment populates as bills get voted on."
    }

    private var zipPromptCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Set your ZIP first")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Voter hub needs your ZIP to find your polling place, ballot, and registration info.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.amber.opacity(0.20), lineWidth: 1))
    }

    // MARK: - Helpers

    private func actionRow(title: String, subtitle: String, systemImage: String, tint: Color, badge: String?) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.15))
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tint, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
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
            Spacer()
        }
    }

    private func errorCard(_ message: String) -> some View {
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
