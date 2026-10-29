import Foundation
import Testing
@testable import HamRadioQuery

struct DatabaseUpdateTests {
    @Test func importScriptUsesPipeFilesAndDoesNotIndexYet() {
        let sql = DatabaseSchema.importScript(
            hd: "/tmp/ham-radio-lookup/HD.dat",
            en: "/tmp/ham-radio-lookup/EN.dat",
            am: "/tmp/ham-radio-lookup/AM.dat"
        )
        #expect(sql.contains("CREATE TABLE hd"))
        #expect(sql.contains("CREATE TABLE en"))
        #expect(sql.contains("CREATE TABLE am"))
        #expect(sql.contains(".separator \"|\" \"\\n\""))
        #expect(sql.contains(".import /tmp/ham-radio-lookup/HD.dat hd"))
        #expect(sql.contains(".import /tmp/ham-radio-lookup/EN.dat en"))
        #expect(sql.contains(".import /tmp/ham-radio-lookup/AM.dat am"))
        #expect(!sql.contains("CREATE INDEX"))
        #expect(!sql.contains("W7DNS"))
    }

    @Test func dmrScriptSkipsTheHeader() {
        let sql = DatabaseSchema.dmrScript(csv: "/tmp/ham-radio-lookup/user.csv")
        #expect(sql.contains(".mode csv"))
        #expect(sql.contains(".import --skip 1 /tmp/ham-radio-lookup/user.csv dmr"))
    }

    @Test func sqlStringDoublesQuotes() {
        #expect(DatabaseSchema.sqlString("/tmp/a'b\\c") == "'/tmp/a''b\\c'")
    }

    @Test func mysqlImportUsesLoadData() throws {
        let sql = DatabaseSchema.licenseSQL(
            database: "fcc",
            hd: "/tmp/ham-radio-lookup/HD.dat",
            en: "/tmp/ham-radio-lookup/EN.dat",
            am: "/tmp/ham-radio-lookup/AM.dat"
        )
        #expect(sql.contains("CREATE DATABASE IF NOT EXISTS `fcc`"))
        #expect(sql.contains("LOAD DATA LOCAL INFILE '/tmp/ham-radio-lookup/HD.dat'"))
        #expect(sql.contains("FIELDS TERMINATED BY '|'"))
        #expect(!sql.contains("W7DNS"))
        #expect(throws: DatabaseUpdateError.self) {
            try DatabaseSchema.validatedName("fcc; DROP TABLE hd")
        }
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
    }

    @Test func columnCountsMatchTheFCCFiles() {
        #expect(DatabaseSchema.hdColumns.count == 59)
        #expect(DatabaseSchema.enColumns.count == 30)
        #expect(DatabaseSchema.amColumns.count == 18)
        #expect(DatabaseSchema.dmrColumns.count == 7)
    }

    @Test func missingAndUnreadableFilesNeedToBeCreated() {
        let missing = URL(fileURLWithPath: "/tmp/ham-radio-query-does-not-exist.sqlite")
        #expect(LicenseStore.freshness(at: missing) == .missing)

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("ham-radio-empty-\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: empty.path, contents: Data("not a database".utf8))
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(LicenseStore.freshness(at: empty) == .missing)
    }

    @Test func databaseOlderThanEightDaysIsStale() throws {
        let imported = try #require(LicenseStore.parse("2026-01-01T00:00:00Z"))
        let url = try Fixture.makeDatabase(importedAt: imported)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let eightDays = imported.addingTimeInterval(LicenseStore.maximumAge)
        #expect(LicenseStore.freshness(at: url, now: eightDays) == .current(importedAt: imported))
        #expect(
            LicenseStore.freshness(at: url, now: eightDays.addingTimeInterval(1))
                == .stale(importedAt: imported)
        )
    }

    @Test func pipeAndCSVImportCanBeSearched() async throws {
        let imported = try #require(LicenseStore.parse("2026-10-20T00:00:00Z"))
        let url = try Fixture.makeDatabase(importedAt: imported)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let database = LicenseDatabase(url: url)
        let emmett = try await database.search(LicenseQuery(
            callSign: "",
            firstName: "",
            lastName: "",
            city: "emmett",
            state: "id",
            licenseStatuses: ["A"],
            operatorClasses: Set(OperatorClass.allCases.map(\.rawValue)),
            applyTitleCase: true
        ))
        #expect(emmett.map(\.callSign) == ["WD6BQX", "KI7PSO"])

        let arthur = try #require(emmett.first)
        #expect(arthur.firstName == "Arthur")
        #expect(arthur.lastName == "Aronsen")
        #expect(arthur.streetAddress == "1501 Jordan Ln")
        #expect(arthur.city == "Emmett")
        #expect(arthur.state == "ID")
        #expect(arthur.zip == "83617")
        #expect(arthur.operatorClass == "G")
        #expect(arthur.licenseStatus == "A")
        #expect(arthur.frn == "0002436145")
        #expect(arthur.regionCode == "7")
        #expect(arthur.dmrID == "")

        let tony = emmett[1]
        #expect(tony.firstName == "Tony")
        #expect(tony.lastName == "Barningham")
        #expect(tony.streetAddress == "9734 Bill Burns Rd")
        #expect(tony.dmrID == "3229049")
        #expect(tony.frn == "0026822262")
        #expect(tony.operatorClass == "E")

        let exact = try await database.search(LicenseQuery(
            callSign: "wd6bqx",
            firstName: "",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            operatorClasses: Set(OperatorClass.allCases.map(\.rawValue)),
            applyTitleCase: true
        ))
        #expect(exact.map(\.callSign) == ["WD6BQX"])

        let byName = try await database.search(LicenseQuery(
            callSign: "",
            firstName: "Jo_n",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            operatorClasses: Set(OperatorClass.allCases.map(\.rawValue)),
            applyTitleCase: false
        ))
        #expect(byName.map(\.callSign) == ["N0UND"])

        let byCity = try await database.search(LicenseQuery(
            callSign: "",
            firstName: "",
            lastName: "",
            city: "100%",
            state: "ID",
            licenseStatuses: ["A"],
            operatorClasses: Set(OperatorClass.allCases.map(\.rawValue)),
            applyTitleCase: false
        ))
        #expect(byCity.map(\.callSign) == ["N0UND"])
    }
}

