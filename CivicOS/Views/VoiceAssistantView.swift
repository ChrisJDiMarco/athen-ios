import SwiftUI

struct VoiceAssistantView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechVoiceController()
    @State private var voiceSession: VoiceSession?
    @State private var isLoadingSession = true
    @State private var sessionError: String?
    @State private var autoReadReplies = true
    @State private var lastSpokenAssistantID: ChatMessage.ID?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        voiceStatusCard
                        voiceOrb
                        transcriptCard
                        controls
                        toolCard
                    }
                    .padding(20)
                    .padding(.bottom, 28)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        speech.stopListening()
                        speech.stopSpeaking()
                        dismiss()
                    }
                    .foregroundStyle(CivicTheme.mutedInk)
                }
            }
            .task {
                await loadVoiceSession()
            }
            .onChange(of: store.chatMessages.last?.isStreaming) { _, _ in
                readLatestAssistantIfReady()
            }
            .onChange(of: store.chatMessages.last?.content) { _, _ in
                readLatestAssistantIfReady()
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Voice Mode")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
            Text("Talk to \(AppBrand.name)")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Ask for a daily brief, a plain-English explanation, a service match, or a filing draft readback.")
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }

    private var voiceStatusCard: some View {
        CivicGlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: voiceSession?.configured == true ? "waveform.circle.fill" : "waveform.badge.mic")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(voiceSession?.configured == true ? CivicTheme.green : CivicTheme.cyan)
                    .frame(width: 42, height: 42)
                    .background((voiceSession?.configured == true ? CivicTheme.green : CivicTheme.cyan).opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(statusCopy)
                        .font(.system(size: 13, weight: .medium))
                        .lineSpacing(2)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var voiceOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (speech.isListening ? CivicTheme.green : CivicTheme.cyan).opacity(0.85),
                            CivicTheme.violet.opacity(0.42),
                            CivicTheme.panelElevated.opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 145
                    )
                )
                .frame(width: 220, height: 220)
                .blur(radius: 0.2)

            Circle()
                .stroke(.white.opacity(0.45), lineWidth: 1)
                .frame(width: speech.isListening ? 178 : 150, height: speech.isListening ? 178 : 150)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: speech.isListening)

            VStack(spacing: 8) {
                Image(systemName: speech.isListening ? "mic.fill" : "sparkles")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                Text(speech.state.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .textCase(.uppercase)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var transcriptCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Transcript", systemImage: "quote.bubble.fill")
                Text(speech.transcript.isEmpty ? "Tap the microphone and speak naturally." : speech.transcript)
                    .font(.system(size: 16, weight: speech.transcript.isEmpty ? .regular : .semibold))
                    .foregroundStyle(speech.transcript.isEmpty ? CivicTheme.quietInk : CivicTheme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = speech.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.red)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    speech.toggleListening()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(speech.isListening ? "Stop" : "Speak")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(speech.isListening ? CivicTheme.red : CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    sendTranscript()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Send")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(canSendTranscript ? .white : CivicTheme.quietInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canSendTranscript ? CivicTheme.violet : CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                }
                .buttonStyle(.plain)
                .disabled(!canSendTranscript)
            }

            Toggle(isOn: $autoReadReplies) {
                Label("Read replies aloud", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
            }
            .tint(CivicTheme.cyan)
            .padding(13)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .stroke(CivicTheme.hairline, lineWidth: 1)
            )
        }
    }

    private var toolCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Voice tools", systemImage: "wrench.and.screwdriver.fill")
                ForEach(voiceSession?.tools ?? MockVoiceService.previewTools) { tool in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: tool.name))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                            .frame(width: 28, height: 28)
                            .background(CivicTheme.cyan.opacity(0.11), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: tool.name))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Text("\(tool.method) \(tool.path)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CivicTheme.quietInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var statusTitle: String {
        if isLoadingSession { return "Checking ElevenLabs" }
        if voiceSession?.configured == true { return "ElevenLabs agent ready" }
        if sessionError != nil { return "Voice backend unavailable" }
        return "Native voice fallback"
    }

    private var statusCopy: String {
        if let sessionError { return sessionError }
        if voiceSession?.configured == true {
            return "The backend minted a signed ElevenLabs session and exposes Athen's civic tools for the agent."
        }
        return voiceSession?.fallbackReason ?? "You can still dictate to Athen and have replies read aloud."
    }

    private var canSendTranscript: Bool {
        !speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isChatStreaming
    }

    private func loadVoiceSession() async {
        isLoadingSession = true
        sessionError = nil
        do {
            voiceSession = try await store.fetchVoiceSession()
        } catch {
            sessionError = (error as? LocalizedError)?.errorDescription ?? "Could not reach the voice session endpoint."
        }
        isLoadingSession = false
    }

    private func sendTranscript() {
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        speech.stopListening()
        speech.transcript = ""
        store.sendChat(text)
    }

    private func readLatestAssistantIfReady() {
        guard autoReadReplies,
              let message = store.chatMessages.last(where: { $0.role == .assistant }),
              !message.isStreaming,
              !message.content.isEmpty,
              message.id != lastSpokenAssistantID
        else { return }
        lastSpokenAssistantID = message.id
        speech.speak(message.content)
    }

    private func icon(for name: String) -> String {
        switch name {
        case "getDailyBrief": "sun.max.fill"
        case "explainIssue": "doc.text.magnifyingglass"
        case "matchServices": "heart.text.square.fill"
        case "draftFiling": "square.and.pencil"
        case "readDraftBack": "speaker.wave.2.fill"
        default: "wrench.fill"
        }
    }

    private func label(for name: String) -> String {
        switch name {
        case "getDailyBrief": "Daily brief"
        case "explainIssue": "Explain issue"
        case "matchServices": "Match services"
        case "draftFiling": "Draft filing"
        case "readDraftBack": "Read draft back"
        default: name
        }
    }
}

private extension MockVoiceService {
    static var previewTools: [VoiceSession.VoiceTool] {
        [
            .init(name: "getDailyBrief", method: "GET", path: "/v1/voice/tools/daily-brief"),
            .init(name: "explainIssue", method: "GET", path: "/v1/voice/tools/explain-issue"),
            .init(name: "matchServices", method: "GET", path: "/v1/voice/tools/service-match"),
            .init(name: "draftFiling", method: "POST", path: "/v1/voice/tools/draft-filing"),
            .init(name: "readDraftBack", method: "POST", path: "/v1/voice/tools/read-draft-back")
        ]
    }
}

#Preview {
    VoiceAssistantView()
        .environment(CivicOSStore(settings: AppSettings(showSampleIssues: true, hasCompletedOnboarding: true)))
}
