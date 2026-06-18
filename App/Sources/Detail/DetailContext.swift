import SwiftUI

/// Where a word/phrase detail view is shown.
/// `.library` = master-detail pane (footer offers "Practice writing").
/// `.capture` = standalone post-capture window (mockups #1/#2): footer shows
/// "Saved ✓" + source + a "Done" button that closes the window.
enum DetailContext {
    case library
    case capture(onDone: () -> Void)

    var isCapture: Bool {
        if case .capture = self { return true }
        return false
    }

    var onDone: (() -> Void)? {
        if case .capture(let cb) = self { return cb }
        return nil
    }
}
