import AVFoundation
import Combine
import Foundation
import Speech

struct VoiceSession: Equatable, Hashable, Decodable {
    let provider: String
    let configured: Bool
    let mode: String
    let fallbackReason: String?
    let agentID: String?
    let signedURL: String?
    let tools: [VoiceTool]

    struct VoiceTool: Equatable, Hashable, Decodable, Identifiable {
        var id: String { name }
        let name: String
        let method: String
        let path: String
    }
}

protocol VoiceServicing {
    func fetchSession() async throws -> VoiceSession
}

struct HTTPVoiceService: VoiceServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchSession() async throws -> VoiceSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/voice/session"), timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CivicFilingError.invalidResponse
        }
        return try JSONDecoder().decode(VoiceSession.self, from: data)
    }
}

struct MockVoiceService: VoiceServicing {
    func fetchSession() async throws -> VoiceSession {
        VoiceSession(
            provider: "elevenlabs",
            configured: false,
            mode: "native-fallback",
            fallbackReason: "Connect CIVIC_API_BASE_URL plus ElevenLabs credentials to enable signed voice-agent sessions.",
            agentID: nil,
            signedURL: nil,
            tools: [
                .init(name: "getDailyBrief", method: "GET", path: "/v1/voice/tools/daily-brief"),
                .init(name: "explainIssue", method: "GET", path: "/v1/voice/tools/explain-issue"),
                .init(name: "matchServices", method: "GET", path: "/v1/voice/tools/service-match"),
                .init(name: "draftFiling", method: "POST", path: "/v1/voice/tools/draft-filing"),
                .init(name: "readDraftBack", method: "POST", path: "/v1/voice/tools/read-draft-back")
            ]
        )
    }
}

@MainActor
final class SpeechVoiceController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case processing
        case speaking
        case unavailable(String)

        var label: String {
            switch self {
            case .idle: "Ready"
            case .requestingPermission: "Checking access"
            case .listening: "Listening"
            case .processing: "Processing"
            case .speaking: "Speaking"
            case let .unavailable(reason): reason
            }
        }
    }

    @Published var transcript = ""
    @Published var state: State = .idle
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    var isSpeaking: Bool {
        if case .speaking = state { return true }
        return false
    }

    func toggleListening() {
        isListening ? stopListening() : requestAndStart()
    }

    func requestAndStart() {
        guard recognizer?.isAvailable == true else {
            state = .unavailable("Speech unavailable")
            return
        }
        state = .requestingPermission
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }
                guard authStatus == .authorized else {
                    self.state = .unavailable("Speech permission needed")
                    return
                }
                self.requestMicrophonePermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.state = .unavailable("Microphone permission needed")
                            return
                        }
                        self.startListening()
                    }
                }
            }
        }
    }

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if state == .listening { state = .processing }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.state == .processing else { return }
            self.state = .idle
        }
    }

    func speak(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        // Recording sets the session to .record which mutes output — flip
        // back to .playback so TTS is actually audible after a voice turn.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal — synthesizer will still try via the prior category.
        }
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        state = .speaking
        synthesizer.speak(utterance)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1.0, Double(cleaned.count) / 24.0)) { [weak self] in
            guard let self, self.state == .speaking else { return }
            self.state = .idle
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        if state == .speaking { state = .idle }
    }

    private func startListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""
        errorMessage = nil

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .listening

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.stopListening()
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            state = .unavailable("Mic start failed")
        }
    }
}
