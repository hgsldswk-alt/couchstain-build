import Foundation
import XCTest

final class CardStateTests: XCTestCase {
    private let coffee = Selection(care: .water, stain: .coffee)
    private let pet = Selection(care: .water, stain: .pet)

    func testPaidDownloadAlwaysOpen() {
        XCTAssertTrue(Launch.freePeriod)
        XCTAssertTrue(CareRules.card(for: coffee).allowsDryCheck)
        XCTAssertEqual(ShareCode.parse(coffee.code), coffee)
    }

    func testInvalidCodesAndFileSizeLimit() throws {
        XCTAssertEqual(ShareCode.parse(" \t csr1-w-cof \r\n"), coffee)
        for invalid in ["CSR2-W-COF", "CSR1-W-COF-EXTRA", "CSR1-W-S-COF", "CSR1-W-DOG",
                        "CSR1--COF", "CSR1-X-COF\nCSR1-W-COF", "CSR1-W-CÖF",
                        "CSR1-W-COF" + String(repeating: " ", count: 64)] {
            XCTAssertNil(ShareCode.parse(invalid), invalid)
        }
        let valid = try ShareFile.write(Data("CSR1-W-COF\n".utf8), name: "card.couchstain")
        defer { ShareFile.remove(valid) }
        XCTAssertEqual(try ShareCode.readFile(valid), coffee)

        let large = try ShareFile.write(Data(repeating: 65, count: 256), name: "large.txt")
        defer { ShareFile.remove(large) }
        XCTAssertNil(try ShareCode.readFile(large))
        let binary = try ShareFile.write(Data([0xFF, 0xFE, 0x00]), name: "binary.couchstain")
        defer { ShareFile.remove(binary) }
        XCTAssertNil(try ShareCode.readFile(binary))
    }

    func testSavedCardAndFirstDryCheckSurviveReload() throws {
        let suite = "CouchStainTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(CardState.load(from: defaults).recent)
        var state = CardState()
        state.open(coffee)
        XCTAssertTrue(state.recordDryCheck(CareRules.card(for: coffee)))
        XCTAssertFalse(state.recordDryCheck(CareRules.card(for: coffee)))
        state.save(to: defaults)
        XCTAssertEqual(CardState.load(from: defaults), state)
        state.open(pet)
        XCTAssertFalse(state.recordDryCheck(CareRules.card(for: pet)))
        XCTAssertEqual(state.firstChecked, coffee)
        XCTAssertFalse(state.recentChecked)
        state.open(coffee)
        XCTAssertTrue(state.recentChecked)
    }

    func testUnknownVersionAndInvalidRecordFallBackToStop() throws {
        let suite = "CouchStainTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = CardState()
        state.open(coffee)
        state.rulesVersion = "CSR999"
        state.save(to: defaults)
        let expected = Selection(care: .unknown, stain: .problem)
        XCTAssertEqual(CardState.load(from: defaults).recent, expected)
        defaults.set(Data("broken".utf8), forKey: "card-state")
        XCTAssertEqual(CardState.load(from: defaults).recent, expected)
    }

    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testReviewRequiresCompletedShareAfterDryCheckWhileIdleAndOnlyOnce() {
        var state = CardState()
        state.open(coffee)
        let card = CareRules.card(for: coffee)
        XCTAssertFalse(state.consumeRatingAttempt(card: card, completedShare: true, idle: true))
        XCTAssertTrue(state.recordDryCheck(card))
        XCTAssertFalse(state.consumeRatingAttempt(card: card, completedShare: false, idle: true))
        XCTAssertFalse(state.consumeRatingAttempt(card: card, completedShare: true, idle: false))
        state.open(pet)
        XCTAssertFalse(state.consumeRatingAttempt(card: CareRules.card(for: pet), completedShare: true, idle: true))
        state.open(coffee)
        XCTAssertTrue(state.consumeRatingAttempt(card: card, completedShare: true, idle: true))
        XCTAssertFalse(state.consumeRatingAttempt(card: card, completedShare: true, idle: true))
    }
}
