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
        #expect(statement.sql.contains("LEFT JOIN dmr ON dmr.call_sign = en.call_sign"))
        #expect(statement.sql.contains("ORDER BY en.last_name ASC, en.first_name ASC"))
        #expect(statement.parameters == ["WD6BQX", "A", "E", "G"])
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
        #expect(statement.parameters == ["Jo\\_n%", "100\\%%", "ID"])
        #expect(!whereClause.contains("license_status"))
        #expect(!whereClause.contains("operator_class"))
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

struct DatabaseTests {
    @Test func emmettIdahoMatchesTheWebLookup() async throws {
        let database = LicenseDatabase(settings: .standard)
        let records = try await database.search(LicenseQuery(
            callSign: "",
            firstName: "",
            lastName: "",
            city: "emmett",
            state: "id",
            licenseStatuses: ["A"],
            operatorClasses: Set(OperatorClass.allCases.map(\.rawValue)),
            applyTitleCase: true
        ))

        let arthur = try #require(records.first { $0.callSign == "WD6BQX" })
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

        let tony = try #require(records.first { $0.callSign == "KI7PSO" })
        #expect(tony.firstName == "Tony")
        #expect(tony.lastName == "Barningham")
        #expect(tony.streetAddress == "9734 Bill Burns Rd")
        #expect(tony.dmrID == "3229049")
        #expect(tony.frn == "0026822262")
        #expect(tony.operatorClass == "E")

        let names = records.map(\.lastName)
        let aronsen = try #require(names.firstIndex(of: "Aronsen"))
        let barningham = try #require(names.firstIndex(of: "Barningham"))
        #expect(aronsen < barningham)
        #expect(records.count > 50)
    }

    @Test func exactCallSignDoesNotReturnOtherStations() async throws {
        let database = LicenseDatabase(settings: .standard)
        let records = try await database.search(LicenseQuery(
            callSign: "wd6bqx",
            firstName: "",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            operatorClasses: Set(OperatorClass.allCases.map(\.rawValue)),
            applyTitleCase: true
        ))
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.callSign == "WD6BQX" })
    }
}
