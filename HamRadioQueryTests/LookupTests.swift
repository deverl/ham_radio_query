import Foundation
import Testing
@testable import HamRadioQuery

struct QuerySQLTests {
    @Test func blankQueryIsRejected() {
        let query = LicenseQuery(
            callSign: "  ",
            firstName: "",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            operatorClasses: ["E"],
            applyTitleCase: true
        )
        #expect(query.hasCriteria == false)
        #expect(LicenseSQL.statement(for: query) == nil)
    }

    @Test func callSignIsExactAndFiltersFollowTheWebApp() throws {
        let query = LicenseQuery(
            callSign: " wd6bqx ",
            firstName: "",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            operatorClasses: ["G", "E"],
            applyTitleCase: true
        )
        let statement = try #require(LicenseSQL.statement(for: query))
        #expect(statement.sql.contains("en.call_sign = ?"))
        #expect(statement.sql.contains("hd.license_status IN (?)"))
        #expect(statement.sql.contains("am.operator_class IN (?, ?)"))
        #expect(statement.sql.contains("IFNULL(dmr.radio_id, '') AS dmr_id"))
        #expect(statement.sql.contains("LEFT JOIN dmr ON dmr.call_sign = en.call_sign"))
        #expect(statement.sql.contains("ORDER BY en.last_name ASC, en.first_name ASC"))
        #expect(statement.parameters == ["WD6BQX", "A", "E", "G"])
    }

    @Test func postgresSearchUsesNumberedPlaceholders() throws {
        let query = LicenseQuery(
            callSign: "w7dns",
            firstName: "Jo_n",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            operatorClasses: [],
            applyTitleCase: true
        )
        let statement = try #require(LicenseSQL.statement(for: query, engine: .postgres))
        #expect(statement.sql.contains("en.call_sign = $1"))
        #expect(statement.sql.contains("en.first_name ILIKE $2 ESCAPE '!'"))
        #expect(statement.sql.contains("COALESCE(dmr.radio_id, '') AS dmr_id"))
        #expect(!statement.sql.contains("IFNULL"))
        #expect(statement.parameters == ["W7DNS", "Jo!_n%", "A"])
    }

    @Test func namesAndCityAreLiteralPrefixes() throws {
        let query = LicenseQuery(
            callSign: "",
            firstName: "Jo_n",
            lastName: "",
            city: "100%",
            state: "id",
            licenseStatuses: [],
            operatorClasses: [],
            applyTitleCase: false
        )
        let statement = try #require(LicenseSQL.statement(for: query))
        let whereClause = statement.sql.components(separatedBy: "WHERE ").last ?? ""
        #expect(statement.parameters == ["Jo!_n%", "100!%%", "ID"])
        #expect(whereClause.contains("ESCAPE '!'"))
        #expect(!whereClause.contains("license_status"))
        #expect(!whereClause.contains("operator_class"))
    }

    @Test func frnAndDmrIDAreExact() throws {
        let query = LicenseQuery(
            callSign: "",
            frn: " 0001234567 ",
            dmrID: "3216068",
            firstName: "",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            operatorClasses: [],
            applyTitleCase: true
        )
        #expect(query.hasCriteria)
        let statement = try #require(LicenseSQL.statement(for: query))
        #expect(statement.sql.contains("en.frn = ?"))
        #expect(statement.sql.contains("dmr.radio_id = ?"))
        #expect(statement.sql.contains("CAST(hd.sys_id AS TEXT) AS sys_id"))
        #expect(statement.parameters == ["0001234567", "3216068", "A"])

        let postgres = try #require(LicenseSQL.statement(for: query, engine: .postgres))
        #expect(postgres.sql.contains("en.frn = $1"))
        #expect(postgres.sql.contains("dmr.radio_id = $2"))
        #expect(postgres.sql.contains("CAST(hd.sys_id AS TEXT) AS sys_id"))

        let mysql = try #require(LicenseSQL.statement(for: query, engine: .mysql))
        #expect(mysql.sql.contains("CAST(hd.sys_id AS CHAR) AS sys_id"))
        #expect(!mysql.sql.contains("AS TEXT"))
    }

    @Test func licenseLinkBuildsTheChosenPage() throws {
        let qrz = try #require(LicenseLink.qrz.page(callSign: " w1aw ", systemID: "780866"))
        #expect(qrz == .url(URL(string: "https://www.qrz.com/db/W1AW")!))
        let radioID = try #require(LicenseLink.radioid.page(callSign: "W1AW", systemID: "780866"))
        #expect(radioID == .url(URL(string: "https://radioid.net/database/search?callsign=W1AW")!))
        let fcc = try #require(LicenseLink.fcc.page(callSign: "W1AW", systemID: " 780866 "))
        #expect(fcc == .url(URL(string: "https://wireless2.fcc.gov/UlsApp/UlsSearch/license.jsp?licKey=780866")!))
        #expect(LicenseLink.fcc.page(callSign: "W1AW", systemID: "") == nil)
        #expect(LicenseLink.fcc.page(callSign: "W1AW", systemID: "780866;drop") == nil)
        #expect(LicenseLink.qrz.page(callSign: "W1 AW", systemID: "780866") == nil)
        #expect(LicenseLink.qrz.menuTitle == "Open This License at QRZ")
    }

    @Test func titleCaseMatchesLicenseFormatting() {
        #expect(TitleCasing.apply("ARTHUR") == "Arthur")
        #expect(TitleCasing.apply("ARONSEN") == "Aronsen")
        #expect(TitleCasing.apply("1501 Jordan Ln") == "1501 Jordan Ln")
        #expect(TitleCasing.apply("9734 BILL BURNS RD") == "9734 Bill Burns Rd")
        #expect(TitleCasing.apply("1033 S CHEROKEE AVE") == "1033 S Cherokee Ave")
        #expect(TitleCasing.apply("PO BOX 12") == "PO Box 12")
        #expect(TitleCasing.apply("EMMETT") == "Emmett")
    }

    @Test func filterMatchesAnyColumnAndSpelledOutClass() {
        let record = LicenseRecord.samples[0]
        #expect(record.matches("jordan"))
        #expect(record.matches("GENERAL"))
        #expect(record.matches("83617"))
        #expect(record.matches("active"))
        #expect(!record.matches("boise"))
        #expect(record.columns.contains("General"))
        #expect(record.columns.contains("Active"))
    }
}

@MainActor
struct MissingDatabaseTests {
    @Test func searchExplainsThatTheDatabaseMustBeCreated() {
        let model = LookupModel()
        model.suppressDatabaseNotice = true
        model.engine = .sqlite
        model.freshness = .missing
        model.callSign = "W7DNS"
        model.search()
        #expect(model.databaseNotice == .missing)
        #expect(model.records.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.maintenanceMenuTitle == "Create License Database…")
    }
}

@MainActor
struct ResultSummaryTests {
    @Test func statusLineIncludesQueryTime() {
        let model = LookupModel()
        model.suppressDatabaseNotice = true
        model.records = [LicenseRecord.samples[0]]
        model.queryDuration = 0.048
        #expect(model.resultSummary == "Found 1 matching record in 48 ms")

        model.records = LicenseRecord.samples
        model.queryDuration = 1.24
        #expect(model.resultSummary == "Found 3 matching records in 1.2 seconds")

        model.filter = "jordan"
        #expect(model.resultSummary == "Showing 1 of 3 records in 1.2 seconds")
        #expect(QueryTiming.label(seconds: 1) == "1 second")
        #expect(QueryTiming.label(seconds: 10) == "10 seconds")
        #expect(QueryTiming.label(seconds: 0.0004) == "< 1 ms")
    }
}
