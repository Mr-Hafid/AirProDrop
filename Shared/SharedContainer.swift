import Foundation

enum SharedContainer {
    static let appGroupIdentifier = "group.com.mrhafid.airpro"
    static let macSideDefaultsKey = "airpro.macSide"

    static var defaults: UserDefaults {
        #if os(iOS)
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
        #else
        .standard
        #endif
    }

    static func string(forKey key: String) -> String? {
        if let shared = defaults.string(forKey: key) {
            return shared
        }
        guard let legacy = UserDefaults.standard.string(forKey: key) else { return nil }
        defaults.set(legacy, forKey: key)
        return legacy
    }
}
