import Foundation

/// Runs one search against the selected MySQL server or the local SQLite file.
actor LicenseDatabase {
    private let url: URL
    private var engine: DatabaseEngine
    private var settings: ConnectionSettings

    /// SQLite-only database used by tests.
    init(url: URL) {
        self.url = url
        self.engine = .sqlite
        self.settings = .standard
    }

    init(engine: DatabaseEngine, settings: ConnectionSettings) {
        self.url = LicenseStore.databaseURL
        self.engine = engine
        self.settings = settings.normalized()
    }

    func use(engine: DatabaseEngine, settings: ConnectionSettings) {
        self.engine = engine
        self.settings = settings.normalized()
    }

    func search(_ query: LicenseQuery) async throws -> [LicenseRecord] {
        switch engine {
        case .sqlite:
            try searchSQLite(query)
        case .mysql:
            try await MySQLLicenseDatabase.search(query, settings: settings)
        }
    }

    private func searchSQLite(_ query: LicenseQuery) throws -> [LicenseRecord] {
        guard let statement = LicenseSQL.statement(for: query) else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DatabaseError.message("The license database has not been created.")
        }
        let database = try SQLiteDatabase(path: url.path, readonly: true)
        let rows = try database.query(statement.sql, parameters: statement.parameters)
        return rows.map { Self.record(from: $0, titleCase: query.applyTitleCase) }
    }

    private static func record(from row: [String: String], titleCase: Bool) -> LicenseRecord {
        func value(_ name: String) -> String {
            (row[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
