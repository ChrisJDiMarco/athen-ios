import SwiftUI

/// "How does this affect me?" sheet. Opens from any issue detail.
/// First-run captures the user's financial / household snapshot once; every
/// subsequent open reuses it. Claude generates a personalized impact
/// estimate that anchors to the user's own numbers.
struct PersonalImpactSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let issueId: String

    @State private var draft: CivicImpactProfile = .empty
    @State private var loaded: Bool = false
    @State private var isEstimating: Bool = false
    @State private var result: CivicPersonalImpact?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        if let result {
                            resultCard(result)
                            Divider().overlay(CivicTheme.hairline)
                        }
                        profileForm
                        estimateButton
                        if let err = errorMessage { errorBanner(err) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("How does this affect me?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .task {
                if !loaded {
                    draft = store.impactProfile
                    loaded = true
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("PERSONAL IMPACT", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("Make it concrete for me")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Give Athen a few quick facts and you'll get a real estimate of how this affects YOU — not the abstract version. Saved on-device; never sent except when you tap Estimate.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var profileForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("YOUR SNAPSHOT")

            currencyField("Monthly rent / mortgage", binding: Binding(
                get: { draft.monthlyRent },
                set: { draft.monthlyRent = $0 }
            ), placeholder: "1800")

            currencyField("Annual household income", binding: Binding(
                get: { draft.annualIncome },
                set: { draft.annualIncome = $0 }
            ), placeholder: "75000")

            intField("Household size", binding: Binding(
                get: { draft.householdSize },
                set: { draft.householdSize = $0 }
            ), placeholder: "2")

            toggleField("Kids in public school", isOn: Binding(
                get: { draft.hasKidsInPublicSchool ?? false },
                set: { draft.hasKidsInPublicSchool = $0 }
            ))

            toggleField("I own my home", isOn: Binding(
                get: { draft.homeOwner ?? false },
                set: { draft.homeOwner = $0 }
            ))

            VStack(alignment: .leading, spacing: 6) {
                Text("Daily commute")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                Picker("Commute mode", selection: Binding(
                    get: { draft.commuteMode ?? .car },
                    set: { draft.commuteMode = $0 }
                )) {
                    ForEach(CivicImpactProfile.CommuteMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var estimateButton: some View {
        Button {
            Haptics.selection()
            // Persist the snapshot before each estimate so re-opens load
            // exactly what the user just typed.
            store.impactProfile = draft
            Task { await estimate() }
        } label: {
            HStack(spacing: 7) {
                if isEstimating {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "function")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(isEstimating ? "Estimating…" : "Estimate impact on me")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: CivicTheme.violet.opacity(0.25), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isEstimating)
    }

    private func resultCard(_ result: CivicPersonalImpact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("ESTIMATE FOR YOU")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.violet)
                Spacer()
                Text(result.confidence.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(confidenceColor(result.confidence), in: Capsule())
                AIDisclosureChip(surface: .brief, compact: true)
            }
            Text(result.headline)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !result.details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(result.details.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5, weight: .bold))
                                .foregroundStyle(CivicTheme.violet)
                                .padding(.top, 7)
                            Text(line)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !result.missingInputs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To sharpen this estimate, add:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                    ForEach(Array(result.missingInputs.enumerated()), id: \.offset) { _, line in
                        Text("· \(line)")
                            .font(.system(size: 11))
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [CivicTheme.violet.opacity(0.08), CivicTheme.cyan.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: RoundedRectangle(cornerRadius: 14),
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CivicTheme.red)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func confidenceColor(_ c: CivicPersonalImpact.Confidence) -> Color {
        switch c {
        case .estimate: CivicTheme.green
        case .roughEstimate: CivicTheme.amber
        case .speculative: CivicTheme.quietInk
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(CivicTheme.mutedInk)
    }

    private func currencyField(_ label: String, binding: Binding<Double?>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            HStack(spacing: 4) {
                Text("$")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
                TextField(placeholder, value: binding, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(10)
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private func intField(_ label: String, binding: Binding<Int?>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            TextField(placeholder, value: binding, format: .number)
                .keyboardType(.numberPad)
                .font(.system(size: 14, weight: .medium))
                .padding(10)
                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private func toggleField(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CivicTheme.ink)
            .tint(CivicTheme.violet)
    }

    private func estimate() async {
        isEstimating = true
        errorMessage = nil
        defer { isEstimating = false }
        if let r = await store.estimatePersonalImpact(for: issueId) {
            result = r
        } else {
            errorMessage = "Couldn't generate an estimate right now. Try again in a moment."
        }
    }
}
