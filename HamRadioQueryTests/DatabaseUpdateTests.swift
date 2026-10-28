import Foundation
import Testing
@testable import HamRadioQuery

struct DatabaseUpdateTests {
    @Test func licenseSQLUsesAbsolutePathsAndSkipsTheSampleQuery() throws {
        let sql = DatabaseSchema.licenseSQL(
            database: "fcc",
            hd: "/tmp/ham-radio-lookup/HD.dat",
            en: "/tmp/ham-radio-lookup/EN.dat",
            am: "/tmp/ham-radio-lookup/AM.dat"
        )
        #expect(sql.contains("CREATE DATABASE IF NOT EXISTS `fcc`"))
        #expect(sql.contains("DROP TABLE IF EXISTS hd"))
        #expect(sql.contains("LOAD DATA LOCAL INFILE '/tmp/ham-radio-lookup/HD.dat'"))
        #expect(sql.contains("LOAD DATA LOCAL INFILE '/tmp/ham-radio-lookup/EN.dat'"))
        #expect(sql.contains("LOAD DATA LOCAL INFILE '/tmp/ham-radio-lookup/AM.dat'"))
        #expect(sql.contains("FIELDS TERMINATED BY '|'"))
        #expect(sql.contains("CREATE INDEX en_call_sign_index ON en (call_sign)"))
        #expect(!sql.contains("W7DNS"))
    }

    @Test func dmrSQLLoadsTheHeaderRow() {
        let sql = DatabaseSchema.dmrSQL(database: "fcc", csv: "/tmp/ham-radio-lookup/user.csv")
        #expect(sql.contains("USE `fcc`"))
        #expect(sql.contains("DROP TABLE IF EXISTS dmr"))
        #expect(sql.contains("LOAD DATA LOCAL INFILE '/tmp/ham-radio-lookup/user.csv'"))
        #expect(sql.contains("FIELDS TERMINATED BY ','"))
        #expect(!sql.contains("IGNORE 1 LINES"))
    }

    @Test func databaseNameMustBeAPlainIdentifier() throws {
        #expect(throws: DatabaseUpdateError.self) {
            try DatabaseSchema.validatedName("fcc; DROP TABLE hd")
        }
        #expect(throws: DatabaseUpdateError.self) {
            try DatabaseSchema.validatedName("")
        }
        let name = try DatabaseSchema.validatedName(" fcc ")
        #expect(name == "fcc")
    }

    @Test func sqlStringEscapesQuotes() {
        #expect(DatabaseSchema.sqlString("/tmp/a'b\\c") == "'/tmp/a\\'b\\\\c'")
    }

    @Test func clientFileIsOwnerReadableOnly() throws {
        let url = URL(fileURLWithPath: "/tmp/ham-radio-query-cnf-test.cnf")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = ConnectionSettings.standard
        settings.password = "a\"b\\c"
        try DatabaseUpdater.writeClientFile(settings: settings, to: url)
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        #expect(mode.uint16Value == 0o600)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("password=\"a\\\"b\\\\c\""))
        #expect(text.contains("local-infile=1"))
        #expect(!FileManager.default.fileExists(atPath: DatabaseUpdater.directory.appendingPathComponent(".mysql-client.cnf").path))
    }

    @Test func localInfileLoadsAScratchTable() throws {
        let directory = URL(fileURLWithPath: "/tmp/ham-radio-query-probe", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let csv = directory.appendingPathComponent("probe.csv")
        try Data("3229049,KI7PSO\n".utf8).write(to: csv)
        let database = try DatabaseSchema.validatedName(ConnectionSettings.standard.database)
        let quoted = DatabaseSchema.quotedIdentifier(database)
        let settings = ConnectionSettings.standard

        defer {
            _ = try? DatabaseUpdater.runMySQL(
                sql: "USE \(quoted); DROP TABLE IF EXISTS _ham_radio_query_probe;",
                settings: settings,
                workingDirectory: directory
            )
        }

        let loaded = try DatabaseUpdater.runMySQL(
            sql: """
            USE \(quoted);
            DROP TABLE IF EXISTS _ham_radio_query_probe;
            CREATE TABLE _ham_radio_query_probe (
                radio_id VARCHAR(20),
                call_sign VARCHAR(20)
            );
            LOAD DATA LOCAL INFILE \(DatabaseSchema.sqlString(csv.path))
            INTO TABLE _ham_radio_query_probe
            FIELDS TERMINATED BY ','
            LINES TERMINATED BY '\\n';
            SELECT COUNT(*) FROM _ham_radio_query_probe;
            """,
            settings: settings,
            workingDirectory: directory
        )
        #expect(loaded.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".mysql-client.cnf").path))
    }
}
