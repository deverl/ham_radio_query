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
        .width(min: 84, ideal: 104)
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
            .width(min: 52, ideal: 64)
    }

    private var zip: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("ZIP", value: \.zip) { record in
            Text(record.zip).monospacedDigit()
        }
        .width(min: 70, ideal: 88)
    }

    private var operatorClass: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("Operator Class", value: \.operatorClass) { record in
            Text(record.operatorClass)
                .help(OperatorClass.title(for: record.operatorClass))
        }
        .width(min: 70, ideal: 110)
    }

    private var licenseStatus: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("License Status", value: \.licenseStatus) { record in
            Text(record.licenseStatus)
                .foregroundStyle(record.licenseStatus == "A" ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .help(LicenseStatus.title(for: record.licenseStatus))
        }
        .width(min: 70, ideal: 110)
    }

    private var frn: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("FRN", value: \.frn) { record in
            Text(record.frn).monospacedDigit()
        }
        .width(min: 100, ideal: 120)
    }

    private var region: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("Region Code", value: \.regionCode)
            .width(min: 60, ideal: 90)
    }

    private var dmr: some TableColumnContent<LicenseRecord, KeyPathComparator<LicenseRecord>> {
        TableColumn("DMR ID", value: \.dmrID) { record in
            Text(record.dmrID.isEmpty ? "-" : record.dmrID)
                .foregroundStyle(record.dmrID.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .monospacedDigit()
        }
        .width(min: 70, ideal: 96)
    }
}
