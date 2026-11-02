import Foundation

struct PortRules: Equatable, Sendable {
    let ranges: [ClosedRange<UInt16>]

    init(_ text: String) throws {
        var parsed: [ClosedRange<UInt16>] = []
        for token in text.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count),
                  bounds.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                  let lower = UInt16(bounds[0]), lower > 0,
                  let upper = UInt16(bounds.last!), upper >= lower else {
                throw ValidationError.invalidPort(String(token))
            }
            parsed.append(lower...upper)
        }
        ranges = parsed
    }

    func contains(_ port: UInt16) -> Bool { ranges.contains { $0.contains(port) } }

    enum ValidationError: LocalizedError {
        case invalidPort(String)
        var errorDescription: String? {
            switch self {
            case .invalidPort(let token): return "Invalid port ‘\(token)’. Use 1–65535 or an ascending range."
            }
        }
    }
}

struct DiscoverySettings: Equatable, Sendable {
    var automatic: Bool
    let includedText: String
    let excludedText: String
    let included: PortRules
    let excluded: PortRules
    static let defaults = try! DiscoverySettings(automatic: true, included: "", excluded: "")

    init(automatic: Bool, included: String, excluded: String) throws {
        self.automatic = automatic
        includedText = included
        excludedText = excluded
        self.included = try PortRules(included)
        self.excluded = try PortRules(excluded)
    }

    static func load(from defaults: UserDefaults = .standard) -> DiscoverySettings {
        let automatic = defaults.object(forKey: "discovery.automatic") as? Bool ?? true
        return (try? DiscoverySettings(automatic: automatic,
                                       included: defaults.string(forKey: "discovery.included") ?? "",
                                       excluded: defaults.string(forKey: "discovery.excluded") ?? "")) ?? .defaults
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(automatic, forKey: "discovery.automatic")
        defaults.set(includedText, forKey: "discovery.included")
        defaults.set(excludedText, forKey: "discovery.excluded")
    }
}
