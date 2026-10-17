import AVFoundation
import SwiftUI

/// Compact "Listen / Stop" pill that streams ElevenLabs TTS for arbitrary text.
///
/// Drop into any detail view. Lazily instantiates an AVAudioPlayer for ElevenLabs
/// audio, falls back to AVSpeechSynthesizer (on-device voice) when the backend
/// returns the client-fallback payload (e.g. ELEVENLABS_API_KEY missing).
struct ReadAloudButton: View {
    let text: () -> String
    var voiceId: String? = nil
    var modelId: String? = nil
    var label: String = "Listen"
    var compact: Bool = false

    @Environment(CivicOSStore.self) private var store
    @State private var player = ReadAloudPlayer()
    @State private var error: String?

    var body: some View {
        Button {
            if player.isPlaying {
                player.stop()
            } else {
                Task { await speak() }
            }
        } label: {
            HStack(spacing: 8) {
                if player.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(CivicTheme.cyan)
                } else {
                    Image(systemName: player.isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                        .imageScale(.small)
                }
                if !compact {
                    Text(player.isPlaying ? "Stop" : (player.isLoading ? "Loading…" : label))
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 8 : 9)
            .background(
                Capsule(style: .continuous)
                    .fill(player.isPlaying ? CivicTheme.red.opacity(0.18) : CivicTheme.cyan.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(player.isPlaying ? CivicTheme.red.opacity(0.5) : CivicTheme.cyan.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(player.isPlaying ? CivicTheme.red : CivicTheme.cyan)
        }
        .buttonStyle(.plain)
        .disabled(player.isLoading)
        .alert("Could not play audio", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .onDisappear { player.stop() }
    }

    private func speak() async {
        let body = text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            try await player.speak(
                text: body,
                voiceId: voiceId,
                modelId: modelId,
                service: store.speechService
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class ReadAloudPlayer: NSObject, @preconcurrency AVAudioPlayerDelegate, @preconcurrency AVSpeechSynthesizerDelegate {
    private(set) var isLoading: Bool = false
    private(set) var isPlaying: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying = false
        isLoading = false
    }

    func speak(text: String, voiceId: String?, modelId: String?, service: SpeechServicing) async throws {
        stop()
        isLoading = true
        defer { isLoading = false }

        let result = try await service.synthesize(text: text, voiceId: voiceId, modelId: modelId)
        switch result.payload {
        case let .elevenlabs(base64, _, _, _, _):
            guard let data = Data(base64Encoded: base64) else {
                fallbackSpeak(text)
                return
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            isPlaying = true
            player.play()
        case .clientFallback:
            fallbackSpeak(text)
        }
    }

    private func fallbackSpeak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        isPlaying = true
        synthesizer.speak(utterance)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.audioPlayer = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
