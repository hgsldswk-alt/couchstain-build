import Foundation

enum ShareCode {
    static let maxBytes = 64

    static func parse(_ input: String) -> Selection? {
        guard input.utf8.prefix(maxBytes + 1).count <= maxBytes else { return nil }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
            || (48...57).contains($0) || $0 == 45 }) else { return nil }
        let parts = value.uppercased().split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == CareRules.version,
              let care = Care(rawValue: String(parts[1])),
              let stain = Stain(rawValue: String(parts[2])) else { return nil }
        return Selection(care: care, stain: stain)
    }

    static func readFile(_ url: URL) throws -> Selection? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes, let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }
}

struct CardState: Codable, Equatable {
    var rulesVersion = CareRules.version
    var lastCare: Care? = nil
    var recent: Selection? = nil
    var recentChecked = false
    var firstChecked: Selection? = nil
    var ratingAttempted = false

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey) else { return Self() }
        guard data.count <= 2048, var state = try? JSONDecoder().decode(Self.self, from: data),
              state.rulesVersion == CareRules.version else {
            return conservative()
        }
        if let recent = state.recent {
            state.recentChecked = state.recentChecked && CareRules.card(for: recent).allowsDryCheck
        } else {
            state.recentChecked = false
        }
        if let first = state.firstChecked, !CareRules.card(for: first).allowsDryCheck {
            state.firstChecked = nil
        }
        return state
    }

    private static let storageKey = "card-state"

    private static func conservative() -> Self {
        Self(lastCare: .unknown, recent: Selection(care: .unknown, stain: .problem),
             ratingAttempted: true)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    mutating func open(_ selection: Selection) {
        lastCare = selection.care
        if recent != selection {
            recent = selection
            recentChecked = firstChecked == selection
        }
    }

    @discardableResult
    mutating func recordDryCheck(_ card: Card) -> Bool {
        guard recent == card.selection, card.allowsDryCheck, !recentChecked else { return false }
        recentChecked = true
        if firstChecked == nil { firstChecked = card.selection }
        return true
    }

    mutating func consumeRatingAttempt(card: Card, completedShare: Bool, idle: Bool) -> Bool {
        guard idle, completedShare, !ratingAttempted, firstChecked != nil, recentChecked,
              recent == card.selection, card.allowsDryCheck else { return false }
        ratingAttempted = true
        return true
    }
}

enum StoreLink {
    static let supportURL = URL(string: "https://hgsldswk-alt.github.io/couchstain-support/")!

    static func appURL(id: String) -> URL? {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + id)
    }
}
