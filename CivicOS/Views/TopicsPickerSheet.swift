import SwiftUI

struct TopicsPickerSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<CivicTopic>

    init(initial: Set<CivicTopic>) {
        _selection = State(initialValue: initial)
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CivicTopic.allCases) { topic in
                            TopicChip(topic: topic, isSelected: selection.contains(topic)) {
                                toggle(topic)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                saveButton
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your interests")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Pick the topics you care most about. We'll prioritize matching items in your feed. Federal items always stay visible.")
                .font(.system(size: 14))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveButton: some View {
        Button {
            store.setInterests(selection)
            dismiss()
        } label: {
            HStack {
                Text(selection.isEmpty ? "Skip" : "Save \(selection.count) interest\(selection.count == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .shadow(color: CivicTheme.cyan.opacity(0.30), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ topic: CivicTopic) {
        if selection.contains(topic) {
            selection.remove(topic)
        } else {
            selection.insert(topic)
        }
    }
}

private struct TopicChip: View {
    let topic: CivicTopic
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: topic.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : topic.tint)
                Text(topic.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : CivicTheme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? topic.tint : CivicTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .stroke(isSelected ? Color.clear : CivicTheme.hairline, lineWidth: 1)
            )
            .shadow(color: isSelected ? topic.tint.opacity(0.25) : CivicTheme.cardShadow, radius: isSelected ? 10 : 4, x: 0, y: isSelected ? 4 : 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TopicsPickerSheet(initial: [])
        .environment(CivicOSStore())
}
