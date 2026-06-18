import Foundation
import AVFoundation
import VokabKit

/// Offline text-to-speech via AVFoundation. Pins an explicit English voice so
/// pronunciation never follows the (possibly non-English) system locale.
///
/// Observable singleton: `speakingText` holds the text currently being spoken
/// (nil when idle) so a `PronounceButton` can show an in-progress spinner and
/// offer tap-to-stop. Only one utterance plays at a time.
@MainActor
final class Speaker: NSObject, ObservableObject {
    static let shared = Speaker()

    /// The text being spoken right now, or nil when idle. Drives button state.
    @Published private(set) var speakingText: String?

    private let synth = AVSpeechSynthesizer()
    /// Identity of the utterance in flight, to ignore stale finish/cancel events
    /// from an utterance that a newer `speak` already superseded.
    private var currentUtterance: AVSpeechUtterance?

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Speaks `text` in the given accent. No-op for empty/whitespace text.
    /// Cancels any in-flight utterance so rapid taps don't overlap.
    func speak(_ text: String, accent: Accent) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.voice(for: accent)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92   // slightly slower for learners
        currentUtterance = utterance
        speakingText = trimmed
        synth.speak(utterance)
    }

    /// Stops the current utterance immediately and returns to idle.
    func stop() {
        synth.stopSpeaking(at: .immediate)
        currentUtterance = nil
        speakingText = nil
    }

    private func clearIfCurrent(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }   // a newer speak already took over
        currentUtterance = nil
        speakingText = nil
    }

    /// Requested accent voice, falling back to a generic English voice, then nil
    /// (system default) — never crashes if a locale voice is unavailable.
    private static func voice(for accent: Accent) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: accent.bcp47)
            ?? AVSpeechSynthesisVoice(language: "en")
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    // Delegate callbacks are not main-actor isolated; hop to the main actor to
    // mutate published state. Only clear if the event is for the live utterance.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.clearIfCurrent(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.clearIfCurrent(utterance) }
    }
}
