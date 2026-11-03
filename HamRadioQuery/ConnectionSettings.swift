import Foundation
import Security

enum DatabaseEngine: String, CaseIterable, Identifiable, Sendable {
    case mysql
    case postgres
    case sqlite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mysql: "MySQL"
        case .postgres: "PostgreSQL"
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

    /// Local PostgreSQL defaults. The database name and account match the MySQL defaults; the port does not.
    static let postgres = ConnectionSettings(
        host: "127.0.0.1",
        port: 5432,
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
        static let postgresHost = "HamRadioQuery.postgres.host"
        static let postgresPort = "HamRadioQuery.postgres.port"
        static let postgresDatabase = "HamRadioQuery.postgres.database"
        static let postgresUsername = "HamRadioQuery.postgres.username"
    }

    static func load() -> ConnectionSettings {
        load(for: .mysql)
    }

    static func load(for engine: DatabaseEngine) -> ConnectionSettings {
        if engine == .postgres {
            return loadStored(
                fallback: .postgres,
                hostKey: Keys.postgresHost,
                portKey: Keys.postgresPort,
                databaseKey: Keys.postgresDatabase,
                usernameKey: Keys.postgresUsername,
                account: PasswordStore.postgresAccount
            )
        }
        return loadStored(
            fallback: .standard,
            hostKey: Keys.host,
            portKey: Keys.port,
            databaseKey: Keys.database,
            usernameKey: Keys.username,
            account: PasswordStore.mysqlAccount
        )
    }

    /// Saves host, port, database, and username in UserDefaults and the password in the Keychain.
    /// Returns a warning when the password could not be stored.
    @discardableResult
    static func save(_ settings: ConnectionSettings) -> String? {
        save(settings, for: .mysql)
    }

    @discardableResult
    static func save(_ settings: ConnectionSettings, for engine: DatabaseEngine) -> String? {
        let settings = settings.normalized()
        let defaults = UserDefaults.standard
        let postgres = engine == .postgres
        defaults.set(settings.host, forKey: postgres ? Keys.postgresHost : Keys.host)
        defaults.set(settings.port, forKey: postgres ? Keys.postgresPort : Keys.port)
        defaults.set(settings.database, forKey: postgres ? Keys.postgresDatabase : Keys.database)
        defaults.set(settings.username, forKey: postgres ? Keys.postgresUsername : Keys.username)
        let account = postgres ? PasswordStore.postgresAccount : PasswordStore.mysqlAccount
        if PasswordStore.save(settings.password, account: account) {
            return nil
        }
        return "The connection was saved, but the password could not be stored in the Keychain. It will be used until you quit."
    }

    private static func loadStored(
        fallback: ConnectionSettings,
        hostKey: String,
        portKey: String,
        databaseKey: String,
        usernameKey: String,
        account: String
    ) -> ConnectionSettings {
        let defaults = UserDefaults.standard
        var settings = fallback
        if let host = defaults.string(forKey: hostKey) {
            settings.host = host
        }
        if defaults.object(forKey: portKey) != nil {
            let port = defaults.integer(forKey: portKey)
            if (1...65535).contains(port) {
                settings.port = port
            }
        }
        if let database = defaults.string(forKey: databaseKey) {
            settings.database = database
        }
        if let username = defaults.string(forKey: usernameKey) {
            settings.username = username
        }
        if let password = PasswordStore.load(account: account) {
            settings.password = password
        }
        return settings
    }
}

private enum PasswordStore {
    private static let service = "us.ds6.HamRadioQuery"
    static let mysqlAccount = "database-password"
    static let postgresAccount = "postgres-password"

    static func load(account: String) -> String? {
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

    static func save(_ password: String, account: String) -> Bool {
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
