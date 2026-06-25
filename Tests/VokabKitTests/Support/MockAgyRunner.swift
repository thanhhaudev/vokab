import Foundation
@testable import VokabKit

/// Test double for `AgyRunner`. Returns a queue of canned responses (or throws
/// canned errors) and records the prompts it received.
final class MockAgyRunner: AgyRunner, @unchecked Sendable {
    enum Step {
        case respond(String)
        case fail(AgyError)
    }

    private let lock = NSLock()
    private var steps: [Step]
    /// When set, the response is chosen by inspecting the prompt instead of popping
    /// in call order — needed when callers run chunks concurrently (call order is
    /// nondeterministic) but the response must still match the chunk's content.
    private let router: (@Sendable (String) -> Step)?
    private(set) var receivedPrompts: [String] = []

    init(_ steps: [Step]) {
        self.steps = steps
        self.router = nil
    }

    init(router: @escaping @Sendable (String) -> Step) {
        self.steps = []
        self.router = router
    }

    /// Convenience for a single canned response.
    convenience init(response: String) {
        self.init([.respond(response)])
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return receivedPrompts.count
    }

    func run(prompt: String, model: String?) async throws -> String {
        lock.lock()
        receivedPrompts.append(prompt)
        let step: Step?
        if let router {
            step = router(prompt)
        } else {
            step = steps.isEmpty ? nil : steps.removeFirst()
        }
        lock.unlock()

        switch step {
        case .respond(let s): return s
        case .fail(let e): throw e
        case nil: throw AgyError.nonZeroExit(code: 1, stderr: "mock exhausted")
        }
    }
}
