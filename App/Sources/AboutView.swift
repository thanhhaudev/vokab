import SwiftUI
import AppKit

/// Custom About window. Replaces the OS-standard about panel (via
/// `CommandGroup(replacing: .appInfo)` in `VokabApp`) so it can carry a link back
/// to the repo — the standard AppKit panel has no room for a custom action.
struct AboutView: View {
    private static let repoURL = URL(string: "https://github.com/thanhhaudev/vokab")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(spacing: 3) {
                Text("vokab").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(L.t("Version \(version) (\(build))", "Phiên bản \(version) (\(build))"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Button {
                NSWorkspace.shared.open(Self.repoURL)
            } label: {
                Image("GitHubMark")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(Self.repoURL.absoluteString)
        }
        .padding(28)
        .frame(width: 260)
        .background(Theme.bgPrimary)
    }
}