enum Fixture {
    static func makeDatabase(importedAt: Date) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ham-radio-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hd = directory.appendingPathComponent("HD.dat")
        let en = directory.appendingPathComponent("EN.dat")
        let am = directory.appendingPathComponent("AM.dat")
        let csv = directory.appendingPathComponent("user.csv")
        try Data(hdText.utf8).write(to: hd)
        try Data(enText.utf8).write(to: en)
        try Data(amText.utf8).write(to: am)
        try Data(csvText.utf8).write(to: csv)

        let database = directory.appendingPathComponent("licenses.sqlite")
        try DatabaseUpdater.buildDatabase(hd: hd, en: en, am: am, csv: csv, to: database, importedAt: importedAt)
        return database
    }

    private static func row(_ values: [Int: String], columns: Int) -> String {
        var fields = Array(repeating: "", count: columns)
        for (index, value) in values where index < columns {
            fields[index] = value
        }
        return fields.joined(separator: "|")
    }

    private static var hdText: String {
        [
            row([0: "HD", 1: "1", 4: "WD6BQX", 5: "A"], columns: 59),
            row([0: "HD", 1: "2", 4: "KI7PSO", 5: "A"], columns: 59),
            row([0: "HD", 1: "3", 4: "N0UND", 5: "A"], columns: 59),
            row([0: "HD", 1: "4", 4: "N0OTHER", 5: "A"], columns: 59),
        ].joined(separator: "\n") + "\n"
    }

    private static var enText: String {
        [
            row([
                0: "EN", 1: "1", 4: "WD6BQX", 8: "ARTHUR", 10: "ARONSEN",
                15: "1501 JORDAN LN", 16: "EMMETT", 17: "ID", 18: "83617", 22: "0002436145",
            ], columns: 30),
            row([
                0: "EN", 1: "2", 4: "KI7PSO", 8: "TONY", 10: "BARNINGHAM",
                15: "9734 BILL BURNS RD", 16: "EMMETT", 17: "ID", 18: "83617", 22: "0026822262",
            ], columns: 30),
            row([
                0: "EN", 1: "3", 4: "N0UND", 8: "JO_N", 10: "SMITH",
                16: "100%TOWN", 17: "ID",
            ], columns: 30),
            row([
                0: "EN", 1: "4", 4: "N0OTHER", 8: "JOHN", 10: "SMITH",
                16: "1000TOWN", 17: "ID",
            ], columns: 30),
        ].joined(separator: "\n") + "\n"
    }

    private static var amText: String {
        [
            row([0: "AM", 1: "1", 4: "WD6BQX", 5: "G", 7: "7"], columns: 18),
            row([0: "AM", 1: "2", 4: "KI7PSO", 5: "E", 7: "7"], columns: 18),
            row([0: "AM", 1: "3", 4: "N0UND", 5: "T", 7: "0"], columns: 18),
            row([0: "AM", 1: "4", 4: "N0OTHER", 5: "T", 7: "0"], columns: 18),
        ].joined(separator: "\n") + "\n"
    }

    private static let csvText = "RADIO_ID,CALLSIGN,FIRST_NAME,LAST_NAME,CITY,STATE,COUNTRY\n3229049,KI7PSO,Tony,Barningham,Emmett,ID,United States\n"
}
