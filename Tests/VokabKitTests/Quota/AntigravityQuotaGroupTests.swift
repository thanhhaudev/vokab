import XCTest
@testable import VokabKit

final class AntigravityQuotaGroupTests: XCTestCase {
    func test_groupKey_fromBucketIdPrefix() {
        let g = AntigravityQuotaSummary.Group(displayName: "Gemini Models", description: nil,
            buckets: [.init(bucketId: "gemini-weekly", displayName: nil, window: .weekly, remainingFraction: 1, resetTime: nil)])
        XCTAssertEqual(g.key, "gemini")
    }
    func test_groupKey_fallsBackToSlug() {
        let g = AntigravityQuotaSummary.Group(displayName: "Claude and GPT models", description: nil, buckets: [])
        XCTAssertEqual(g.key, "claude-and-gpt-models")
    }
    func test_modelToGroupKey_gemini() {
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "Gemini 3.1 Pro (High)"), "gemini")
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "Gemini 3.5 Flash (Low)"), "gemini")
    }
    func test_modelToGroupKey_thirdParty() {
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "Claude Sonnet 4.6 (Thinking)"), "3p")
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "Claude Opus 4.6 (Thinking)"), "3p")
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "GPT-OSS 120B (Medium)"), "3p")
    }
    func test_modelToGroupKey_nilOrUnknown_returnsNil() {
        XCTAssertNil(AntigravityModelGroup.groupKey(forModel: nil))
        XCTAssertNil(AntigravityModelGroup.groupKey(forModel: "Mystery Model"))
    }
    func test_modelToGroupKey_moreThirdPartyNames() {
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "Sonnet 4.6"), "3p")
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "Haiku 4.5"), "3p")
        XCTAssertEqual(AntigravityModelGroup.groupKey(forModel: "Fable 5"), "3p")
    }
}
