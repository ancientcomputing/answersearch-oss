import Foundation

public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// One of `space`, `return`, `f`, `k`.
    public var key: String
    /// One of `control+option`, `control+shift`, `option+shift`.
    public var modifiers: String

    public init(enabled: Bool, key: String, modifiers: String) {
        self.enabled = enabled
        self.key = key
        self.modifiers = modifiers
    }

    public static let suggested = KeyboardShortcut(enabled: true, key: "space", modifiers: "control+option")

    public static let allowedKeys = ["space", "return", "f", "k"]
    public static let allowedModifiers = ["control+option", "control+shift", "option+shift"]

    /// Replaces unknown values with the suggested ones.
    public var normalized: KeyboardShortcut {
        KeyboardShortcut(
            enabled: enabled,
            key: Self.allowedKeys.contains(key) ? key : Self.suggested.key,
            modifiers: Self.allowedModifiers.contains(modifiers) ? modifiers : Self.suggested.modifiers
        )
    }
}

/// Non-secret settings, persisted as JSON in Application Support. API keys never live here.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultWebSearchMaxUses = 5

    public var provider: ProviderKind = .anthropic
    public var model: String = ProviderKind.anthropic.defaultModel
    public var responseMode: ResponseMode = .default
    public var webSearchMaxUses: Int = AppSettings.defaultWebSearchMaxUses
    /// Opt-in for the on-device "Local AI" answer mode. Answer-mode presets never change it.
    public var automaticallyUseLocalAI = false
    public var shortcut: KeyboardShortcut = .suggested
    public var userCity = ""
    public var userRegion = ""
    public var userCountry = ""
    public var userTimezone = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case provider, model, responseMode, webSearchMaxUses, automaticallyUseLocalAI
        case shortcut, userCity, userRegion, userCountry, userTimezone
    }

    /// Tolerant decoding: a missing or invalid field falls back to its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try c.decodeIfPresent(String.self, forKey: .provider), let value = ProviderKind(rawValue: raw) {
            provider = value
        }
        let storedModel = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        model = storedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.defaultModel : storedModel
        if let raw = try c.decodeIfPresent(String.self, forKey: .responseMode) {
            responseMode = ResponseMode(storedValue: raw)
        }
        if let uses = try c.decodeIfPresent(Int.self, forKey: .webSearchMaxUses), (1...20).contains(uses) {
            webSearchMaxUses = uses
        }
        automaticallyUseLocalAI = try c.decodeIfPresent(Bool.self, forKey: .automaticallyUseLocalAI) ?? false
        shortcut = (try c.decodeIfPresent(KeyboardShortcut.self, forKey: .shortcut) ?? .suggested).normalized
        userCity = try c.decodeIfPresent(String.self, forKey: .userCity) ?? ""
        userRegion = try c.decodeIfPresent(String.self, forKey: .userRegion) ?? ""
        userCountry = try c.decodeIfPresent(String.self, forKey: .userCountry) ?? ""
        userTimezone = try c.decodeIfPresent(String.self, forKey: .userTimezone) ?? ""
    }

    public var location: RequestLocation {
        RequestLocation(city: userCity, region: userRegion, country: userCountry, timezone: userTimezone)
    }
}

public struct RequestLocation: Equatable, Sendable {
    public var city = ""
    public var region = ""
    public var country = ""
    public var timezone = ""

    public init(city: String = "", region: String = "", country: String = "", timezone: String = "") {
        self.city = city
        self.region = region
        self.country = country
        self.timezone = timezone
    }

    var parts: [String] {
        [city, region, country, timezone]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
