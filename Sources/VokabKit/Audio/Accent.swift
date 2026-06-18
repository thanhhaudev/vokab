/// Spoken-English accent for pronunciation. Raw value is the BCP-47 language
/// code passed straight to the speech synthesizer voice.
public enum Accent: String, Sendable, CaseIterable {
    case us = "en-US"
    case uk = "en-GB"

    /// BCP-47 language code for the synthesizer voice (e.g. "en-US").
    public var bcp47: String { rawValue }

    /// Maps a stored settings string to an accent; unknown values fall back to US.
    public init(settingsValue: String) {
        self = Accent(rawValue: settingsValue) ?? .us
    }
}
