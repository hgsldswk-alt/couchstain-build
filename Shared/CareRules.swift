import Foundation

enum Care: String, CaseIterable, Codable, Identifiable {
    case water = "W", solvent = "S", either = "WS", vacuum = "X"
    case unknown = "UNK", leather = "LEA", vinyl = "VIN"

    static let codes: [Self] = [.water, .solvent, .either, .vacuum]
    static let materials: [Self] = [.unknown, .leather, .vinyl]

    var id: String { rawValue }
    var key: String { "care." + rawValue }
    var matchKey: String { Self.codes.contains(self) ? "care.label." + rawValue : key }

    static func normalized(_ label: String) -> Self {
        let code = label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch code {
        case "W": return .water
        case "S": return .solvent
        case "WS", "W-S", "W/S", "SW": return .either
        case "X": return .vacuum
        default: return .unknown
        }
    }
}

enum Stain: String, CaseIterable, Codable, Identifiable {
    case coffee = "COF", juice = "JUI", food = "FOO", ink = "INK"
    case pet = "PET", other = "OTH", problem = "PRB"

    var id: String { rawValue }
    var key: String { "stain." + rawValue }
}

struct Selection: Codable, Equatable {
    let care: Care
    let stain: Stain

    var code: String { CareRules.version + "-" + care.rawValue + "-" + stain.rawValue }

    func label(bundle: Bundle = L.bundle) -> String {
        L.f("card.match", L.t(care.matchKey, bundle: bundle), L.t(stain.key, bundle: bundle), bundle: bundle)
    }
}

struct Rule: Identifiable {
    let id: String
    let careGate: [Care]
    let stain: [Stain]
    let sourceRefs: [SourceID]
    let allowsDryCheck: Bool

    var firstStep: String { id + ".first" }
    var recheck: String { id + ".recheck" }
    var stop: String { id + ".stop" }
    var citation: String { id + ".citation" }

    init(_ id: String, careGate: [Care] = Care.allCases, stain: [Stain] = Stain.allCases,
         sources: [SourceID], allowsDryCheck: Bool = false) {
        self.id = id
        self.careGate = careGate
        self.stain = stain
        sourceRefs = sources
        self.allowsDryCheck = allowsDryCheck
    }
}

struct Card {
    let selection: Selection
    let gate: Rule
    let stainRule: Rule?
    let title: String
    let firstSteps: [String]
    let rechecks: [String]
    let stops: [String]
    let allowsDryCheck: Bool

    var rules: [Rule] { [gate] + (stainRule.map { [$0] } ?? []) }
    var sourceRefs: [SourceID] {
        rules.flatMap(\.sourceRefs).reduce(into: []) { result, source in
            if !result.contains(source) { result.append(source) }
        }
    }
}

enum CareRules {
    static let version = "CSR1"
    static let r01 = Rule("R01", careGate: [.water], sources: [.a, .b, .c, .d], allowsDryCheck: true)
    static let r02 = Rule("R02", careGate: [.either], sources: [.a, .b, .c, .e], allowsDryCheck: true)
    static let r03 = Rule("R03", careGate: [.solvent], sources: [.a, .b, .c])
    static let r04 = Rule("R04", careGate: [.vacuum], sources: [.a, .b])
    static let r05 = Rule("R05", careGate: [.unknown], sources: [.b, .c, .f])
    static let r06 = Rule("R06", careGate: [.leather, .vinyl], sources: [.a, .b, .g])
    static let r07 = Rule("R07", careGate: [.water, .either], stain: [.coffee, .juice],
                          sources: [.b, .c, .d, .h], allowsDryCheck: true)
    static let r08 = Rule("R08", careGate: [.water, .either, .solvent, .unknown],
                          stain: [.food, .ink, .other], sources: [.b, .c, .d, .h])
    static let r09 = Rule("R09", stain: [.pet], sources: [.c, .i])
    static let r10 = Rule("R10", stain: [.problem], sources: [.b, .c, .d, .e])
    static let all = [r01, r02, r03, r04, r05, r06, r07, r08, r09, r10]

