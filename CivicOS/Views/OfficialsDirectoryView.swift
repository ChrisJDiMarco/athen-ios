import SwiftUI

/// Top-level browse surface for the master directory of US elected
/// officials. Sections: My reps (federal + state for user's ZIP), Federal
/// (all members of Congress + executive), and per-state expansion. Search
/// bar across the top searches all loaded entries.
struct OfficialsDirectoryView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""
    @State private var searchResults: [DirectoryOfficial] = []
    @State private var isSearching: Bool = false
    @State private var presented: DirectoryOfficial?
    @State private var activeChamberFilter: ChamberFilter = .all
    @State private var activePartyFilter: PartyFilter = .all

    enum ChamberFilter: String, CaseIterable, Identifiable {
        case all, senate, house, executive
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All chambers"
            case .senate: "Senate"
            case .house: "House"
            case .executive: "Executive"
            }
        }
    }

    enum PartyFilter: String, CaseIterable, Identifiable {
        case all, democratic, republican, independent, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "Any party"
            case .democratic: "Democratic"
            case .republican: "Republican"
            case .independent: "Independent"
            case .other: "Other"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        intro
                            .padding(.horizontal, 18)
                            .padding(.top, 14)

                        BackendOfflineBanner()
                            .padding(.horizontal, 18)

                        searchBar
                            .padding(.horizontal, 18)

                        if !searchQuery.isEmpty {
                            searchSection
                                .padding(.horizontal, 18)
                        } else {
                            if !store.myReps.isEmpty {
                                myRepsSection
                                    .padding(.horizontal, 18)
                            }
                            chamberFilterBar
                                .padding(.horizontal, 18)
                            partyFilterBar
                                .padding(.horizontal, 18)
                            federalSection
                                .padding(.horizontal, 18)
                            if !store.stateDirectoryByCode.isEmpty {
                                stateSection
                                    .padding(.horizontal, 18)
                            }
                        }
                        if let err = store.lastDirectoryError {
                            errorBanner(err)
                                .padding(.horizontal, 18)
                        }
                        Color.clear.frame(height: 24)
                    }
                }
                .refreshable {
                    _ = await store.loadFederalDirectory(force: true)
                    if let state = store.profile?.stateCode {
                        _ = await store.loadStateDirectory(state, force: true)
                    }
                }
            }
            .navigationTitle("Directory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .task {
                if store.federalDirectory.isEmpty {
                    _ = await store.loadFederalDirectory()
                }
                if let state = store.profile?.stateCode, store.stateDirectoryByCode[state] == nil {
                    _ = await store.loadStateDirectory(state)
                }
            }
            .onChange(of: searchQuery) { _, q in
                debounceSearch(q)
            }
            .sheet(item: $presented) { official in
                OfficialDetailView(official: official)
                    .environment(store)
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("DIRECTORY", systemImage: "person.text.rectangle.fill")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.cyan)
            Text("Every elected official, in one place")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("President, Congress, governors, state legislators. Tap anyone to see their office, social handles, recent votes, and your filings with them.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CivicTheme.mutedInk)
            TextField("Search by name, state, district", text: $searchQuery)
                .font(.system(size: 14))
                .autocapitalization(.words)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CivicTheme.quietInk)
                }
                .buttonStyle(.plain)
            }
            if isSearching {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("RESULTS · \(searchResults.count)", systemImage: "magnifyingglass", tint: CivicTheme.cyan)
            if searchResults.isEmpty {
                Text(isSearching ? "Searching…" : "No matches. Try a name, party, state, or district.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(searchResults) { person in
                        officialRow(person)
                    }
                }
            }
        }
    }

    private var myRepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MY REPS", systemImage: "star.fill", tint: CivicTheme.amber)
            VStack(spacing: 8) {
                ForEach(store.myReps) { person in
                    officialRow(person, accent: true)
                }
            }
        }
    }

    private var chamberFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChamberFilter.allCases) { f in
                    filterChip(f.label, active: activeChamberFilter == f) {
                        activeChamberFilter = f
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private var partyFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PartyFilter.allCases) { f in
                    filterChip(f.label, active: activePartyFilter == f) {
                        activePartyFilter = f
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? .white : CivicTheme.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? CivicTheme.violet : CivicTheme.violet.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(CivicTheme.violet.opacity(active ? 0 : 0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var federalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FEDERAL · \(filteredFederal.count)", systemImage: "building.columns.fill", tint: DirectoryOfficial.Level.federal.tint)
            if filteredFederal.isEmpty {
                if store.isLoadingDirectory {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading Congress…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }
                    .padding(.vertical, 12)
                } else {
                    Text("No matches with current filters.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 8) {
                    // Cap at first 60 by default; the search bar is the
                    // intended way to find specific people.
                    ForEach(filteredFederal.prefix(60)) { person in
                        officialRow(person)
                    }
                    if filteredFederal.count > 60 {
                        Text("+\(filteredFederal.count - 60) more — use search to narrow.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CivicTheme.quietInk)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("STATE", systemImage: "flag.fill", tint: DirectoryOfficial.Level.state.tint)
            ForEach(Array(store.stateDirectoryByCode.keys.sorted()), id: \.self) { code in
                if let list = store.stateDirectoryByCode[code], !list.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(code) · \(list.count) officials")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(CivicTheme.violet)
                        VStack(spacing: 8) {
                            ForEach(list.prefix(20)) { person in
                                officialRow(person)
                            }
                            if list.count > 20 {
                                Text("+\(list.count - 20) more — open via search.")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CivicTheme.quietInk)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private var filteredFederal: [DirectoryOfficial] {
        store.federalDirectory.filter { person in
            switch activeChamberFilter {
            case .all: break
            case .senate: if person.chamber != .senate { return false }
            case .house: if person.chamber != .house { return false }
            case .executive: if person.chamber != .executive { return false }
            }
            switch activePartyFilter {
            case .all: break
            case .democratic: if person.party?.lowercased().contains("democrat") != true { return false }
            case .republican: if person.party?.lowercased().contains("republican") != true { return false }
            case .independent: if person.party?.lowercased().contains("independent") != true { return false }
            case .other:
                let p = person.party?.lowercased() ?? ""
                if p.contains("democrat") || p.contains("republican") || p.contains("independent") { return false }
            }
            return true
        }
    }

    // MARK: - Row + helpers

    private func officialRow(_ person: DirectoryOfficial, accent: Bool = false) -> some View {
        Button {
            Haptics.selection()
            presented = person
        } label: {
            HStack(spacing: 12) {
                officialAvatar(person)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                            .lineLimit(1)
                        if !person.partyAbbreviation.isEmpty {
                            Text(person.partyAbbreviation)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(person.partyTint, in: Circle())
                        }
                        if store.isOfficialBookmarked(person.id) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(CivicTheme.amber)
                        }
                    }
                    Text("\(person.role) · \(person.displayDistrict)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if person.socials.any {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(10)
            .background(accent ? CivicTheme.amber.opacity(0.05) : CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent ? CivicTheme.amber.opacity(0.25) : CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func officialAvatar(_ person: DirectoryOfficial) -> some View {
        Group {
            if let urlString = person.photoURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder(person)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(person.partyTint.opacity(0.4), lineWidth: 1.5))
            } else {
                avatarPlaceholder(person)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(person.partyTint.opacity(0.4), lineWidth: 1.5))
            }
        }
    }

    private func avatarPlaceholder(_ person: DirectoryOfficial) -> some View {
        Circle()
            .fill(person.partyTint.opacity(0.18))
            .overlay {
                Text(initials(of: person.name))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(person.partyTint)
            }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "?" : combined
    }

    private func sectionLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
            Rectangle()
                .fill(tint.opacity(0.25))
                .frame(height: 1)
        }
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Search

    @State private var searchTask: Task<Void, Never>?

    private func debounceSearch(_ q: String) {
        searchTask?.cancel()
        if q.trimmingCharacters(in: .whitespaces).count < 2 {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            isSearching = true
            defer { isSearching = false }
            let results = await store.searchDirectory(q)
            if !Task.isCancelled {
                searchResults = results
            }
        }
    }
}
