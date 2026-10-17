import SwiftUI

/// Hub for the user's saved searches. Reporters, Hill staff, and engaged
/// citizens all use this surface — what varies is whose keywords they
/// track. Open from You tab.
struct SavedSearchesView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingComposer: Bool = false
    @State private var editingSearch: CivicSavedSearch?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if store.isLoadingSavedSearches && store.savedSearches.isEmpty {
                            loadingCard
                        } else if store.savedSearches.isEmpty {
                            emptyState
                        } else {
                            ForEach(store.savedSearches) { search in
                                row(search)
                            }
                        }
                        if let err = store.lastSavedSearchError {
                            errorBanner(err)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Saved searches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        showingComposer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                }
            }
            .task { await store.loadSavedSearches() }
            .sheet(isPresented: $showingComposer) {
                SavedSearchComposer { name, query, scope, stateCode, alerts in
                    Task {
                        _ = await store.createSavedSearch(
                            name: name,
                            query: query,
                            scope: scope,
                            stateCode: stateCode,
                            alertsEnabled: alerts,
                        )
                    }
                }
                .environment(store)
            }
            .sheet(item: $editingSearch) { search in
                SavedSearchComposer(initial: search) { name, query, scope, stateCode, alerts in
                    Task {
                        var patch = SavedSearchPatch()
                        patch.name = name
                        patch.query = query
                        patch.scope = scope
                        patch.stateCode = stateCode
                        patch.alertsEnabled = alerts
                        await store.updateSavedSearch(id: search.id, patch: patch)
                    }
                }
                .environment(store)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("RADAR", systemImage: "scope")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("Saved searches")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Track keywords, scopes, or whatever you care about. When something new matches, Athen drops it in your inbox.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(CivicTheme.violet)
            Text("Loading saved searches…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No saved searches yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Try one of these to start:")
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.mutedInk)
            ForEach(starterIdeas, id: \.0) { idea in
                Button {
                    Haptics.selection()
                    Task {
                        _ = await store.createSavedSearch(
                            name: idea.0,
                            query: idea.1,
                            scope: .any,
                            stateCode: nil,
                            alertsEnabled: true,
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.0)
                                .font(.system(size: 13, weight: .bold))
                            Text("\"\(idea.1)\"")
                                .font(.system(size: 11))
                                .foregroundStyle(CivicTheme.mutedInk)
                        }
                        Spacer()
                    }
                    .foregroundStyle(CivicTheme.violet)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(CivicTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var starterIdeas: [(String, String)] {
        [
            ("Housing watchlist", "housing"),
            ("Education bills", "education"),
            ("Transit deadlines", "transit"),
        ]
    }

    private func row(_ search: CivicSavedSearch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: search.alertsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(search.alertsEnabled ? CivicTheme.violet : CivicTheme.quietInk)
                    .frame(width: 28, height: 28)
                    .background(
                        (search.alertsEnabled ? CivicTheme.violet : CivicTheme.quietInk).opacity(0.10),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(search.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    HStack(spacing: 6) {
                        Text("\"\(search.query)\"")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(CivicTheme.quietInk)
                        Text(search.scope.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                }
                Spacer()
                if let n = search.currentMatchCount {
                    Text("\(n)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(n > 0 ? .white : CivicTheme.quietInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(n > 0 ? CivicTheme.violet : CivicTheme.panelElevated, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    editingSearch = search
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.selection()
                    Task {
                        var patch = SavedSearchPatch()
                        patch.alertsEnabled = !search.alertsEnabled
                        await store.updateSavedSearch(id: search.id, patch: patch)
                    }
                } label: {
                    Label(search.alertsEnabled ? "Mute" : "Alert", systemImage: search.alertsEnabled ? "bell.slash.fill" : "bell.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(search.alertsEnabled ? CivicTheme.quietInk : CivicTheme.violet)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background((search.alertsEnabled ? CivicTheme.quietInk : CivicTheme.violet).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.selection()
                    Task { await store.deleteSavedSearch(id: search.id) }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.red)
                        .frame(width: 38, height: 34)
                        .background(CivicTheme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(CivicTheme.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Composer (create + edit)

private struct SavedSearchComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CivicOSStore.self) private var store

    let initial: CivicSavedSearch?
    let onSubmit: (String, String, CivicSavedSearch.Scope, String?, Bool) -> Void

    @State private var name: String
    @State private var query: String
    @State private var scope: CivicSavedSearch.Scope
    @State private var stateCode: String
    @State private var alertsEnabled: Bool

    init(
        initial: CivicSavedSearch? = nil,
        onSubmit: @escaping (String, String, CivicSavedSearch.Scope, String?, Bool) -> Void,
    ) {
        self.initial = initial
        self.onSubmit = onSubmit
        _name = State(initialValue: initial?.name ?? "")
        _query = State(initialValue: initial?.query ?? "")
        _scope = State(initialValue: initial?.scope ?? .any)
        _stateCode = State(initialValue: initial?.stateCode ?? "")
        _alertsEnabled = State(initialValue: initial?.alertsEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name this search") {
                    TextField("e.g. Housing on my block", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Keywords") {
                    TextField("e.g. short-term rentals", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Scope") {
                    Picker("Scope", selection: $scope) {
                        ForEach(CivicSavedSearch.Scope.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    if scope == .state {
                        TextField("State code (e.g. PA)", text: $stateCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Toggle("Alert me when there are new matches", isOn: $alertsEnabled)
                        .tint(CivicTheme.violet)
                }
            }
            .navigationTitle(initial == nil ? "New saved search" : "Edit search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedQuery.isEmpty else { return }
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = trimmedName.isEmpty ? trimmedQuery : trimmedName
                        let codeTrimmed = stateCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        let finalCode = (scope == .state && codeTrimmed.count == 2) ? codeTrimmed : nil
                        onSubmit(finalName, trimmedQuery, scope, finalCode, alertsEnabled)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(CivicTheme.cyan)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
