import SwiftUI

struct HelpView: View {
    @Environment(CivicOSStore.self) private var store
    let askAssistant: (String) -> Void

    @State private var selectedCategory: ServiceCategory?
    @State private var showingNeeds = false
    @State private var showingEligibility = false
    @State private var showingDocuments = false
    @State private var selectedService: CivicService?

    private var visibleServices: [CivicService] {
        let services = store.prioritizedServices
        guard let selectedCategory else { return services }
        return services.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        needPicker

                        if store.profile == nil {
                            setLocationCard
                        } else {
                            readinessCard
                            matchedServicesBlock
                            documentCard
                            languageCard
                        }

                        servicesBlock
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNeeds) {
                ServiceNeedsSheet(initial: store.profile?.serviceNeeds ?? [])
                    .environment(store)
            }
            .sheet(isPresented: $showingEligibility) {
                EligibilityProfileSheet(profile: store.profile)
                    .environment(store)
            }
            .sheet(isPresented: $showingDocuments) {
                DocumentChecklistSheet()
                    .environment(store)
            }
            .sheet(item: $selectedService) { service in
                ServiceDetailSheet(service: service, askAssistant: askAssistant)
                    .environment(store)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Help")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
            Text("What do you need today?")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Find services, check fit, gather documents, and ask \(AppBrand.name) for the next step.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }

