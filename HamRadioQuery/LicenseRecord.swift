import Foundation

struct LicenseRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let callSign: String
    let firstName: String
    let lastName: String
    let streetAddress: String
    let city: String
    let state: String
    let zip: String
    let operatorClass: String
    let licenseStatus: String
    let frn: String
    let regionCode: String
    let dmrID: String

    init(
        id: UUID = UUID(),
        callSign: String,
        firstName: String,
        lastName: String,
        streetAddress: String,
        city: String,
        state: String,
        zip: String,
        operatorClass: String,
        licenseStatus: String,
        frn: String,
        regionCode: String,
        dmrID: String
    ) {
        self.id = id
        self.callSign = callSign
        self.firstName = firstName
        self.lastName = lastName
        self.streetAddress = streetAddress
        self.city = city
        self.state = state
        self.zip = zip
        self.operatorClass = operatorClass
        self.licenseStatus = licenseStatus
        self.frn = frn
        self.regionCode = regionCode
        self.dmrID = dmrID
    }

    /// Case-insensitive match against every value shown in the table, plus the
    /// spelled-out license status and operator class.
    func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return true }
        let fields = [
            callSign, firstName, lastName, streetAddress, city, state, zip,
            operatorClass, OperatorClass.title(for: operatorClass),
            licenseStatus, LicenseStatus.title(for: licenseStatus),
            frn, regionCode, dmrID,
        ]
        return fields.contains { $0.lowercased().contains(needle) }
    }

    var columns: [String] {
        [
            callSign, firstName, lastName, streetAddress, city, state, zip,
            operatorClass, licenseStatus, frn, regionCode, dmrID,
        ]
    }

    var tabSeparated: String {
        columns.joined(separator: "\t")
    }

    static let csvHeader = [
        "Call Sign", "First Name", "Last Name", "Street Address", "City", "State",
        "ZIP", "Operator Class", "License Status", "FRN", "Region Code", "DMR ID",
    ]

    static func csv(_ records: [LicenseRecord]) -> String {
        let lines = [csvHeader.map(csvField).joined(separator: ",")]
            + records.map { $0.columns.map(csvField).joined(separator: ",") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static let samples: [LicenseRecord] = [
        LicenseRecord(
            callSign: "WD6BQX", firstName: "Arthur", lastName: "Aronsen",
            streetAddress: "1501 Jordan Ln", city: "Emmett", state: "ID", zip: "83617",
            operatorClass: "G", licenseStatus: "A", frn: "0002436145", regionCode: "7", dmrID: ""
        ),
        LicenseRecord(
            callSign: "KC5KKX", firstName: "Michael", lastName: "Asplund",
            streetAddress: "2068 County Line Rd", city: "Emmett", state: "ID", zip: "83617",
            operatorClass: "E", licenseStatus: "A", frn: "0002031631", regionCode: "7", dmrID: ""
        ),
        LicenseRecord(
            callSign: "KI7PSO", firstName: "Tony", lastName: "Barningham",
            streetAddress: "9734 Bill Burns Rd", city: "Emmett", state: "ID", zip: "83617",
            operatorClass: "E", licenseStatus: "A", frn: "0026822262", regionCode: "7", dmrID: "3229049"
        ),
    ]
}
