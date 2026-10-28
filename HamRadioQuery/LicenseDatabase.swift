import Foundation
import Logging
import MySQLNIO
import NIOCore
import NIOPosix

enum DatabaseError: LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

enum LoggingBootstrap {
    static func configure() {
        _ = once
    }

    private static let once: Void = {
        LoggingSystem.bootstrap { _ in
            SwiftLogNoOpLogHandler()
        }
    }()
}

/// Opens a short-lived connection to the FCC MariaDB database and runs one search.
actor LicenseDatabase {
    private var settings: ConnectionSettings

    init(settings: ConnectionSettings) {
        self.settings = settings.normalized()
    }

    func update(settings: ConnectionSettings) {
        self.settings = settings.normalized()
    }

    static func test(_ settings: ConnectionSettings) async throws {
        let database = LicenseDatabase(settings: settings)
        try await database.ping()
    }

    func ping() async throws {
        let settings = self.settings
        let connection = try await open(settings)
        do {
            _ = try await connection.query("SELECT 1").get()
            try? await connection.close().get()
        } catch {
            try? await connection.close().get()
            throw describe(error, settings: settings)
        }
    }

    func search(_ query: LicenseQuery) async throws -> [LicenseRecord] {
        guard let statement = LicenseSQL.statement(for: query) else { return [] }
        let settings = self.settings
        let connection = try await open(settings)
        do {
            let binds = statement.parameters.map { MySQLData(string: $0) }
            let rows = try await connection.query(statement.sql, binds).get()
            try? await connection.close().get()
            return rows.map { Self.record(from: $0, titleCase: query.applyTitleCase) }
        } catch {
            try? await connection.close().get()
            throw describe(error, settings: settings)
        }
    }

    private func open(_ settings: ConnectionSettings) async throws -> MySQLConnection {
        try validate(settings)
        LoggingBootstrap.configure()
        do {
            let address = try SocketAddress.makeAddressResolvingHost(settings.host, port: settings.port)
            return try await MySQLConnection.connect(
                to: address,
                username: settings.username,
                database: settings.database,
                password: settings.password,
                tlsConfiguration: nil,
                serverHostname: settings.host,
                on: MultiThreadedEventLoopGroup.singleton.any()
            ).get()
        } catch {
            throw describe(error, settings: settings)
        }
    }

    private func validate(_ settings: ConnectionSettings) throws {
        if settings.host.isEmpty {
            throw DatabaseError.message("Enter a database host in Settings.")
        }
        if !(1...65535).contains(settings.port) {
            throw DatabaseError.message("Port must be between 1 and 65535.")
        }
        if settings.database.isEmpty {
            throw DatabaseError.message("Enter a database name in Settings.")
        }
        if settings.username.isEmpty {
            throw DatabaseError.message("Enter a database username in Settings.")
        }
    }

    private func describe(_ error: Error, settings: ConnectionSettings) -> DatabaseError {
        if let error = error as? DatabaseError {
            return error
        }
        let raw = String(describing: error)
        let lower = raw.lowercased()
        if lower.contains("connection refused") || lower.contains("connection reset") || lower.contains("timed out") {
            return .message("Could not connect to MySQL at \(settings.host):\(settings.port). Check that the database is running, or update the connection in Settings.")
        }
        if lower.contains("access denied") {
            return .message("The database rejected \(settings.username). Check the username and password in Settings.")
        }
        if lower.contains("unknown database") {
            return .message("Database “\(settings.database)” was not found on \(settings.host).")
        }
        return .message("Database error: \(raw)")
    }

    private static func record(from row: MySQLRow, titleCase: Bool) -> LicenseRecord {
        func value(_ name: String) -> String {
            guard let data = row.column(name), let string = data.string else { return "" }
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func shape(_ text: String) -> String {
            titleCase ? TitleCasing.apply(text) : text
        }
        return LicenseRecord(
            callSign: value("call_sign"),
            firstName: shape(value("first_name")),
            lastName: shape(value("last_name")),
            streetAddress: shape(value("street_address")),
            city: shape(value("city")),
            state: value("state"),
            zip: value("zip_code"),
            operatorClass: value("operator_class"),
            licenseStatus: value("license_status"),
            frn: value("frn"),
            regionCode: value("region_code"),
            dmrID: value("dmr_id")
        )
    }
}
