import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class LookupModel {
    var callSign = ""
    var firstName = ""
    var lastName = ""
    var city = ""
    var state = ""
    var licenseStatuses: Set<String> = [LicenseStatus.active.rawValue]
    var operatorClasses: Set<String> = Set(OperatorClass.allCases.map(\.rawValue))
    var applyTitleCase = true
    var filter = ""
    var records: [LicenseRecord] = []
    var selection = Set<LicenseRecord.ID>()
    var sortOrder = [KeyPathComparator<LicenseRecord>]()
    var isSearching = false
    var hasSearched = false
    var hadCriteria = false
    var errorMessage: String?
    var isExporting = false
    var connectionSettings: ConnectionSettings

    private let database: LicenseDatabase
    private var generation = 0

    init(database: LicenseDatabase? = nil) {
        let settings = ConnectionSettings.load()
        connectionSettings = settings
        self.database = database ?? LicenseDatabase(settings: settings)
    }

    var filteredRecords: [LicenseRecord] {
        let sorted = sortOrder.isEmpty ? records : records.sorted(using: sortOrder)
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.matches(query) }
    }

    var resultSummary: String? {
        guard !records.isEmpty else { return nil }
        let total = records.count
        if !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let noun = total == 1 ? "record" : "records"
            return "Showing \(filteredRecords.count) of \(total) \(noun)"
        }
        if total == 1 {
            return "Found 1 matching record"
        }
        return "Found \(total) matching records"
    }

    func search() {
        let query = makeQuery()
        generation += 1
        let token = generation
        errorMessage = nil
        filter = ""
        selection = []
        sortOrder = []

        guard query.hasCriteria else {
            records = []
            hasSearched = true
            hadCriteria = false
            isSearching = false
            return
        }

        hadCriteria = true
        isSearching = true
        hasSearched = true
        let database = database
        Task {
            do {
                let found = try await database.search(query)
                guard token == generation else { return }
                records = found
                errorMessage = nil
            } catch {
                guard token == generation else { return }
                errorMessage = error.localizedDescription
            }
            if token == generation {
                isSearching = false
            }
        }
    }

    func clear() {
        generation += 1
        callSign = ""
        firstName = ""
        lastName = ""
        city = ""
        state = ""
        licenseStatuses = [LicenseStatus.active.rawValue]
        operatorClasses = Set(OperatorClass.allCases.map(\.rawValue))
        applyTitleCase = true
        filter = ""
        records = []
        selection = []
        sortOrder = []
        hasSearched = false
        hadCriteria = false
        isSearching = false
        errorMessage = nil
    }

    func copySelection() {
        copy(ids: selection)
    }

    func copy(ids: Set<LicenseRecord.ID>) {
        let chosen = filteredRecords.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let header = LicenseRecord.csvHeader.joined(separator: "\t")
        let text = ([header] + chosen.map(\.tabSeparated)).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func searchCallSigns(_ ids: Set<LicenseRecord.ID>) {
        guard ids.count == 1,
              let id = ids.first,
              let record = records.first(where: { $0.id == id })
        else { return }
        callSign = record.callSign
        firstName = ""
        lastName = ""
        city = ""
        state = ""
        search()
    }

    @discardableResult
    func updateConnection(_ settings: ConnectionSettings) -> String? {
        let normalized = settings.normalized()
        connectionSettings = normalized
        let warning = ConnectionSettings.save(normalized)
        let database = database
        Task {
            await database.update(settings: normalized)
        }
        return warning
    }

    private func makeQuery() -> LicenseQuery {
        LicenseQuery(
            callSign: callSign,
            firstName: firstName,
            lastName: lastName,
            city: city,
            state: state,
            licenseStatuses: licenseStatuses,
            operatorClasses: operatorClasses,
            applyTitleCase: applyTitleCase
        )
    }

    static var preview: LookupModel {
        let model = LookupModel()
        model.city = "Emmett"
        model.state = "ID"
        model.records = LicenseRecord.samples
        model.hasSearched = true
        model.hadCriteria = true
        return model
    }
}
