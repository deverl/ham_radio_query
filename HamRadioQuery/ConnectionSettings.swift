import Foundation
import Security

enum DatabaseEngine: String, CaseIterable, Identifiable, Sendable {
    case mysql
    case sqlite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mysql: "MySQL"
        case .sqlite: "SQLite"
        }
    }

    private static let key = "HamRadioQuery.engine"

    static func load() -> DatabaseEngine {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let engine = DatabaseEngine(rawValue: raw)
        else { return .sqlite }
        return engine
    }

    static func save(_ engine: DatabaseEngine) {
        UserDefaults.standard.set(engine.rawValue, forKey: key)
    }
}

struct ConnectionSettings: Equatable, Sendable {
    var host: String
    var port: Int
    var database: String
    var username: String
    var password: String

    /// Same local database the FCC web app uses.
    static let standard = ConnectionSettings(
        host: "127.0.0.1",
        port: 3306,
        database: "fcc",
        username: "fccuser",
        password: "fccuser"
    )

    func normalized() -> ConnectionSettings {
        var copy = self
        copy.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.database = database.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private enum Keys {
        static let host = "HamRadioQuery.host"
        static let port = "HamRadioQuery.port"
        static let database = "HamRadioQuery.database"
        static let username = "HamRadioQuery.username"
    }

    static func load() -> ConnectionSettings {
        let defaults = UserDefaults.standard
        var settings = ConnectionSettings.standard
        if let host = defaults.string(forKey: Keys.host) {
            settings.host = host
        }
        if defaults.object(forKey: Keys.port) != nil {
            let port = defaults.integer(forKey: Keys.port)
            if (1...65535).contains(port) {
                settings.port = port
            }
        }
        if let database = defaults.string(forKey: Keys.database) {
            settings.database = database
        }
        if let username = defaults.string(forKey: Keys.username) {
            settings.username = username
        }
        if let password = PasswordStore.load() {
            settings.password = password
        }
        return settings
    }

    /// Saves host, port, database, and username in UserDefaults and the password in the Keychain.
    /// Returns a warning when the password could not be stored.
    @discardableResult
    static func save(_ settings: ConnectionSettings) -> String? {
        let settings = settings.normalized()
        let defaults = UserDefaults.standard
        defaults.set(settings.host, forKey: Keys.host)
        defaults.set(settings.port, forKey: Keys.port)
        defaults.set(settings.database, forKey: Keys.database)
        defaults.set(settings.username, forKey: Keys.username)
        if PasswordStore.save(settings.password) {
            return nil
        }
        return "The connection was saved, but the password could not be stored in the Keychain. It will be used until you quit."
    }
}

private enum PasswordStore {
    private static let service = "com.dstokes.HamRadioQuery"
    private static let account = "database-password"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
