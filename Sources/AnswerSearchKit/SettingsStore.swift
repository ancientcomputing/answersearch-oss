import Foundation

/// Reads and writes `config.json` under Application Support. Set `ANSWERSEARCH_APP_SUPPORT_DIR`
/// to relocate it (used by tests and for running a throwaway profile).
public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = SettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func supportDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["ANSWERSEARCH_APP_SUPPORT_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "AnswerSearch", directoryHint: .isDirectory)
    }

    public static func defaultFileURL() -> URL {
        supportDirectory().appending(path: "config.json")
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path(percentEncoded: false)
        )
    }

    public func delete() throws {
        guard exists else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
