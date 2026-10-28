import Foundation

struct LicenseQuery: Equatable, Sendable {
    var callSign: String
    var firstName: String
    var lastName: String
    var city: String
    var state: String
    var licenseStatuses: Set<String>
    var operatorClasses: Set<String>
    var applyTitleCase: Bool

    var hasCriteria: Bool {
        !Self.trimmed(callSign).isEmpty
            || !Self.trimmed(firstName).isEmpty
            || !Self.trimmed(lastName).isEmpty
            || !Self.trimmed(city).isEmpty
            || !Self.trimmed(state).isEmpty
    }

    fileprivate static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SQLStatement: Equatable, Sendable {
    var sql: String
    var parameters: [String]
}

/// The same search the React app sends to `fcc/server/fccapp.py`.
/// Call sign and state are exact. First name, last name, and city are prefixes.
/// An empty license-status or operator-class set does not filter that column.
enum LicenseSQL {
    static func statement(for query: LicenseQuery) -> SQLStatement? {
        let callSign = LicenseQuery.trimmed(query.callSign).uppercased()
        let firstName = LicenseQuery.trimmed(query.firstName)
        let lastName = LicenseQuery.trimmed(query.lastName)
        let city = LicenseQuery.trimmed(query.city)
        let state = LicenseQuery.trimmed(query.state).uppercased()

        if callSign.isEmpty && firstName.isEmpty && lastName.isEmpty && city.isEmpty && state.isEmpty {
            return nil
        }

        var clauses: [String] = []
        var parameters: [String] = []

        if !callSign.isEmpty {
            clauses.append("en.call_sign = ?")
            parameters.append(callSign)
        }
        if !firstName.isEmpty {
            clauses.append("en.first_name LIKE ?" + sqlLikeEscape)
            parameters.append(likePrefix(firstName))
        }
        if !lastName.isEmpty {
            clauses.append("en.last_name LIKE ?" + sqlLikeEscape)
            parameters.append(likePrefix(lastName))
        }
        if !city.isEmpty {
            clauses.append("en.city LIKE ?" + sqlLikeEscape)
            parameters.append(likePrefix(city))
        }
        if !state.isEmpty {
            clauses.append("en.state = ?")
            parameters.append(state)
        }

        let statuses = LicenseStatus.allCases.map(\.rawValue).filter { query.licenseStatuses.contains($0) }
        if !statuses.isEmpty {
            clauses.append("hd.license_status IN (\(placeholders(statuses.count)))")
            parameters.append(contentsOf: statuses)
        }

        let classes = OperatorClass.allCases.map(\.rawValue).filter { query.operatorClasses.contains($0) }
        if !classes.isEmpty {
            clauses.append("am.operator_class IN (\(placeholders(classes.count)))")
            parameters.append(contentsOf: classes)
        }

        let sql = """
        SELECT en.call_sign AS call_sign,
               en.first_name AS first_name,
               en.last_name AS last_name,
               en.street_address AS street_address,
               en.city AS city,
               en.state AS state,
               en.zip AS zip_code,
               am.operator_class AS operator_class,
               hd.license_status AS license_status,
               en.frn AS frn,
               am.region_code AS region_code,
               IFNULL(dmr.radio_id, '') AS dmr_id
        FROM en
        JOIN hd ON hd.sys_id = en.sys_id
        JOIN am ON am.sys_id = en.sys_id
        LEFT JOIN dmr ON dmr.call_sign = en.call_sign
        WHERE \(clauses.joined(separator: "\n  AND "))
        ORDER BY en.last_name ASC, en.first_name ASC
        """
        return SQLStatement(sql: sql, parameters: parameters)
    }

    /// SQLite needs an explicit escape character. The clause is `ESCAPE '\'`.
    private static let sqlLikeEscape = " ESCAPE " + "'" + "\\" + "'"

    /// Prefix match with `%` and `_` treated as ordinary characters.
    static func likePrefix(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 1)
        for character in value {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        escaped.append("%")
        return escaped
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
