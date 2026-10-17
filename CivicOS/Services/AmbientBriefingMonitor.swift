import Foundation
import AVFoundation
import Combine

/// Listens for audio route changes (AirPods, CarPlay, BT headset coming
/// online) and — if the user opted into the ambient morning briefing — pings
/// a handler so the app can auto-start playback. The handler is responsible
/// for the actual "play" call so this monitor stays UI-agnostic.
///
/// Triggers fire at most once per calendar day, only during the morning
/// window (5am–11am local), and only when the user opted in via Settings.
@MainActor
final class AmbientBriefingMonitor {
    typealias Trigger = @MainActor () -> Void

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var isEnabled = false
    private var trigger: Trigger?

    private static let lastFiredDayKey = "athen.ambient.last-fired-day"
    private static let morningStartHour = 5
    private static let morningEndHour = 11

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(enabled: Bool, onTrigger trigger: @escaping Trigger) {
        self.isEnabled = enabled
        self.trigger = trigger
        if enabled {
            startObservingIfNeeded()
        } else {
            stopObserving()
        }
    }

    func updateEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            startObservingIfNeeded()
        } else {
            stopObserving()
        }
    }

    private func startObservingIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isEnabled else { return }
        guard let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
            return
        }
        // Only "new device available" — coming online, not going away.
        guard reason == .newDeviceAvailable else { return }

        let session = AVAudioSession.sharedInstance()
        guard isInterestingRoute(session.currentRoute) else { return }
        guard isMorning() else { return }
        guard !alreadyFiredToday() else { return }

        markFiredToday()
        trigger?()
    }

    private func isInterestingRoute(_ route: AVAudioSessionRouteDescription) -> Bool {
        for output in route.outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .headphones, .airPlay:
                return true
            default: continue
            }
        }
        return false
    }

    private func isMorning() -> Bool {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= Self.morningStartHour && hour < Self.morningEndHour
    }

    private func alreadyFiredToday() -> Bool {
        let today = Self.todayKey()
        return defaults.string(forKey: Self.lastFiredDayKey) == today
    }

    private func markFiredToday() {
        defaults.set(Self.todayKey(), forKey: Self.lastFiredDayKey)
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .init(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}