    private var needPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                needChip(title: "All", icon: "sparkles", tint: CivicTheme.cyan, selected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(ServiceCategory.allCases) { category in
                    needChip(title: category.label, icon: category.systemImage, tint: category.tint, selected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func needChip(title: String, icon: String, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(selected ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? tint : tint.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var setLocationCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Set your ZIP first", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                Text("A ZIP lets \(AppBrand.name) match programs and government actions to your area.")
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.mutedInk)
            }
        }
    }

    private var readinessCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Benefit profile")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text("\(store.serviceReadiness)% ready")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                    }
                    Spacer()
                    Button {
                        showingEligibility = true
                    } label: {
                        Text("Edit")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(CivicTheme.cyan.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ProgressView(value: Double(store.serviceReadiness), total: 100)
                    .tint(readinessTint)

                HStack(spacing: 8) {
                    Button {
                        showingNeeds = true
                    } label: {
                        miniAction("Needs", icon: "heart.text.square.fill", tint: CivicTheme.violet)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingDocuments = true
                    } label: {
                        miniAction("Docs", icon: "folder.fill", tint: CivicTheme.amber)
                    }
                    .buttonStyle(.plain)

                    Button {
                        askAssistant("I need help figuring out which public services I may qualify for. Ask me only the few details you need and cite official sources when possible.")
                    } label: {
                        miniAction("Ask", icon: "sparkles", tint: CivicTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var readinessTint: Color {
        if store.serviceReadiness >= 70 { return CivicTheme.green }
        if store.serviceReadiness >= 40 { return CivicTheme.amber }
        return CivicTheme.cyan
    }

    private func miniAction(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
    }

    @ViewBuilder
    private var matchedServicesBlock: some View {
        if !store.matchedServices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Best matches")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .textCase(.uppercase)
                    .tracking(0.5)
                ForEach(store.matchedServices.prefix(3)) { service in
                    ServiceRowCard(service: service, askAssistant: askAssistant) {
                        selectedService = service
                    }
                }
            }
        }
    }

    private var documentCard: some View {
        Button {
            showingDocuments = true
        } label: {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(CivicTheme.amber.opacity(0.15))
                        Image(systemName: "folder.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CivicTheme.amber)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Document checklist")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(documentSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var documentSubtitle: String {
        let count = store.profile?.preparedDocuments.count ?? 0
        if count == 0 { return "Mark the documents you already have ready" }
        return "\(count) document\(count == 1 ? "" : "s") ready for applications"
    }

    private var languageCard: some View {
        CivicGlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                        .fill(CivicTheme.green.opacity(0.15))
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CivicTheme.green)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Language")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(store.profile?.preferredLanguage.label ?? ResidentLanguage.english.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }

                Spacer()

                Button {
                    showingEligibility = true
                } label: {
                    Text("Change")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.green)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var servicesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedCategory?.label ?? "Service directory")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0.5)
            ForEach(visibleServices) { service in
                ServiceRowCard(service: service, askAssistant: askAssistant) {
                    selectedService = service
                }
            }
        }
    }
}

private struct ServiceRowCard: View {
    @Environment(CivicOSStore.self) private var store
    let service: CivicService
    let askAssistant: (String) -> Void
    let onOpen: () -> Void

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(service.category.tint.opacity(0.14))
                        Image(systemName: service.category.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(service.category.tint)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(service.provider)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }

                    Spacer()

                    RectBadge(text: "\(service.matchScore(for: store.profile))%", systemImage: "target", tint: service.category.tint)
                }

                Text(service.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                documentProgress

                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        Text("Details")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(service.category.tint)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(service.category.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    }
                    .buttonStyle(.plain)

                    Button {
                        askAssistant("Help me apply for \(service.title). My ZIP is \(store.profile?.zipCode ?? "not set"). Explain eligibility, documents, and the safest next step.")
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles")
                            Text("Ask")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var documentProgress: some View {
        let progress = service.documentProgress(for: store.profile)
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.amber)
            Text(progress.total == 0 ? "No documents listed" : "\(progress.ready)/\(progress.total) docs ready")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
            Text(service.freshness)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.smallRadius))
    }
}

private struct ServiceDetailSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let service: CivicService
    let askAssistant: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        CivicGlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                RectBadge(text: service.category.label, systemImage: service.category.systemImage, tint: service.category.tint)
                                Text(service.title)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(CivicTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(service.summary)
                                    .font(.system(size: 15))
                                    .lineSpacing(4)
                                    .foregroundStyle(CivicTheme.mutedInk)
                            }
                        }

                        detailSection(title: "Eligibility", icon: "checkmark.seal.fill", lines: [service.eligibility])
                        detailSection(title: "Steps", icon: "list.number", lines: service.applySteps)
                        detailSection(title: "Documents", icon: "folder.fill", lines: service.documents.map(\.label))
                        detailSection(title: "Source", icon: "link", lines: [service.sourceName, service.sourceURL])

                        Button {
                            askAssistant("Walk me through \(service.title) step by step. Use plain language, ask only necessary questions, and help me avoid missing deadlines.")
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Ask \(AppBrand.name) for a plan")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func detailSection(title: String, icon: String, lines: [String]) -> some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, systemImage: icon)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ServiceNeedsSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<ServiceCategory>

    init(initial: Set<ServiceCategory>) {
        _selected = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(ServiceCategory.allCases) { category in
                            Button {
                                Haptics.selection()
                                if selected.contains(category) {
                                    selected.remove(category)
                                } else {
                                    selected.insert(category)
                                }
                            } label: {
                                SelectableHelpRow(
                                    title: category.label,
                                    subtitle: category.prompt,
                                    icon: category.systemImage,
                                    tint: category.tint,
                                    selected: selected.contains(category)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Needs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.setServiceNeeds(selected)
                        Haptics.success()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct EligibilityProfileSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<EligibilitySignal>
    @State private var householdSize: HouseholdSize
    @State private var incomeBand: IncomeBand
    @State private var language: ResidentLanguage

    init(profile: UserProfile?) {
        _selected = State(initialValue: profile?.eligibilitySignals ?? [])
        _householdSize = State(initialValue: profile?.householdSize ?? .unknown)
        _incomeBand = State(initialValue: profile?.incomeBand ?? .unknown)
        _language = State(initialValue: profile?.preferredLanguage ?? .english)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        CivicGlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader(title: "Household", systemImage: "person.2.fill")
                                Picker("Household size", selection: $householdSize) {
                                    ForEach(HouseholdSize.allCases) { option in
                                        Text(option.label).tag(option)
                                    }
                                }
                                Picker("Income", selection: $incomeBand) {
                                    ForEach(IncomeBand.allCases) { option in
                                        Text(option.label).tag(option)
                                    }
                                }
                                Picker("Language", selection: $language) {
                                    ForEach(ResidentLanguage.allCases) { option in
                                        Text(option.label).tag(option)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Signals")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            ForEach(EligibilitySignal.allCases) { signal in
                                Button {
                                    Haptics.selection()
                                    if selected.contains(signal) {
                                        selected.remove(signal)
                                    } else {
                                        selected.insert(signal)
                                    }
                                } label: {
                                    SelectableHelpRow(
                                        title: signal.label,
                                        subtitle: "Used only to rank possible programs and explain fit.",
                                        icon: signal.systemImage,
                                        tint: CivicTheme.violet,
                                        selected: selected.contains(signal)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Benefit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.setEligibilitySignals(selected)
                        store.setHouseholdSize(householdSize)
                        store.setIncomeBand(incomeBand)
                        store.setPreferredLanguage(language)
                        Haptics.success()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct DocumentChecklistSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(CivicDocumentKind.allCases) { document in
                            Button {
                                Haptics.selection()
                                store.togglePreparedDocument(document)
                            } label: {
                                SelectableHelpRow(
                                    title: document.label,
                                    subtitle: "Mark ready when you know where this document is.",
                                    icon: document.systemImage,
                                    tint: CivicTheme.amber,
                                    selected: store.profile?.preparedDocuments.contains(document) == true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct SelectableHelpRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let selected: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .fill(tint.opacity(selected ? 0.18 : 0.10))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(CivicTheme.mutedInk)
            }

            Spacer()

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? tint : CivicTheme.quietInk)
        }
        .padding(13)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                .stroke(selected ? tint.opacity(0.35) : CivicTheme.hairline, lineWidth: selected ? 1.5 : 1)
        )
        .shadow(color: CivicTheme.cardShadow, radius: 8, x: 0, y: 3)
    }
}

#Preview {
    HelpView { _ in }
        .environment(CivicOSStore(settings: AppSettings(showSampleIssues: true, hasCompletedOnboarding: true)))
}
