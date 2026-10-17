import AVFoundation
import SwiftUI

// MARK: - Daily hero card (the top of Brief tab)

struct BriefDailyHeroCard: View {
    let brief: CivicBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Today in \(brief.locationLabel)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text(brief.sourceHealth.freshnessLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.20), in: Capsule())
            }
            Text(brief.headline)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(brief.summary)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                metric("\(brief.metrics.activeIssues)", "Active")
                metric("\(brief.metrics.urgentIssues)", "Urgent")
                if let trust = brief.metrics.averageTrustScore {
                    metric("\(trust)%", "Trust")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    CivicTheme.violet,
                    Color(red: 0.34, green: 0.42, blue: 0.96),
                    CivicTheme.cyan
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .shadow(color: CivicTheme.violet.opacity(0.25), radius: 18, x: 0, y: 8)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Deadline rail

struct DeadlineRailCard: View {
    let items: [DeadlineItem]

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.amber)
                    Text("Deadlines this stretch")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.amber)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Text("\(items.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                        .monospacedDigit()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: UUID(uuidString: item.id) ?? UUID()) {
                                DeadlineTile(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct DeadlineTile: View {
    let item: DeadlineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.tint)
                Text(item.countdownLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(item.tint)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 0)
                Image(systemName: scopeIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            Text(item.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(item.jurisdiction)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 220, height: 132, alignment: .topLeading)
        .padding(14)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.tint.opacity(0.30), lineWidth: 1))
        .shadow(color: CivicTheme.cardShadow, radius: 10, x: 0, y: 4)
    }

    private var scopeIcon: String {
        switch item.scope {
        case "federal": "building.columns.fill"
        case "state": "flag.fill"
        case "local-philly": "building.2.fill"
        default: "globe.americas.fill"
        }
    }
}

// MARK: - Audio briefing

/// Curated ElevenLabs voice options exposed in the audio-briefing settings.
/// IDs are stable ElevenLabs voice identifiers. Description strings give the
/// listener a vibe, not a literal personality claim.
struct AudioBriefingVoiceOption: Identifiable, Hashable {
    let id: String   // ElevenLabs voice ID
    let name: String
    let blurb: String
}

enum AudioBriefingVoiceCatalog {
    /// `nil` voiceId means "backend default" (Sarah).
    static let options: [AudioBriefingVoiceOption] = [
        .init(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah",   blurb: "Calm news-anchor cadence"),
        .init(id: "9BWtsMINqrJLrRacOk9x", name: "Aria",    blurb: "Clear, professional"),
        .init(id: "JBFqnCBsd6RMkjVDRZzb", name: "George",  blurb: "Warm, conversational"),
        .init(id: "IKne3meq5aSn9XLyUdCD", name: "Charlie", blurb: "Energetic, upbeat"),
        .init(id: "pqHfZKP75CvOlQylNhV4", name: "Bill",    blurb: "Deep, authoritative"),
    ]
}

struct AudioBriefCard: View {
    @Environment(CivicOSStore.self) private var store
    private var player: AudioBriefingPlayer { .shared }
    /// Local UI state — when true, the customization panel is visible.
    @State private var isExpanded: Bool = false
    /// Local mirror of the focus text so editing doesn't write to UserDefaults
    /// on every keystroke; we commit on Apply.
    @State private var focusDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tappable header row (everything except the play button).
            HStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                    if isExpanded {
                        focusDraft = store.audioBriefingFocus
                    }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(CivicTheme.cyan.opacity(0.18))
                            Image(systemName: "waveform")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CivicTheme.cyan)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(headlineTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide briefing options" : "Show briefing options")

                playButton
            }

            if let err = store.lastAudioBriefingError {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let briefing = store.audioBriefing,
               case .clientFallback(let reason) = briefing.audio,
               !reason.isEmpty {
                Text("Voiced on-device (ElevenLabs unavailable: \(reason))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.quietInk)
            }

            if isExpanded {
                customizationPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CivicTheme.cyan.opacity(0.18), lineWidth: 1))
        .onChange(of: store.audioBriefing) { _, briefing in
            player.load(briefing)
        }
        .onChange(of: store.ambientPlayRequestID) { _, _ in
            // AirPods / CarPlay came online in the morning — auto-play.
            Task {
                if store.audioBriefing == nil {
                    await store.loadAudioBriefing()
                }
                player.load(store.audioBriefing)
                player.play()
            }
        }
    }

