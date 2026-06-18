import Foundation

/// Runs `agy models` to populate the model picker, and a trivial prompt to test
/// the configured binary.
/// Caches the `agy models` list in UserDefaults so the pickers show options
/// instantly (agy models cold-starts in ~7s). Refreshed in the background.
enum ModelCache {
    private static let key = "vokab.agyModels.v1"
    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func save(_ models: [String]) {
        guard !models.isEmpty else { return }
        UserDefaults.standard.set(models, forKey: key)
    }

    /// Refreshes the cache off the main thread (best-effort).
    static func refresh(agyPath: String) {
        Task.detached {
            let fresh = AgyTooling.listModels(agyPath: agyPath)
            if !fresh.isEmpty { await MainActor.run { ModelCache.save(fresh) } }
        }
    }
}

enum AgyTooling {
    /// Async wrapper: runs the (blocking) `agy models` subprocess off the main
    /// thread so opening Settings never beachballs the cursor.
    static func listModelsAsync(agyPath: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: listModels(agyPath: agyPath))
            }
        }
    }

    static func listModels(agyPath: String) -> [String] {
        guard FileManager.default.isExecutableFile(atPath: agyPath) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agyPath)
        process.arguments = ["models"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
}