    static func card(label: String, material: Care = .unknown, conflict: Bool = false, stain: Stain) -> Card {
        let labelCare = Care.normalized(label)
        let care: Care
        if labelCare == .vacuum {
            care = .vacuum
        } else if material == .leather || material == .vinyl {
            care = material
        } else {
            care = conflict ? .unknown : labelCare
        }
        return card(for: Selection(care: care, stain: stain))
    }

    static func card(for selection: Selection) -> Card {
        if selection.stain == .pet { return restricted(selection, r09, "card.pet") }
        if selection.stain == .problem { return restricted(selection, r10, "card.problem") }

        let gate: Rule
        switch selection.care {
        case .vacuum: return restricted(selection, r04, "card.vacuum")
        case .leather, .vinyl: return restricted(selection, r06, "card.special")
        case .unknown: return restricted(selection, r05, "card.unknown", dryFirst: r08)
        case .solvent: return restricted(selection, r03, "card.solvent", dryFirst: r08)
        case .water: gate = r01
        case .either: gate = r02
        }

        if gate.allowsDryCheck && r07.stain.contains(selection.stain) {
            return Card(selection: selection, gate: gate, stainRule: r07,
                        title: selection.stain == .coffee ? "card.coffee" : "card.juice",
                        firstSteps: ["R07.surface", gate.id + ".allowed"],
                        rechecks: ["R07.dry"], stops: [gate.stop, "R07.escalate"],
                        allowsDryCheck: true)
        }
        return Card(selection: selection, gate: gate, stainRule: r08, title: "card.restricted",
                    firstSteps: [selection.stain == .food ? "R08.food" : "R08.uncertain"],
                    rechecks: [r08.recheck], stops: [r08.stop], allowsDryCheck: false)
    }

    private static func restricted(_ selection: Selection, _ gate: Rule, _ title: String,
                                   dryFirst: Rule? = nil) -> Card {
        let stainRule = dryFirst.flatMap { $0.stain.contains(selection.stain) ? $0 : nil }
        return Card(selection: selection, gate: gate, stainRule: stainRule, title: title,
                    firstSteps: [gate.firstStep] + (stainRule.map { [$0.firstStep] } ?? []),
                    rechecks: [gate.recheck], stops: [gate.stop], allowsDryCheck: false)
    }
}

enum SourceID: String, CaseIterable, Identifiable {
    case a = "A", b = "B", c = "C", d = "D", e = "E", f = "F", g = "G", h = "H", i = "I"

    var id: String { rawValue }
    var name: String { "source." + rawValue + ".name" }
    var scope: String { "source." + rawValue + ".scope" }

    var urls: [URL] {
        let addresses: [String]
        switch self {
        case .a: addresses = ["https://www.ashleyfurniture.com/care-and-cleaning"]
        case .b: addresses = ["https://www.la-z-boy.com/content/CustomerCare/fabric-and-leather-care"]
        case .c: addresses = ["https://iicrc.org/wp-content/uploads/2023/01/Tip-Sheet-Upholstery.pdf"]
        case .d: addresses = ["https://iicrc.org/wp-content/uploads/2023/01/Tip-Sheet-Carpet-Topics.pdf"]
        case .e: addresses = ["https://www.cdc.gov/hygiene/about/when-and-how-to-clean-and-disinfect-your-home.html"]
        case .f: addresses = ["https://revolutionfabrics.com/blogs/gotcha-covered/upholstery-cleaning-codes-explained"]
        case .g: addresses = ["https://www.knoll.com/document/1347383352362/KT_Cleaning.pdf",
                              "https://intexsupport.com/en/intex-product-user-manual-pull-out-sofa-66552np-season-2026/a-10043/"]
        case .h: addresses = ["https://www.ethanallen.com/on/demandware.static/-/Library-Sites-ethanallen-shared/default/dwd2c42c00/pdf/Ethan_Allen_Use_and_Care.pdf"]
        case .i: addresses = ["https://iicrc.org/iicrcgloballocator/"]
        }
        return addresses.compactMap { URL(string: $0) }
    }
}
