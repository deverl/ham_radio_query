import Foundation

enum DatabaseSchema {
    static let hdColumns = [
        "record_type", "sys_id", "file_number", "ebf_number", "call_sign", "license_status",
        "radio_service_code", "grant_date", "expired_date", "cancellation_date", "eligibility_rule_num",
        "reserved1", "alien", "alien_government", "alien_corporation", "alien_officer", "alien_control",
        "revoked", "convicted", "adjudged", "reserved2", "common_carrier", "non_common_carrier",
        "private_comm", "fixed", "mobile", "radiolocation", "satellite", "dev_sta_demo",
        "interconnected_service", "certifier_first_name", "certifier_middle_initial", "certifier_last_name",
        "certifier_suffix", "certifier_title", "female", "black_or_african_american", "native_american",
        "hawaiian", "asian", "white", "hispanic", "effective_date", "last_action_date", "auction_id",
        "broadcast_regulatory_status", "band_manager_regulatory_status", "broadcast_services_type",
        "alien_ruling", "licensee_name_change", "whitespace_indicator", "operation_perf_requirement_choice",
        "operation_perf_requirement_answer", "discontinuation_of_service", "regulatory_compliance",
        "_900_mhz_eligibility_cert", "_900_mhz_transition_plan_cert", "_900_mhz_return_spectrum_cert",
        "_900_mhz_payment_cert",
    ]

    static let enColumns = [
        "record_type", "sys_id", "file_number", "ebf_number", "call_sign", "entity_type", "licensee_id",
        "entity_name", "first_name", "middle_initial", "last_name", "suffix", "phone", "fax", "email",
        "street_address", "city", "state", "zip", "po_box", "attention_line", "sgin", "frn",
        "app_type_code", "app_type_code_other", "status_code", "status_date", "_37_ghz_lic_type",
        "linked_sys_id", "linked_call_sign",
    ]

    static let amColumns = [
        "record_type", "sys_id", "file_number", "ebf_number", "call_sign", "operator_class", "group_code",
        "region_code", "trustee_call_sign", "trustee_indicator", "physician_cert", "ve_signature",
        "systematic_call_sign_change", "vanity_call_sign_change", "vanity_relationship", "previous_call_sign",
        "previous_operator_class", "trustee_name",
    ]

    static let dmrColumns = [
        "radio_id", "call_sign", "first_name", "last_name", "city", "state", "country",
    ]

    static let createTables = """
    \(table("hd", columns: hdColumns))
    \(table("en", columns: enColumns))
    \(table("am", columns: amColumns))
    \(table("dmr", columns: dmrColumns))
    CREATE TABLE app_info (
        imported_at TEXT NOT NULL
    );
    """

    static let createIndexes = """
    CREATE INDEX en_call_sign_index ON en (call_sign);
    CREATE INDEX en_first_name_last_name_index ON en (first_name, last_name);
    CREATE INDEX en_last_name_index ON en (last_name);
    CREATE INDEX en_city ON en (city);
    CREATE INDEX hd_sys_id_index ON hd (sys_id, license_status);
    CREATE INDEX am_sys_id_index ON am (sys_id, operator_class, region_code);
    CREATE INDEX dmr_call_sign_index ON dmr (call_sign, radio_id);
    """

    static func importScript(hd: String, en: String, am: String) -> String {
        """
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        PRAGMA temp_store = MEMORY;
        PRAGMA cache_size = -262144;
        \(createTables)
        .mode ascii
        .separator "|" "\\n"
        .import \(hd) hd
        .import \(en) en
        .import \(am) am
        """
    }

    static func dmrScript(csv: String) -> String {
        """
        .mode csv
        .import --skip 1 \(csv) dmr
        """
    }

    static func finishScript(importedAt: String) -> String {
        """
        \(createIndexes)
        INSERT INTO app_info (imported_at) VALUES (\(sqlString(importedAt)));
        SELECT COUNT(*) FROM en;
        """
    }

    static func sqlString(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static let nocaseColumns: Set<String> = [
        "call_sign", "first_name", "last_name", "city", "state", "license_status", "operator_class",
    ]

    private static func table(_ name: String, columns: [String]) -> String {
        let definitions = columns.map { column in
            if nocaseColumns.contains(column) {
                "\(column) TEXT COLLATE NOCASE"
            } else {
                "\(column) TEXT"
            }
        }
        return """
        CREATE TABLE \(name) (
            \(definitions.joined(separator: ",\n    "))
        );
        """
    }
}

enum DatabaseUpdateError: LocalizedError {
    case cancelled(databaseReplaced: Bool)
    case failed(String, databaseReplaced: Bool)

    var replacedLicenseTables: Bool {
        switch self {
        case .cancelled(let replaced), .failed(_, let replaced):
            replaced
        }
    }

    var errorDescription: String? {
        switch self {
        case .cancelled(false):
            "Update cancelled. The database was not changed."
        case .cancelled(true):
            "Update cancelled after the new database was installed."
        case .failed(let message, false):
            message
        case .failed(let message, true):
            "The new database was installed, but a later step did not finish. \(message)"
        }
    }
}
