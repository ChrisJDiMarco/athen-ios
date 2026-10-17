import SwiftUI

/// "Ask Athen anything" search bar that lives at the top of Home.
///
/// - Tap the text area → keyboard opens, user types their question
/// - Tap the mic → on-device speech-to-text fills the field as they speak
/// - Hit Return or the arrow button → sends to Assistant
///
/// The voice path uses Apple's Speech framework via SpeechVoiceController,
/// which requires NSSpeechRecognitionUsageDescription + NSMicrophoneUsageDescription
/// (already in Info.plist).
struct GlobalSearchBar: View {
    @Binding var text: String
    let onSubmit: () -> Void

    @StateObject private var speech = SpeechVoiceController()
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CivicTheme.violet)

            TextField(placeholderText, text: $text, axis: .horizontal)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CivicTheme.ink)
                .submitLabel(.send)
                .focused($focused)
                .onSubmit(onSubmit)
                .onChange(of: speech.transcript) { _, newValue in
                    // Live-mirror the spoken transcript into the text field
                    // so the user sees what we heard.
                    if !newValue.isEmpty { text = newValue }
                }

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send question to Assistant")
            } else {
                Button(action: toggleVoice) {
                    Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(speech.isListening ? CivicTheme.red : CivicTheme.violet)
                        .frame(width: 28, height: 28)
                        .background(
                            (speech.isListening ? CivicTheme.red : CivicTheme.violet)
                                .opacity(speech.isListening ? 0.16 : 0.10),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isListening ? "Stop voice input" : "Voice input")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(focused ? CivicTheme.violet.opacity(0.45) : CivicTheme.hairline, lineWidth: focused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: focused)
    }

    private var placeholderText: String {
        if speech.isListening {
            return "Listening… speak now"
        }
        return "Ask Athen anything…"
    }

    private func toggleVoice() {
        Haptics.selection()
        if speech.isListening {
            speech.stopListening()
        } else {
            // Defocus the text field so the system mic indicator is the
            // only active input UI — avoids double-input weirdness.
            focused = false
            speech.requestAndStart()
        }
    }
}
