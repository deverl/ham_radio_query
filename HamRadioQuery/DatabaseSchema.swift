import Foundation

enum DatabaseSchema {
    static func validatedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= 64,
              name.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil
        else {
            throw DatabaseUpdateError.failed(
                "The database name “\(name)” cannot be used. Use letters, numbers, and underscores.",
                licensesLoaded: false
            )
        }
        return name
    }

    static func quotedIdentifier(_ name: String) -> String {
        "`\(name.replacingOccurrences(of: "`", with: "``"))`"
    }

    static func sqlString(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\", "'":
                escaped.append("\\")
                escaped.append(character)
            case "\n":
                escaped.append("\\n")
            case "\r":
                escaped.append("\\r")
            default:
                escaped.append(character)
            }
        }
        return "'\(escaped)'"
    }

    static func licenseSQL(database: String, hd: String, en: String, am: String) -> String {
        """
        CREATE DATABASE IF NOT EXISTS \(quotedIdentifier(database));
        USE \(quotedIdentifier(database));

        DROP TABLE IF EXISTS hd;
        DROP TABLE IF EXISTS en;
        DROP TABLE IF EXISTS am;

        \(licenseTables)

        LOAD DATA LOCAL INFILE \(sqlString(hd))
        INTO TABLE hd
        FIELDS TERMINATED BY '|'
        LINES TERMINATED BY '\\n';

        LOAD DATA LOCAL INFILE \(sqlString(en))
        INTO TABLE en
        FIELDS TERMINATED BY '|'
        LINES TERMINATED BY '\\n';

        LOAD DATA LOCAL INFILE \(sqlString(am))
        INTO TABLE am
        FIELDS TERMINATED BY '|'
        LINES TERMINATED BY '\\n';
        """
    }

    static func dmrSQL(database: String, csv: String) -> String {
        """
        USE \(quotedIdentifier(database));

        DROP TABLE IF EXISTS dmr;

        CREATE TABLE dmr (
            radio_id VARCHAR(20),
            call_sign VARCHAR(20),
            first_name VARCHAR(30),
            last_name VARCHAR(40),
            city VARCHAR(40),
            state VARCHAR(30),
            country VARCHAR(30)
        );

        CREATE INDEX dmr_call_sign_index ON dmr (call_sign, radio_id);

        LOAD DATA LOCAL INFILE \(sqlString(csv))
        INTO TABLE dmr
        FIELDS TERMINATED BY ','
        LINES TERMINATED BY '\\n';
        """
    }

    private static let licenseTables = """
    CREATE TABLE hd (
        record_type VARCHAR(10),
        sys_id BIGINT,
        file_number VARCHAR(20),
        ebf_number VARCHAR(20),
        call_sign VARCHAR(20),
        license_status VARCHAR(5),
        radio_service_code VARCHAR(10),
        grant_date VARCHAR(20),
        expired_date VARCHAR(20),
        cancellation_date VARCHAR(20),
        eligibility_rule_num VARCHAR(10),
        reserved1 VARCHAR(10),
        alien VARCHAR(5),
        alien_government VARCHAR(5),
        alien_corporation VARCHAR(5),
        alien_officer VARCHAR(5),
        alien_control VARCHAR(5),
        revoked VARCHAR(5),
        convicted VARCHAR(5),
        adjudged VARCHAR(5),
        reserved2 VARCHAR(10),
        common_carrier VARCHAR(5),
        non_common_carrier VARCHAR(5),
        private_comm VARCHAR(5),
        fixed VARCHAR(5),
        mobile VARCHAR(5),
        radiolocation VARCHAR(5),
        satellite VARCHAR(5),
        dev_sta_demo VARCHAR(5),
        interconnected_service VARCHAR(5),
        certifier_first_name VARCHAR(50),
        certifier_middle_initial VARCHAR(5),
        certifier_last_name VARCHAR(50),
        certifier_suffix VARCHAR(10),
        certifier_title VARCHAR(50),
        female VARCHAR(5),
        black_or_african_american VARCHAR(5),
        native_american VARCHAR(5),
        hawaiian VARCHAR(5),
        asian VARCHAR(5),
        white VARCHAR(5),
        hispanic VARCHAR(5),
        effective_date VARCHAR(20),
        last_action_date VARCHAR(20),
        auction_id INT,
        broadcast_regulatory_status VARCHAR(10),
        band_manager_regulatory_status VARCHAR(10),
        broadcast_services_type VARCHAR(10),
        alien_ruling VARCHAR(10),
        licensee_name_change VARCHAR(10),
        whitespace_indicator VARCHAR(5),
        operation_perf_requirement_choice VARCHAR(10),
        operation_perf_requirement_answer VARCHAR(10),
        discontinuation_of_service VARCHAR(10),
        regulatory_compliance VARCHAR(10),
        _900_mhz_eligibility_cert VARCHAR(10),
        _900_mhz_transition_plan_cert VARCHAR(10),
        _900_mhz_return_spectrum_cert VARCHAR(10),
        _900_mhz_payment_cert VARCHAR(10)
    );

    CREATE TABLE en (
        record_type VARCHAR(10),
        sys_id BIGINT,
        file_number VARCHAR(20),
        ebf_number VARCHAR(20),
        call_sign VARCHAR(20),
        entity_type VARCHAR(10),
        licensee_id VARCHAR(20),
        entity_name VARCHAR(100),
        first_name VARCHAR(50),
        middle_initial VARCHAR(5),
        last_name VARCHAR(50),
        suffix VARCHAR(10),
        phone VARCHAR(20),
        fax VARCHAR(20),
        email VARCHAR(100),
        street_address VARCHAR(100),
        city VARCHAR(50),
        state VARCHAR(10),
        zip VARCHAR(20),
        po_box VARCHAR(20),
        attention_line VARCHAR(100),
        sgin VARCHAR(20),
        frn VARCHAR(20),
        app_type_code VARCHAR(10),
        app_type_code_other VARCHAR(10),
        status_code VARCHAR(10),
        status_date VARCHAR(20),
        _37_ghz_lic_type VARCHAR(10),
        linked_sys_id BIGINT,
        linked_call_sign VARCHAR(20)
    );

    CREATE TABLE am (
        record_type VARCHAR(10),
        sys_id BIGINT,
        file_number VARCHAR(20),
        ebf_number VARCHAR(20),
        call_sign VARCHAR(20),
        operator_class VARCHAR(5),
        group_code VARCHAR(5),
        region_code VARCHAR(10),
        trustee_call_sign VARCHAR(20),
        trustee_indicator VARCHAR(5),
        physician_cert VARCHAR(5),
        ve_signature VARCHAR(5),
        systematic_call_sign_change VARCHAR(5),
        vanity_call_sign_change VARCHAR(5),
        vanity_relationship VARCHAR(10),
        previous_call_sign VARCHAR(20),
        previous_operator_class VARCHAR(5),
        trustee_name VARCHAR(100)
    );

    CREATE INDEX en_call_sign_index ON en (call_sign);
    CREATE INDEX en_first_name_last_name_index ON en (first_name, last_name);
    CREATE INDEX en_last_name_index ON en (last_name);
    CREATE INDEX en_city ON en (city);
    CREATE INDEX hd_sys_id_index ON hd (sys_id, license_status);
    CREATE INDEX am_sys_id_index ON am (sys_id, operator_class, region_code);
    """
}

enum DatabaseUpdateError: LocalizedError {
    case cancelled(licensesLoaded: Bool)
    case failed(String, licensesLoaded: Bool)

    var replacedLicenseTables: Bool {
        switch self {
        case .cancelled(let loaded), .failed(_, let loaded):
            return loaded
        }
    }

    var errorDescription: String? {
        switch self {
        case .cancelled(false):
            "Update cancelled. The database was not changed."
        case .cancelled(true):
            "Update cancelled. License records were updated, but DMR IDs were not imported."
        case .failed(let message, false):
            message
        case .failed(let message, true):
            "License records were updated, but the DMR import did not finish. \(message)"
        }
    }
}
