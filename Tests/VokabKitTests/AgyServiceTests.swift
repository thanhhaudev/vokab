import XCTest
@testable import VokabKit

final class AgyServiceTests: XCTestCase {

    private func service(_ runner: AgyRunner,
                         jsonError: JSONErrorBehavior = .retryOnce) -> AgyService {
        AgyService(runner: runner, settings: VokabSettings(jsonErrorBehavior: jsonError))
    }

    func testDefineWordDecodes() async throws {
        let runner = MockAgyRunner(response: #"{"pos":"noun","meaning_vi":"nghĩa"}"#)
        let card = try await service(runner).defineWord("test", language: "en")
        XCTAssertEqual(card.pos, "noun")
        XCTAssertEqual(card.meaningVi, "nghĩa")
        XCTAssertEqual(runner.callCount, 1)
    }

    func testWordPromptIncludesLanguage() async throws {
        let runner = MockAgyRunner(response: #"{"pos":"noun"}"#)
        _ = try await service(runner).defineWord("ephemeral", language: "fr")
        XCTAssertTrue(runner.receivedPrompts.first?.contains("language: fr") == true)
        XCTAssertTrue(runner.receivedPrompts.first?.contains("ephemeral") == true)
    }

    func testClassifyReturnsCategory() async throws {
        let runner = MockAgyRunner(response: #"{"category":"Technology"}"#)
        let category = try await service(runner).classify("router", language: "en", taxonomy: ["Technology"])
        XCTAssertEqual(category, "Technology")
    }

    func testRetriesOnceThenSucceeds() async throws {
        let runner = MockAgyRunner([
            .respond("garbage not json"),
            .respond(#"{"pos":"verb"}"#)
        ])
        let card = try await service(runner).defineWord("run", language: "en")
        XCTAssertEqual(card.pos, "verb")
        XCTAssertEqual(runner.callCount, 2)   // retried exactly once
    }

    func testTwoBadResponsesThrowsDecodeFailure() async {
        let runner = MockAgyRunner([
            .respond("garbage"),
            .respond("still garbage")
        ])
        do {
            _ = try await service(runner).defineWord("x", language: "en")
            XCTFail("expected throw")
        } catch let AgyError.decodeFailure(raw) {
            XCTAssertEqual(raw, "still garbage")
            XCTAssertEqual(runner.callCount, 2)
        } catch {
            XCTFail("expected decodeFailure, got \(error)")
        }
    }

    func testNoRetryWhenShowRaw() async {
        let runner = MockAgyRunner([.respond("garbage"), .respond(#"{"pos":"x"}"#)])
        do {
            _ = try await service(runner, jsonError: .showRaw).defineWord("x", language: "en")
            XCTFail("expected throw")
        } catch AgyError.decodeFailure {
            XCTAssertEqual(runner.callCount, 1)   // did not retry
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testTimeoutPropagatesWithoutRetry() async {
        let runner = MockAgyRunner([.fail(.timeout), .respond(#"{"pos":"x"}"#)])
        do {
            _ = try await service(runner).defineWord("x", language: "en")
            XCTFail("expected throw")
        } catch AgyError.timeout {
            XCTAssertEqual(runner.callCount, 1)   // transport error: no retry
        } catch {
            XCTFail("expected timeout, got \(error)")
        }
    }

    func testAnalyzePhraseDecodes() async throws {
        let runner = MockAgyRunner(response: #"{"type":"idiom","formula_pattern":"kick the bucket"}"#)
        let card = try await service(runner).analyzePhrase("kick the bucket")
        XCTAssertEqual(card.type, "idiom")
        XCTAssertEqual(card.formulaPattern, "kick the bucket")
    }

    func testExtractFromParagraphDecodesArray() async throws {
        let runner = MockAgyRunner(response: #"[{"word":"a","cefr":"B2"},{"word":"b","cefr":"C1"}]"#)
        let items = try await service(runner).extractFromParagraph("some text", taxonomy: [])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[1].word, "b")
    }

    func testJudgeProductionDecodes() async throws {
        let runner = MockAgyRunner(response: """
        {"verdict":"correct","diff":[{"type":"keep","text":"ok"}],"suggested_rating":"good"}
        """)
        let fb = try await service(runner).judgeProduction(word: "run", sentence: "I run.")
        XCTAssertEqual(fb.verdict, "correct")
        XCTAssertEqual(fb.suggestedGrade, .good)
    }
}
