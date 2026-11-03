import Foundation
import Logging
import NIOCore
import PostgresNIO

enum PostgresLicenseDatabase {
    static func test(_ settings: ConnectionSettings) async throws {
        try await ping(settings.normalized())
    }

    static func search(_ query: LicenseQuery, settings: ConnectionSettings) async throws -> [LicenseRecord] {
        guard let statement = LicenseSQL.statement(for: query, engine: .postgres) else { return [] }
        let settings = settings.normalized()
        let connection = try await open(settings)
        do {
            var binds = PostgresBindings(capacity: statement.parameters.count)
            for parameter in statement.parameters {
                binds.append(parameter)
            }
            let rows = try await connection.query(
                PostgresQuery(unsafeSQL: statement.sql, binds: binds),
                logger: logger
            )
            var records: [LicenseRecord] = []
            for try await row in rows {
                records.append(record(from: row, titleCase: query.applyTitleCase))
            }
            try await connection.close()
            return records
        } catch {
            try? await connection.close()
            throw describe(error, settings: settings)
        }
    }

    private static func ping(_ settings: ConnectionSettings) async throws {
        let connection = try await open(settings)
        do {
            _ = try await connection.query(PostgresQuery(unsafeSQL: "SELECT 1"), logger: logger)
            try await connection.close()
        } catch {
            try? await connection.close()
            throw describe(error, settings: settings)
        }
    }

    private static func open(_ settings: ConnectionSettings) async throws -> PostgresConnection {
        try validate(settings)
        LoggingBootstrap.configure()
        do {
            let configuration = PostgresConnection.Configuration(
                host: settings.host,
                port: settings.port,
                username: settings.username,
                password: settings.password,
                database: settings.database,
                tls: .disable
            )
            return try await PostgresConnection.connect(
                on: MultiThreadedEventLoopGroup.singleton.any(),
                configuration: configuration,
                id: Int.random(in: 1...Int.max),
                logger: logger
            )
        } catch {
            throw describe(error, settings: settings)
        }
    }

    private static let logger = Logger(label: "us.ds6.HamRadioQuery.postgres")

    private static func validate(_ settings: ConnectionSettings) throws {
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

    private static func describe(_ error: Error, settings: ConnectionSettings) -> DatabaseError {
        if let error = error as? DatabaseError {
            return error
        }
        let raw = String(describing: error)
        let lower = raw.lowercased()
        if lower.contains("connection refused") || lower.contains("connection reset") || lower.contains("timed out") || lower.contains("nodename nor servname") {
            return .message("Could not connect to PostgreSQL at \(settings.host):\(settings.port). Check that the database is running, or update the connection in Settings.")
        }
        if lower.contains("password authentication failed") || lower.contains("authentication failed") {
            return .message("The database rejected \(settings.username). Check the username and password in Settings.")
        }
        if lower.contains("does not exist") {
            return .message("Database “\(settings.database)” was not found on \(settings.host).")
        }
        return .message("Database error: \(raw)")
    }

    private static func record(from row: PostgresRow, titleCase: Bool) -> LicenseRecord {
        let cells = row.makeRandomAccess()
        func value(_ name: String) -> String {
            guard cells.contains(name) else { return "" }
            let text = (try? cells[name].decode(String.self)) ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