    private var headlineTitle: String {
        "\(store.audioBriefingDurationMin)-minute audio briefing"
    }

    private var subtitle: String {
        if store.isGeneratingAudioBriefing { return "Writing your script…" }
        if let briefing = store.audioBriefing {
            let mins = max(1, Int(Double(briefing.script.split(separator: " ").count) / 150.0))
            return "Personalized · about \(mins) min · \(briefing.issueIds.count) items"
        }
        return "Tap to customize · tap play to listen."
    }

    // MARK: - Customization panel

    private var customizationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(CivicTheme.hairline)
            durationSection
            voiceSection
            focusSection
            applyButton
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("LENGTH")
            HStack(spacing: 8) {
                ForEach([5, 10, 15], id: \.self) { mins in
                    let active = store.audioBriefingDurationMin == mins
                    Button {
                        Haptics.selection()
                        store.audioBriefingDurationMin = mins
                    } label: {
                        Text("\(mins) min")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? .white : CivicTheme.mutedInk)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(active ? CivicTheme.ink : CivicTheme.panelElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("VOICE")
            VStack(spacing: 6) {
                ForEach(AudioBriefingVoiceCatalog.options) { option in
                    let active = (store.audioBriefingVoiceId ?? AudioBriefingVoiceCatalog.options.first?.id) == option.id
                    Button {
                        Haptics.selection()
                        store.audioBriefingVoiceId = option.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(active ? CivicTheme.cyan : CivicTheme.quietInk)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(CivicTheme.ink)
                                Text(option.blurb)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(CivicTheme.mutedInk)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(active ? CivicTheme.cyan.opacity(0.10) : CivicTheme.panelElevated,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                            active ? CivicTheme.cyan.opacity(0.4) : CivicTheme.hairline,
                            lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FOCUS / DIRECTION")
            ZStack(alignment: .topLeading) {
                if focusDraft.isEmpty {
                    Text("e.g. focus on local housing, skip federal, briefer on each item")
                        .font(.system(size: 13))
                        .foregroundStyle(CivicTheme.quietInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $focusDraft)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.ink)
                    .frame(minHeight: 70, maxHeight: 120)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private var applyButton: some View {
        Button {
            Haptics.selection()
            // Commit the in-progress focus text.
            store.audioBriefingFocus = focusDraft
            // Drop the cached briefing so the next play regenerates with
            // the new settings, then kick off the load right away so the
            // user gets the new audio quickly.
            store.resetAudioBriefingForRegeneration()
            Task { await store.loadAudioBriefing() }
            withAnimation(.easeInOut(duration: 0.22)) { isExpanded = false }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold))
                Text("Regenerate with these settings")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: CivicTheme.cyan.opacity(0.25), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(store.isGeneratingAudioBriefing)
        .opacity(store.isGeneratingAudioBriefing ? 0.55 : 1)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(CivicTheme.mutedInk)
    }

    private var playButton: some View {
        Button {
            Haptics.selection()
            if store.audioBriefing == nil {
                Task {
                    await store.loadAudioBriefing()
                    if let briefing = store.audioBriefing {
                        player.load(briefing)
                        player.play()
                    }
                }
            } else {
                if player.isPlaying { player.pause() } else { player.play() }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(CivicTheme.cyan)
                Image(systemName: store.isGeneratingAudioBriefing
                      ? "ellipsis"
                      : (player.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                if store.isGeneratingAudioBriefing {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 44, height: 44)
            .shadow(color: CivicTheme.cyan.opacity(0.35), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play audio briefing")
        .disabled(store.isGeneratingAudioBriefing)
    }
}

@Observable
final class AudioBriefingPlayer: NSObject {
    /// Process-wide singleton so audio playback survives any view rebuilds
    /// (e.g., Home tab switches that destroy/recreate the AudioBriefCard).
    static let shared = AudioBriefingPlayer()

    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var lastFingerprint: String?
    private(set) var isPlaying: Bool = false

    func load(_ briefing: CivicAudioBriefing?) {
        guard let briefing else { return }
        let fingerprint = "\(briefing.generatedAt.timeIntervalSince1970)"
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        currentScript = briefing.script

        switch briefing.audio {
        case .elevenlabs(let base64, _, _):
            if let data = Data(base64Encoded: base64) {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
                    try AVAudioSession.sharedInstance().setActive(true)
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    self.player = player
                } catch {
                    player = nil
                }
            }
        case .clientFallback:
            player = nil
        }
    }

    func play() {
        if let player {
            player.play()
            isPlaying = true
            return
        }
        // Fallback to on-device TTS using the script field.
        guard let script = currentScript else { return }
        let utterance = AVSpeechUtterance(string: script)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        synthesizer.delegate = self
        synthesizer.speak(utterance)
        isPlaying = true
    }

    func pause() {
        player?.pause()
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .immediate) }
        isPlaying = false
    }

    /// Drop everything — used when the underlying briefing is invalidated
    /// (e.g., location change wipes the cached briefing).
    func stop() {
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isPlaying = false
        lastFingerprint = nil
        currentScript = nil
    }

    /// Injected lazily so we can fall back without holding state.
    var currentScript: String?
}

extension AudioBriefingPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

extension AudioBriefingPlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in self.isPlaying = false }
    }
}

// MARK: - Cohort card ("How this affects you")

struct CohortCard: View {
    let brief: CivicBriefAnalysis
    let profile: UserProfile?
    let issue: BriefIssueRef

    private var pickedProjection: CivicBriefAnalysis.CohortProjection? {
        let factors = profile?.factors ?? []
        let preferred = preferredCohorts(for: factors)
        return brief.cohortProjections.first { preferred.contains($0.cohort) }
            ?? brief.cohortProjections.first
    }

    var body: some View {
        if let projection = pickedProjection {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: projection.cohort.systemImage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(projection.cohort.tint)
                        .frame(width: 28, height: 28)
                        .background(projection.cohort.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HOW THIS AFFECTS YOU")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(projection.cohort.tint)
                            .tracking(0.5)
                        Text(projection.cohort.label)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                    }
                    Spacer()
                    Text(issue.scope.capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                        .textCase(.uppercase)
                }
                Text(projection.impact)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(value: UUID(uuidString: issue.id) ?? UUID()) {
                    HStack(spacing: 8) {
                        Text("Open the issue")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(projection.cohort.tint)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(projection.cohort.tint)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(projection.cohort.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(projection.cohort.tint.opacity(0.20), lineWidth: 1))
        }
    }

    private func preferredCohorts(for factors: Set<CivicProfileFactor>) -> Set<CivicBriefAnalysis.CohortProjection.Cohort> {
        var out: Set<CivicBriefAnalysis.CohortProjection.Cohort> = [.general]
        for factor in factors {
            switch factor {
            case .renter: out.insert(.renter)
            case .homeowner: out.insert(.homeowner)
            case .parent: out.insert(.parent)
            case .commuter: out.insert(.commuter)
            case .businessOwner: out.insert(.businessOwner)
            case .accessibilityNeeds: out.insert(.olderAdult)
            case .climateFlood: out.insert(.general)
            }
        }
        return out
    }
}

// MARK: - Deep brief card (the main repeating unit in Brief feed)

struct DeepBriefCard: View {
    @Environment(CivicOSStore.self) private var store
    let item: CivicBriefDigestItem
    @State private var expandedLead = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataStrip
                .padding(.horizontal, 16)
                .padding(.top, 14)

            if let brief = item.brief {
                briefBody(brief)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            } else {
                pendingBody
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(CivicTheme.panelElevated.opacity(0.5))
                .overlay(alignment: .top) {
                    Rectangle().fill(CivicTheme.hairline).frame(height: 1)
                }
        }
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CivicTheme.hairline, lineWidth: 1))
        .shadow(color: CivicTheme.cardShadow, radius: 14, x: 0, y: 6)
    }

    private var metadataStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: scopeIcon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(scopeTint)
            Text(item.issue.scope.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(scopeTint)
                .tracking(0.4)
            Text("·")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
            Text(item.issue.jurisdiction)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if let brief = item.brief {
                ConfidenceChip(label: brief.confidence.label)
            }
        }
    }

    @ViewBuilder
    private func briefBody(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(brief.headline)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(brief.subhead)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(brief.lead)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(expandedLead ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
            if brief.lead.count > 280 {
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.18)) { expandedLead.toggle() }
                } label: {
                    Text(expandedLead ? "Show less" : "Show more")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .buttonStyle(.plain)
            }

            if !brief.keyFacts.isEmpty {
                KeyFactsPanel(facts: brief.keyFacts)
            }

            if !brief.twoSides.isEmpty {
                SidesPanel(sides: brief.twoSides)
            }

            FiscalPill(text: brief.fiscalImpact)

            if let quote = brief.pullQuote, !quote.isEmpty {
                PullQuote(text: quote)
            }

            NextActionBox(text: brief.recommendedAction)

            Text(brief.sourceLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CivicTheme.quietInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pendingBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.issue.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.issue.summary)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(3)
            Button {
                Haptics.selection()
                Task { await store.generateBrief(for: item.issueId) }
            } label: {
                HStack(spacing: 7) {
                    if store.generatingBriefFor.contains(item.issueId) {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(store.generatingBriefFor.contains(item.issueId) ? "Thinking…" : "Generate AI brief")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(CivicTheme.violet, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.generatingBriefFor.contains(item.issueId))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            NavigationLink(value: UUID(uuidString: item.issueId) ?? UUID()) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Open source")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(CivicTheme.violet)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Haptics.selection()
                store.queueAssistantPrompt("Explain \(item.issue.title) like I'm a neighbor with no time. Use the brief you have for it, and keep it under 4 sentences.")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Ask Athen")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(CivicTheme.cyan)
            }
            .buttonStyle(.plain)

            ShareLink(item: shareText) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .bold))
                    Text("Share")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(CivicTheme.mutedInk)
            }
        }
    }

    private var shareText: String {
        if let brief = item.brief {
            return "\(brief.headline)\n\n\(brief.subhead)\n\nVia Athen: athen://issue/\(item.issueId)"
        }
        return "\(item.issue.title)\n\nVia Athen: athen://issue/\(item.issueId)"
    }

    private var scopeIcon: String {
        switch item.issue.scope {
        case "federal": "building.columns.fill"
        case "state": "flag.fill"
        case "local-philly": "building.2.fill"
        default: "globe.americas.fill"
        }
    }

    private var scopeTint: Color {
        switch item.issue.scope {
        case "federal": CivicTheme.cyan
        case "state": CivicTheme.violet
        case "local-philly": CivicTheme.amber
        default: CivicTheme.mutedInk
        }
    }
}

// MARK: - Brief sub-components

private struct ConfidenceChip: View {
    let label: CivicBriefAnalysis.Confidence.Label

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(label.tint).frame(width: 6, height: 6)
            Text(label.display)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(label.tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(label.tint.opacity(0.10), in: Capsule())
    }
}

private struct KeyFactsPanel: View {
    let facts: [CivicBriefAnalysis.KeyFact]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(facts) { fact in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 3) {
                        Circle().fill(CivicTheme.cyan).frame(width: 5, height: 5).padding(.top, 5)
                        Rectangle().fill(CivicTheme.cyan.opacity(0.18)).frame(width: 1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                            .tracking(0.4)
                        Text(fact.value)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(CivicTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SidesPanel: View {
    let sides: [CivicBriefAnalysis.Side]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(sides) { side in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: side.stance.systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(side.stance.tint)
                        .frame(width: 22, height: 22)
                        .background(side.stance.tint.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(side.stance.label.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(side.stance.tint)
                                .tracking(0.4)
                            Text("·")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(CivicTheme.quietInk)
                            Text(side.who)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CivicTheme.quietInk)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text(side.headline)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(side.argument)
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .foregroundStyle(CivicTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(side.stance.tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(side.stance.tint.opacity(0.18), lineWidth: 1))
            }
        }
    }
}

private struct FiscalPill: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CivicTheme.green)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("FISCAL IMPACT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.green)
                    .tracking(0.4)
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(CivicTheme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.green.opacity(0.18), lineWidth: 1))
    }
}

private struct PullQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(CivicTheme.violet).frame(width: 3)
            Text("\u{201C}\(text)\u{201D}")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .italic()
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
}

private struct NextActionBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
            VStack(alignment: .leading, spacing: 3) {
                Text("NEXT STEP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                    .tracking(0.5)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(CivicTheme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
    }
}
