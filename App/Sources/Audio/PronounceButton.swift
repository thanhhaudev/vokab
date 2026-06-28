import SwiftUI
import VokabKit

/// Speaker button that pronounces `text` in `accent`. Matches the mockup
/// `.audio-btn` (circle, accent icon, hairline border). Two sizes: `.regular`
/// for headwords, `.small` for inline example rows. While this text is being
/// spoken the icon becomes a spinner and tapping again stops playback.
struct PronounceButton: View {
    @Environment(\.displayScale) private var displayScale
    let text: String
    let accent: Accent
    var size: Size = .regular
    @ObservedObject private var speaker = Speaker.shared

    enum Size {
        case regular, small
        var diameter: CGFloat { self == .regular ? 30 : 22 }
        var icon: CGFloat { self == .regular ? 13 : 11 }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSpeaking: Bool { !trimmed.isEmpty && speaker.speakingText == trimmed }

    var body: some View {
        Button {
            if isSpeaking { speaker.stop() } else { speaker.speak(text, accent: accent) }
        } label: {
            Group {
                if isSpeaking {
                    ActivityDots(diameter: size == .regular ? 4 : 3, color: Theme.accent)
                } else {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: size.icon)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: size.diameter, height: size.diameter)
            .overlay(Circle().strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeaking ? L.t("Stop", "Dừng") : "Pronounce \(text)")
    }
}
