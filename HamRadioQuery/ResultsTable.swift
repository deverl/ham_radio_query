import SwiftUI

struct ResultsTable: View {
    @Bindable var model: LookupModel

    var body: some View {
        Table(model.filteredRecords, selection: $model.selection, sortOrder: $model.sortOrder) {
            Group {
                callSign
                firstName
                lastName
                street
                city
                state
            }
            Group {
                zip
                operatorClass
                licenseStatus
                frn
                region
                dmr
            }
        }
        .contextMenu(forSelectionType: LicenseRecord.ID.self) { ids in
            Button("Copy") {
                model.copy(ids: ids)
            }
            .disabled(ids.isEmpty)
            Button("Search This Call Sign") {
                model.searchCallSigns(ids)
            }
            .disabled(ids.count != 1)
        } primaryAction: { ids in
            model.searchCallSigns(ids)
        }
        .accessibilityLabel("License results")
    }

    private var callSign: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("Call Sign", value: \.callSign) { record in
            Text(record.callSign).monospaced()
        }
        .width(min: 76, ideal: ResultColumns.callSign, max: ResultColumns.callSign)
    }

    private var firstName: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("First Name", value: \.firstName)
            .width(min: 90, ideal: 120)
    }

    private var lastName: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("Last Name", value: \.lastName)
            .width(min: 90, ideal: 130)
    }

    private var street: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("Street Address", value: \.streetAddress)
            .width(min: 140, ideal: 190)
    }

    private var city: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("City", value: \.city)
            .width(min: 90, ideal: 120)
    }

    private var state: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("State", value: \.state)
            .width(min: 52, ideal: ResultColumns.state, max: ResultColumns.state)
    }

    private var zip: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("ZIP", value: \.zip) { record in
            Text(record.zip).monospacedDigit()
        }
        .width(min: 90, ideal: ResultColumns.zip, max: ResultColumns.zip)
    }

    private var operatorClass: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("Operator Class", value: \.operatorClassName) { record in
            Text(record.operatorClassName)
        }
        .width(min: 124, ideal: 140)
    }

    private var licenseStatus: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("License Status", value: \.licenseStatusName) { record in
            Text(record.licenseStatusName)
                .foregroundStyle(record.licenseStatus == "A" ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .width(min: 172, ideal: 180)
    }

    private var frn: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("FRN", value: \.frn) { record in
            Text(record.frn).monospacedDigit()
        }
        .width(min: 100, ideal: ResultColumns.frn, max: ResultColumns.frn)
    }

    private var region: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("Region Code", value: \.regionCode)
            .width(min: 96, ideal: ResultColumns.region, max: ResultColumns.region)
    }

    private var dmr: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("DMR ID", value: \.dmrID) { record in
            Text(record.dmrID.isEmpty ? "-" : record.dmrID)
                .foregroundStyle(record.dmrID.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .monospacedDigit()
        }
        .width(min: 76, ideal: ResultColumns.dmr, max: ResultColumns.dmr)
    }
}

/// Widths for the short columns, locked so they no longer stretch with the window.
/// The table lays each column out about 17 points wider than the value passed to `.width`,
/// so the default window is wide enough for that table without a horizontal scroller.
enum ResultColumns {
    static let callSign: CGFloat = 86
    static let state: CGFloat = 58
    static let zip: CGFloat = 100
    static let frn: CGFloat = 108
    static let region: CGFloat = 104
    static let dmr: CGFloat = 88
    static let defaultWindowWidth: CGFloat = 1640
}
