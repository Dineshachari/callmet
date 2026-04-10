import Foundation

final class BotSettingsStore {
    static let shared = BotSettingsStore()

    private let displayNameKey = "botDisplayName"
    private let defaultDisplayName = "MeetScribe"

    private init() {}

    var displayName: String {
        get {
            let value = UserDefaults.standard.string(forKey: displayNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
            return defaultDisplayName
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: displayNameKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: displayNameKey)
            }
        }
    }
}
