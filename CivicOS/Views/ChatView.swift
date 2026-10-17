import SwiftUI

struct ChatView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool
    /// True when the user has dragged the transcript up off the bottom.
    /// While true we stop hijacking their scroll with auto-pin-to-bottom.
    @State private var userScrolledUp: Bool = false

    // Seamless voice mode: tap mic → immediately listening, silence auto-
    // submits, assistant reply streams in chat AND gets spoken via TTS.
    // No sheet. No tap-to-send. No tap-to-stop-recording.
    @StateObject private var voice = SpeechVoiceController()
    /// ElevenLabs-backed TTS for the assistant's spoken reply. Same
    /// pipeline as ReadAloudButton — falls back to on-device TTS if the
    /// backend / ElevenLabs is unavailable.
    @State private var ttsPlayer = ReadAloudPlayer()
    @State private var silenceTask: Task<Void, Never>?
    /// True when the last user message came from voice — used to gate
    /// whether to TTS-speak the assistant's reply when it finishes.
    @State private var lastSendWasVoice: Bool = false
    /// True from the moment we kick off a voice send until streaming ends,
    /// so the silence-watcher doesn't fire again on stale transcript edits.
    @State private var voiceSendInFlight: Bool = false
    /// How long of "no new transcript" we wait before auto-submitting (sec).
    private let silenceThreshold: Double = 1.5

    @State private var showUrlAnalyzer: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    BackendOfflineBanner()
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)

                    if store.chatMessages.isEmpty {
                        emptyState
                            .padding(.horizontal, 18)
                            .frame(maxHeight: .infinity)
                    } else {
                        transcript
                    }
                }
            }
            // Tap-anywhere-to-dismiss. simultaneousGesture lets buttons and
            // text fields still receive their own tap — this just runs
            // alongside and pulls focus off the composer.
            .simultaneousGesture(
                TapGesture().onEnded {
                    if inputFocused { inputFocused = false }
                }
            )
            // Render the composer as a bottom safe-area inset so iOS pushes
            // it up above the keyboard instead of letting the keyboard slide
            // over the send button.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationBarHidden(true)
            .onAppear(perform: sendQueuedAssistantPromptIfNeeded)
            .onChange(of: store.pendingAssistantPrompt) { _, _ in
                sendQueuedAssistantPromptIfNeeded()
            }
            .onChange(of: voice.transcript) { _, _ in
                // Every time partial transcript grows, restart the silence
                // countdown. When the user stops talking long enough, the
                // task fires and we auto-submit.
                guard voice.isListening, !voiceSendInFlight else { return }
                scheduleSilenceSubmit()
            }
            .sheet(isPresented: $showUrlAnalyzer) {
                UrlAnalyzeView()
                    .environment(store)
            }
            .onChange(of: store.isChatStreaming) { wasStreaming, nowStreaming in
                // When the assistant finishes streaming a reply triggered
                // from voice input, speak the reply via the same backend
                // ElevenLabs pipeline the 5-min audio brief uses.
                guard wasStreaming, !nowStreaming, lastSendWasVoice else { return }
                lastSendWasVoice = false
                voiceSendInFlight = false
                if let last = store.chatMessages.last,
                   last.role == .assistant, !last.content.isEmpty {
                    let reply = last.content
                    Task {
                        try? await ttsPlayer.speak(
                            text: reply,
                            voiceId: nil,
                            modelId: nil,
                            service: store.speechService
                        )
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assistant")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .textCase(.uppercase)
                Text("Ask your AI")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
            }
            Spacer()
            Button {
                Haptics.selection()
                showUrlAnalyzer = true
            } label: {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                    .padding(10)
                    .background(CivicTheme.violet.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paste a URL for Athen to read")
            if ttsPlayer.isPlaying || ttsPlayer.isLoading {
                Button {
                    Haptics.selection()
                    ttsPlayer.stop()
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CivicTheme.red)
                        .padding(10)
                        .background(CivicTheme.red.opacity(0.12), in: Circle())
                        .overlay(Circle().stroke(CivicTheme.red.opacity(0.20), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop speaking")
            }
            if !store.chatMessages.isEmpty {
                Button {
                    store.resetChat()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .padding(10)
                        .background(CivicTheme.panelElevated, in: Circle())
                        .overlay(Circle().stroke(CivicTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.chatMessages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    if let err = store.chatError {
                        ErrorBubble(text: err)
                            .id("error")
                    }
                    // Invisible sentinel — when it's visible, the user is at
                    // the bottom and we keep auto-scrolling. When it scrolls
                    // off-screen (user dragged up to read history), we stop
                    // hijacking their scroll.
                    Color.clear
                        .frame(height: 8)
                        .id("__bottom")
                        .onAppear { userScrolledUp = false }
                        .onDisappear { userScrolledUp = true }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 6)
            }
            // Swipe down on the message list to interactively drop the keyboard.
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.chatMessages.last?.content) { _, _ in
                guard !userScrolledUp else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.chatMessages.count) { _, _ in
                // A new message bubble always wins — either it's the user's
                // own send (they want to see it) or the start of a fresh
                // assistant turn. Reset the manual-scroll flag.
                userScrolledUp = false
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if userScrolledUp {
                    jumpToLatestButton { proxy.scrollTo("__bottom", anchor: .bottom) }
                        .padding(.bottom, 12)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: userScrolledUp)
                }
            }
        }
    }

    /// Floating chip that appears when the user has dragged up while the
    /// assistant is still streaming. Tap to jump back to the latest token.
    private func jumpToLatestButton(action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.25)) { action() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(store.isChatStreaming ? "Jump to latest" : "Back to bottom")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(CivicTheme.violet, in: Capsule())
            .shadow(color: CivicTheme.violet.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to latest message")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                Text("I know your reps, the items in your feed, and what you've filed.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ask me to translate an item, find services, plan an outreach campaign, or figure out who to call.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
            .padding(18)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                    .stroke(CivicTheme.hairline, lineWidth: 1)
            )
            .shadow(color: CivicTheme.cardShadow, radius: 18, x: 0, y: 8)

            Text("Try")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(suggestionPrompts, id: \.self) { prompt in
                Button {
                    draft = prompt
                    inputFocused = true
                } label: {
                    HStack {
                        Text(prompt)
                            .font(.system(size: 14, weight: .medium))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(CivicTheme.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                    .padding(14)
                    .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .stroke(CivicTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var suggestionPrompts: [String] {
        if store.profile == nil {
            return [
                "What does this app do?",
                "How do I set my location?",
                "What can you help me with?"
            ]
        }
        return [
            "What should I act on first, and why?",
            "What public services might I qualify for?",
            "Explain the top issue like I'm texting a neighbor.",
            "Draft an AI brief for the feed with both sides."
        ]
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                Haptics.selection()
                toggleVoice()
            } label: {
                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(voice.isListening ? .white : CivicTheme.cyan)
                    .frame(width: 42, height: 42)
                    .background(
                        Group {
                            if voice.isListening {
                                Circle().fill(CivicTheme.red)
                            } else {
                                Circle().fill(CivicTheme.cyan.opacity(0.12))
                            }
                        }
                    )
                    .overlay(Circle().stroke(
                        voice.isListening ? CivicTheme.red.opacity(0.4) : CivicTheme.cyan.opacity(0.20),
                        lineWidth: 1
                    ))
                    .scaleEffect(voice.isListening ? 1.06 : 1.0)
                    .animation(
                        voice.isListening
                            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                            : .default,
                        value: voice.isListening
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isListening ? "Stop listening" : "Talk to Athen")

            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(composerPlaceholder)
                        .font(.system(size: 15))
                        .foregroundStyle(CivicTheme.quietInk)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .font(.system(size: 15))
                    .foregroundStyle(CivicTheme.ink)
                    // Collapsed at rest so the message list gets the room;
                    // expands when focused or while typing. After tapping
                    // send we defocus + clear, so the box snaps back to one
                    // line and the new output gets the screen.
                    .frame(minHeight: 36, maxHeight: inputMaxHeight)
                    .animation(.easeInOut(duration: 0.18), value: inputMaxHeight)
                    .tint(CivicTheme.cyan)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .stroke(CivicTheme.hairline, lineWidth: 1)
            )

            Button(action: send) {
                Image(systemName: store.isChatStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(sendButtonColor, in: Circle())
                    .shadow(color: sendButtonColor.opacity(0.3), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!store.isChatStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            CivicTheme.panel
                .overlay(
                    Rectangle()
                        .fill(CivicTheme.hairline)
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }

    private var sendButtonColor: Color {
        if store.isChatStreaming { return CivicTheme.red }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CivicTheme.quietInk : CivicTheme.cyan
    }

    /// One-line at rest; grows to ~5 lines when focused or typing.
    private var inputMaxHeight: CGFloat {
        if inputFocused || !draft.isEmpty { return 140 }
        return 36
    }

    private func send() {
        if store.isChatStreaming {
            store.cancelChatStream()
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // Collapse the composer so the streaming reply gets the room.
        inputFocused = false
        // Typed send — don't TTS-speak the response.
        lastSendWasVoice = false
        store.sendChat(text)
    }

    private func sendQueuedAssistantPromptIfNeeded() {
        guard !store.isChatStreaming,
              let prompt = store.consumePendingAssistantPrompt()
        else { return }
        draft = ""
        lastSendWasVoice = false
        store.sendChat(prompt)
    }

    // MARK: - Voice flow

    private var composerPlaceholder: String {
        if voice.isListening {
            let partial = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            return partial.isEmpty ? "Listening…" : partial
        }
        if ttsPlayer.isLoading { return "Loading voice…" }
        if ttsPlayer.isPlaying { return "Speaking…" }
        if store.isChatStreaming { return "Streaming…" }
        return "Ask \(AppBrand.name)"
    }

    private func toggleVoice() {
        if voice.isListening {
            // Tap-while-listening = abort, drop the transcript, no submit.
            silenceTask?.cancel()
            silenceTask = nil
            voice.stopListening()
            return
        }
        if ttsPlayer.isPlaying || ttsPlayer.isLoading { ttsPlayer.stop() }
        if store.isChatStreaming { store.cancelChatStream() }
        inputFocused = false
        draft = ""
        voiceSendInFlight = false
        voice.requestAndStart()
    }

    /// Reset the silence countdown each time we see a new partial transcript.
    /// When the countdown elapses with no further updates → submit.
    private func scheduleSilenceSubmit() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(silenceThreshold * 1_000_000_000))
            guard !Task.isCancelled, voice.isListening, !voiceSendInFlight else { return }
            commitVoiceTranscript()
        }
    }

    private func commitVoiceTranscript() {
        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        voice.stopListening()
        guard !text.isEmpty else { return }
        voiceSendInFlight = true
        lastSendWasVoice = true
        store.sendChat(text)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 36) }

            VStack(alignment: .leading, spacing: 6) {
                if message.role == .assistant {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.violet)
                        Text("Assistant")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CivicTheme.violet)
                            .textCase(.uppercase)
                    }
                }

                if message.role == .assistant && !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(message.toolCalls.enumerated()), id: \.offset) { _, call in
                            ToolCallChip(call: call)
                        }
                    }
                }

                if message.role == .assistant {
                    if message.isStreaming && message.content.isEmpty && message.toolCalls.isEmpty {
                        TypingIndicator()
                    } else {
                        MarkdownText(
                            raw: message.content,
                            isStreaming: message.isStreaming,
                            textColor: CivicTheme.ink,
                            accent: CivicTheme.cyan
                        )
                        .textSelection(.enabled)
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(message.role == .user ? CivicTheme.cyan : CivicTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                    .stroke(message.role == .user ? Color.clear : CivicTheme.hairline, lineWidth: 1)
            )
            .shadow(color: message.role == .user ? CivicTheme.cyan.opacity(0.20) : CivicTheme.cardShadow, radius: 10, x: 0, y: 4)

            if message.role == .assistant { Spacer(minLength: 36) }
        }
    }

}

/// Inline chip showing one tool the assistant called during this turn —
/// e.g. "🔍 Searching the web — philadelphia mayor 2026 (8 results)".
/// Renders as a small purple pill above the response body. The status flips
/// from spinner → check as the tool completes.
private struct ToolCallChip: View {
    let call: ChatToolCall

    var body: some View {
        HStack(spacing: 6) {
            switch call.status {
            case .running:
                ProgressView()
                    .controlSize(.mini)
                    .tint(CivicTheme.violet)
                    .frame(width: 12, height: 12)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.red)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(CivicTheme.violet.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(CivicTheme.violet.opacity(0.25), lineWidth: 0.5))
    }

    private var label: String {
        let prefix: String
        switch call.name {
        case "web_search": prefix = call.status == .running ? "Searching the web" : "Searched the web"
        default:           prefix = call.status == .running ? "Running \(call.name)" : "Ran \(call.name)"
        }
        if let summary = call.summary, !summary.isEmpty {
            return "\(prefix) — \(summary)"
        }
        return prefix
    }
}

/// Three-dot pulsing indicator shown while the assistant is composing the
/// first token. Replaces a static "…" that read as broken.
private struct TypingIndicator: View {
    @State private var phase: Int = 0
    private let dots = 3
    private let interval: TimeInterval = 0.35

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<dots, id: \.self) { index in
                Circle()
                    .fill(CivicTheme.violet)
                    .frame(width: 7, height: 7)
                    .opacity(phase == index ? 1 : 0.3)
                    .scaleEffect(phase == index ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: interval / 1.8), value: phase)
            }
            Text("Athen is thinking")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .padding(.leading, 6)
        }
        .padding(.vertical, 4)
        .onAppear { cycle() }
    }

    private func cycle() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                phase = (phase + 1) % dots
            }
        }
    }
}

private struct ErrorBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CivicTheme.red)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CivicTheme.red)
        }
        .padding(12)
        .background(CivicTheme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: CivicTheme.smallRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.smallRadius)
                .stroke(CivicTheme.red.opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview {
    ChatView()
        .environment(CivicOSStore())
}
