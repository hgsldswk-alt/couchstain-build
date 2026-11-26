import XCTest

final class CareRulesTests: XCTestCase {
    func testAll49SelectionsAndGatePrecedence() {
        let expected: [Care: String] = [
            .water: "R01", .either: "R02", .solvent: "R03", .vacuum: "R04",
            .unknown: "R05", .leather: "R06", .vinyl: "R06"
        ]
        var codes = Set<String>()
        for care in Care.allCases {
            for stain in Stain.allCases {
                let selection = Selection(care: care, stain: stain)
                let card = CareRules.card(for: selection)
                let gate = stain == .pet ? "R09" : stain == .problem ? "R10" : expected[care]
                XCTAssertEqual(card.gate.id, gate, selection.code)
                XCTAssertTrue(card.gate.careGate.contains(care))
                XCTAssertTrue(card.gate.stain.contains(stain))
                XCTAssertFalse(card.firstSteps.isEmpty)
                XCTAssertFalse(card.rechecks.isEmpty)
                XCTAssertFalse(card.stops.isEmpty)
                XCTAssertFalse(card.sourceRefs.isEmpty)
                XCTAssertEqual(ShareCode.parse(selection.code), selection)
                XCTAssertTrue(codes.insert(selection.code).inserted)

                let dryCheck = (care == .water || care == .either) && (stain == .coffee || stain == .juice)
                XCTAssertEqual(card.allowsDryCheck, dryCheck, selection.code)
                XCTAssertEqual(card.firstSteps.contains(where: { $0.hasSuffix(".allowed") }), dryCheck)
                if dryCheck {
                    XCTAssertEqual(card.stainRule?.id, "R07")
                } else if [.water, .either, .solvent, .unknown].contains(care)
                            && [.food, .ink, .other].contains(stain) {
                    XCTAssertEqual(card.stainRule?.id, "R08")
                } else {
                    XCTAssertNil(card.stainRule)
                }
            }
        }
        XCTAssertEqual(codes.count, 49)
    }

    func testR08AddsOnlyTheConditionalDryFirstStepToRestrictedCards() {
        for (care, gate, title) in [(Care.solvent, "R03", "card.solvent"), (.unknown, "R05", "card.unknown")] {
            for stain in [Stain.food, .ink, .other] {
                let selection = Selection(care: care, stain: stain)
                let card = CareRules.card(for: selection)
                XCTAssertEqual(card.rules.map(\.id), [gate, "R08"], selection.code)
                XCTAssertEqual(card.title, title, selection.code)
                XCTAssertEqual(card.firstSteps, [gate + ".first", "R08.first"], selection.code)
                XCTAssertEqual(card.rechecks, [gate + ".recheck"], selection.code)
                XCTAssertEqual(card.stops, [gate + ".stop"], selection.code)
                XCTAssertFalse(card.allowsDryCheck, selection.code)
            }
        }
    }

    func testAliasesConflictsAndSpecialMaterial() {
        for code in [" WS ", "W-s", "W/S", "SW\n"] {
            XCTAssertEqual(Care.normalized(code), .either)
        }
        for code in ["", "W/S/X", "W S", "W+", "WATER"] {
            XCTAssertEqual(Care.normalized(code), .unknown)
        }
        XCTAssertEqual(CareRules.card(label: "W", conflict: true, stain: .coffee).gate.id, "R05")
        XCTAssertEqual(CareRules.card(label: "W", material: .leather, stain: .coffee).gate.id, "R06")
        XCTAssertEqual(CareRules.card(label: "W", material: .vinyl, stain: .juice).gate.id, "R06")
        XCTAssertEqual(CareRules.card(label: "X", material: .leather, stain: .coffee).gate.id, "R04")
        XCTAssertEqual(CareRules.card(label: "X", stain: .pet).gate.id, "R09")
        XCTAssertEqual(CareRules.card(label: "W", material: .vinyl, stain: .problem).gate.id, "R10")
    }

    func testEveryRuleAndProducedCardHasThreeLanguagesAndSources() throws {
        XCTAssertEqual(CareRules.all.map(\.id), (1...10).map { String(format: "R%02d", $0) })
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let bundle = try localizedBundle(language)
            for source in SourceID.allCases {
                assertLocalized([source.name, source.scope], in: bundle)
                XCTAssertFalse(source.urls.isEmpty)
                XCTAssertTrue(source.urls.allSatisfy { $0.scheme == "https" })
            }
            for rule in CareRules.all {
                assertLocalized([rule.firstStep, rule.recheck, rule.stop, rule.citation], in: bundle)
                XCTAssertFalse(rule.sourceRefs.isEmpty)
            }
            for care in Care.allCases {
                for stain in Stain.allCases {
                    let card = CareRules.card(for: Selection(care: care, stain: stain))
                    assertLocalized([card.title, care.key, care.matchKey, stain.key] +
                                    card.firstSteps + card.rechecks + card.stops, in: bundle)
                    XCTAssertFalse(card.selection.label(bundle: bundle).contains("%"))
                }
            }
        }
    }

    private func assertLocalized(_ keys: [String], in bundle: Bundle,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for key in keys {
            let value = L.t(key, bundle: bundle)
            XCTAssertNotEqual(value, key, key, file: file, line: line)
            XCTAssertFalse(value.isEmpty, key, file: file, line: line)
        }
    }
}

func localizedBundle(_ language: String) throws -> Bundle {
    let url = try XCTUnwrap(L.bundle.url(forResource: language, withExtension: "lproj"))
    return try XCTUnwrap(Bundle(url: url))
}
