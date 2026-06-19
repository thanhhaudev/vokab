import XCTest
@testable import VokabKit

final class BatchEnrichmentTests: XCTestCase {

    private func service(_ runner: AgyRunner) -> AgyService {
        AgyService(runner: runner, settings: VokabSettings())
    }

    func testEnrichWordRelationsBatchOneCallTwoWords() async throws {
        let runner = MockAgyRunner(response:
            #"[{"word":"alpha","synonyms":["a1"]},{"word":"beta","synonyms":["b1"]}]"#)
        let result = try await service(runner).enrichWordRelationsBatch(["alpha", "beta"], language: "en")

        XCTAssertEqual(runner.callCount, 1, "batch must spend exactly one agy call")
        XCTAssertEqual(result["alpha"]?.synonyms, ["a1"])
        XCTAssertEqual(result["beta"]?.synonyms, ["b1"])
        XCTAssertNotNil(result["alpha"])
        XCTAssertNotNil(result["beta"])
    }

    func testEnrichWordExtrasBatchOneCallTwoWords() async throws {
        let runner = MockAgyRunner(response:
            #"[{"word":"alpha","etymology":"A-root"},{"word":"beta","etymology":"B-root"}]"#)
        let result = try await service(runner).enrichWordExtrasBatch(["alpha", "beta"], language: "en")

        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(result["alpha"]?.etymology, "A-root")
        XCTAssertEqual(result["beta"]?.etymology, "B-root")
    }

    func testBatchKeysByInputSpellingCaseInsensitive() async throws {
        // agy echoes a different-cased word; caller looks up by what it passed.
        let runner = MockAgyRunner(response:
            #"[{"word":"Alpha","synonyms":["a1"]}]"#)
        let result = try await service(runner).enrichWordRelationsBatch(["alpha"], language: "en")
        XCTAssertEqual(result["alpha"]?.synonyms, ["a1"], "keyed by the input spelling")
    }

    func testBatchStripsMarkdownFence() async throws {
        let fenced = """
        ```json
        [{"word":"alpha","synonyms":["a1"]},{"word":"beta","synonyms":["b1"]}]
        ```
        """
        let runner = MockAgyRunner(response: fenced)
        let result = try await service(runner).enrichWordRelationsBatch(["alpha", "beta"], language: "en")
        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(result["alpha"]?.synonyms, ["a1"])
        XCTAssertEqual(result["beta"]?.synonyms, ["b1"])
    }

    func testBatchPromptListsWordsAndLanguage() async throws {
        let runner = MockAgyRunner(response: #"[]"#)
        _ = try await service(runner).enrichWordRelationsBatch(["alpha", "beta"], language: "fr")
        let prompt = try XCTUnwrap(runner.receivedPrompts.first)
        XCTAssertTrue(prompt.contains("alpha"))
        XCTAssertTrue(prompt.contains("beta"))
        XCTAssertTrue(prompt.contains("language: fr"))
    }

    func testBatchDecodeFailureThrowsAgyError() async throws {
        // showRaw → no retry, so a single garbage response must surface the error.
        let runner = MockAgyRunner(response: "not json at all")
        let svc = AgyService(runner: runner,
                             settings: VokabSettings(jsonErrorBehavior: .showRaw))
        do {
            _ = try await svc.enrichWordRelationsBatch(["alpha"], language: "en")
            XCTFail("expected decode failure to throw")
        } catch let error as AgyError {
            guard case .decodeFailure = error else {
                return XCTFail("expected .decodeFailure, got \(error)")
            }
        }
    }
}
