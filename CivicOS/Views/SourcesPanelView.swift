import SwiftUI

struct SourcesPanelView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        cadenceCard
                        searchField
                        if store.allSources.isEmpty {
                            emptyState
                        } else {
                            ForEach(groupedSources, id: \.scope) { group in
                                sourceGroup(group)
                            }
                        }
                        if let err = store.lastSourcesError {
                            errorCard(err)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                        .font(.system(size: 15, weight: .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await store.refreshSources() }
                        } label: {
                            Label("Refresh registry", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            store.enableAllSources()
                        } label: {
                            Label("Enable all", systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button {
                            Task { await store.runFullRefresh() }
                        } label: {
                            Label("Run orchestrator now", systemImage: "bolt.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                }
            }
            .task {
                if store.allSources.isEmpty {
                    await store.refreshSources()
                }
            }
            .refreshable {
                await store.refreshSources()
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header + cadence + search

    private var headerCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label("Data sources", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.cyan)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    Spacer()
                    if store.isRefreshingSources {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                Text("These are the upstream registries your backend pulls civic items from. Toggle one off to hide its items on this device — the backend keeps ingesting either way.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    statTile("\(store.allSources.count)", "Registered", CivicTheme.cyan)
                    statTile("\(store.enabledSources.count)", "On", CivicTheme.green)
                    statTile("\(store.settings.disabledSourceIDs.count)", "Off", CivicTheme.amber)
                }
            }
        }
    }

    private func statTile(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
    }

    private var cadenceCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Auto-refresh", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text("How often the app pulls fresh civic items from your backend. You can always trigger a manual refresh from the Home tab.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                Menu {
                    Picker("Refresh cadence", selection: Binding(
                        get: { store.settings.refreshInterval },
                        set: { store.setRefreshInterval($0) }
                    )) {
                        ForEach(RefreshInterval.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.violet)
                        Text(store.settings.refreshInterval.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .stroke(CivicTheme.hairline, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CivicTheme.quietInk)
            TextField("Search by name, jurisdiction, host", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 14))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CivicTheme.quietInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Filtered + grouped sources

    private var filteredSources: [CivicSourceDescriptor] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.allSources
        guard !term.isEmpty else { return all }
        return all.filter { source in
            source.name.lowercased().contains(term)
                || source.jurisdiction.lowercased().contains(term)
                || source.primaryHost.lowercased().contains(term)
                || source.allowedHosts.contains { $0.lowercased().contains(term) }
        }
    }

    private struct ScopedGroup: Identifiable {
        let scope: CivicSourceDescriptor.Scope
        var sources: [CivicSourceDescriptor]
        var id: String { scope.rawValue }
    }

    private var groupedSources: [ScopedGroup] {
        let order: [CivicSourceDescriptor.Scope] = [.federal, .state, .localPhilly, .unknown]
        let grouped = Dictionary(grouping: filteredSources, by: { $0.scope })
        return order.compactMap { scope in
            guard let entries = grouped[scope], !entries.isEmpty else { return nil }
            return ScopedGroup(scope: scope, sources: entries.sorted { $0.name < $1.name })
        }
    }

    @ViewBuilder
    private func sourceGroup(_ group: ScopedGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.scope.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(group.scope.tint)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Rectangle()
                    .fill(group.scope.tint.opacity(0.25))
                    .frame(height: 1)
            }
            VStack(spacing: 10) {
                ForEach(group.sources) { source in
                    sourceRow(source)
                }
            }
        }
    }

    private func sourceRow(_ source: CivicSourceDescriptor) -> some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(source.trustTier.tint.opacity(0.16))
                        Image(systemName: source.kind.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(source.trustTier.tint)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(source.jurisdiction)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: Binding(
                        get: { store.isSourceEnabled(source.id) },
                        set: { store.setSourceEnabled(source.id, enabled: $0) }
                    ))
                    .labelsHidden()
                    .tint(CivicTheme.cyan)
                }

                HStack(spacing: 6) {
                    RectBadge(text: source.trustTier.label, systemImage: "checkmark.shield.fill", tint: source.trustTier.tint)
                    RectBadge(text: source.kind.label, systemImage: source.kind.systemImage, tint: CivicTheme.cyan)
                    if let state = source.stateCode {
                        RectBadge(text: state, systemImage: "mappin.circle.fill", tint: CivicTheme.violet)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    detailRow(icon: "globe", text: source.primaryHost)
                    if let url = URL(string: source.url) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Open registry page")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(CivicTheme.cyan)
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.quietInk)
                        Text(source.issueCount == 0
                             ? "No issues ingested yet"
                             : "\(source.issueCount) issue\(source.issueCount == 1 ? "" : "s") ingested · last \(relativeLabel(for: source.lastUpdatedAt))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }
                }
            }
        }
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func relativeLabel(for date: Date?) -> String {
        guard let date else { return "never" }
        let elapsed = -date.timeIntervalSinceNow
        switch elapsed {
        case ..<60: return "just now"
        case ..<3600: return "\(max(1, Int(elapsed / 60)))m ago"
        case ..<86400: return "\(max(1, Int(elapsed / 3600)))h ago"
        default: return "\(max(1, Int(elapsed / 86400)))d ago"
        }
    }

    // MARK: - Empty + error states

    private var emptyState: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("No sources loaded", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.amber)
                Text("Connect a backend from Radar → profile → AI backend, then come back here. Source rosters live on the backend and are read from /v1/sources.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                Button {
                    Task { await store.refreshSources() }
                } label: {
                    Text("Try again")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        CivicGlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CivicTheme.red)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    SourcesPanelView()
        .environment(CivicOSStore())
}
