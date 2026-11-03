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
    var queryDuration: TimeInterval?
    var isExporting = false
    var engine: DatabaseEngine
    var connectionSettings: ConnectionSettings
    var freshness: LicenseStore.Freshness = .missing
    var databaseNotice: DatabaseNotice?
    var confirmDatabaseUpdate = false
    var isPresentingUpdate = false
    var isUpdatingDatabase = false
    var updateCanCancel = false
    var updateStatus = "Preparing…"
    var updateFraction: Double?
    var updateDetail = ""
    var updateError: String?

    var suppressDatabaseNotice = false

    private var databaseUpdateSession: DatabaseUpdateSession?
    private var didOfferDatabaseMaintenance = false

    private let database: LicenseDatabase
    private var generation = 0

    init(database: LicenseDatabase? = nil) {
        let engine = DatabaseEngine.load()
        let settings = ConnectionSettings.load(for: engine == .postgres ? .postgres : .mysql)
        self.engine = engine
        self.connectionSettings = settings
        self.database = database ?? LicenseDatabase(engine: engine, settings: settings)
        if database == nil, engine == .sqlite {
            freshness = LicenseStore.freshness()
        }
    }

    var searchUnavailable: Bool {
        engine == .sqlite && freshness.isMissing
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
        let timing = queryDuration.map { " in \(QueryTiming.label(seconds: $0))" } ?? ""
        if !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let noun = total == 1 ? "record" : "records"
            return "Showing \(filteredRecords.count) of \(total) \(noun)\(timing)"
        }
        if total == 1 {
            return "Found 1 matching record\(timing)"
        }
        return "Found \(total) matching records\(timing)"
    }

    func search() {
        guard !isUpdatingDatabase else { return }
        if searchUnavailable {
            records = []
            queryDuration = nil
            hasSearched = false
            hadCriteria = false
            isSearching = false
            errorMessage = nil
            databaseNotice = .missing
            return
        }
        let query = makeQuery()
        generation += 1
        let token = generation
        errorMessage = nil
        filter = ""
        selection = []
        sortOrder = []

        guard query.hasCriteria else {
            records = []
            queryDuration = nil
            hasSearched = true
            hadCriteria = false
            isSearching = false
            return
        }

        hadCriteria = true
        isSearching = true
        hasSearched = true
        let database = database
        let started = ContinuousClock.now
        Task {
            do {
                let found = try await database.search(query)
                guard token == generation else { return }
                records = found
                queryDuration = QueryTiming.seconds(from: started.duration(to: .now))
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
        queryDuration = nil
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

    var maintenanceMenuTitle: String {
        if engine == .sqlite, freshness.isMissing {
            return "Create License Database…"
        }
        return "Update License Database…"
    }

    var maintenanceConfirmTitle: String {
        if engine == .sqlite, freshness.isMissing {
            return "Create License Database?"
        }
        return "Update License Database?"
    }

    var maintenanceConfirmButton: String {
        if engine == .sqlite, freshness.isMissing {
            return "Create"
        }
        return "Update"
    }

    var maintenanceConfirmMessage: String {
        if engine == .mysql || engine == .postgres {
            let product = engine == .postgres ? "PostgreSQL" : "MySQL"
            return "This downloads the latest FCC amateur license file (about 190 MB) and the RadioID user list, then rebuilds the \(product) database \(connectionSettings.database). The current license tables are replaced. Downloaded files are left in /tmp/ham-radio-lookup."
        }
        if freshness.isMissing {
            return "The license database has not been created. This downloads the FCC amateur license file (about 190 MB) and the RadioID user list, then builds a database in \(LicenseStore.folderName). Downloaded files are left in /tmp/ham-radio-lookup."
        }
        return "This downloads the latest FCC amateur license file (about 190 MB) and the RadioID user list, then replaces the SQLite license database. Downloaded files are left in /tmp/ham-radio-lookup."
    }

    var freshnessDescription: String {
        switch freshness {
        case .missing:
            "Not created"
        case .stale(let date), .current(let date):
            date.formatted(date: .long, time: .shortened)
        }
    }

    var databaseNoticeTitle: String {
        switch databaseNotice {
        case .missing, .none:
            "License Database Needed"
        case .stale:
            "License Database Is Old"
        }
    }

    var databaseNoticeMessage: String {
        switch databaseNotice {
        case .missing, .none:
            "The license database has not been created. Create it before searching. This downloads the FCC amateur license file (about 190 MB) and the RadioID user list."
        case .stale(let date):
            "The license database was last built \(date.formatted(date: .long, time: .shortened)) and is more than 8 days old. It should be updated."
        }
    }

    var databaseNoticeButton: String {
        if case .stale = databaseNotice { return "Update" }
        return "Create"
    }

    func applyEngine(_ engine: DatabaseEngine) {
        DatabaseEngine.save(engine)
        databaseNotice = nil
        if engine != .sqlite {
            connectionSettings = ConnectionSettings.load(for: engine)
        }
        let database = database
        let settings = connectionSettings
        Task { await database.use(engine: engine, settings: settings) }
        if engine == .sqlite {
            refreshFreshness()
            guard !suppressDatabaseNotice else { return }
            switch freshness {
            case .missing:
                databaseNotice = .missing
            case .stale(let date):
                databaseNotice = .stale(date)
            case .current:
                break
            }
        }
    }

    @discardableResult
    func updateConnection(_ settings: ConnectionSettings) -> String? {
        let normalized = settings.normalized()
        connectionSettings = normalized
        let slot: DatabaseEngine = engine == .postgres ? .postgres : .mysql
        let warning = ConnectionSettings.save(normalized, for: slot)
        let database = database
        let engine = engine
        Task { await database.use(engine: engine, settings: normalized) }
        return warning
    }

    func offerDatabaseMaintenanceIfNeeded() {
        guard !suppressDatabaseNotice, engine == .sqlite else { return }
        freshness = LicenseStore.freshness()
        guard !didOfferDatabaseMaintenance else { return }
        didOfferDatabaseMaintenance = true
        switch freshness {
        case .missing:
            databaseNotice = .missing
        case .stale(let date):
            databaseNotice = .stale(date)
        case .current:
            break
        }
    }

    func refreshFreshness() {
        freshness = LicenseStore.freshness()
    }

    func startDatabaseUpdate() {
        guard !isUpdatingDatabase, !isSearching else { return }
        let session = DatabaseUpdateSession()
        databaseUpdateSession = session
        databaseNotice = nil
        isPresentingUpdate = true
        isUpdatingDatabase = true
        updateCanCancel = true
        updateError = nil
        updateStatus = "Preparing…"
        updateFraction = nil
        updateDetail = ""
        let creating = engine == .sqlite && freshness.isMissing
        let engine = engine
        let settings = connectionSettings
        NSApp.windows.first { $0.frameAutosaveName.contains("WindowGroup") }?.makeKeyAndOrderFront(nil)
        Task {
            do {
                try await DatabaseUpdater.update(engine: engine, settings: settings, session: session) { snapshot in
                    self.updateStatus = snapshot.status
                    self.updateFraction = snapshot.fraction
                    self.updateDetail = snapshot.detail
                    self.updateCanCancel = snapshot.canCancel
                }
                records = []
                queryDuration = nil
                selection = []
                filter = ""
                hasSearched = false
                hadCriteria = false
                errorMessage = nil
                freshness = LicenseStore.freshness()
                updateStatus = creating ? "Database created" : "Database updated"
                updateDetail = "The new records are used the next time you search. Downloaded files remain in /tmp/ham-radio-lookup."
                updateFraction = 1
                updateCanCancel = false
            } catch let error as DatabaseUpdateError {
                if error.replacedLicenseTables {
                    records = []
                    queryDuration = nil
                    selection = []
                    filter = ""
                    hasSearched = false
                    hadCriteria = false
                    errorMessage = nil
                }
                updateError = error.localizedDescription
                updateFraction = nil
                updateCanCancel = false
            } catch {
                updateError = error.localizedDescription
                updateFraction = nil
                updateCanCancel = false
            }
            freshness = LicenseStore.freshness()
            isUpdatingDatabase = false
            databaseUpdateSession = nil
        }
    }

    func cancelDatabaseUpdate() {
        guard updateCanCancel else { return }
        databaseUpdateSession?.cancel()
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
        model.suppressDatabaseNotice = true
        model.freshness = .current(importedAt: Date())
        model.city = "Emmett"
        model.state = "ID"
        model.records = LicenseRecord.samples
        model.queryDuration = 0.18
        model.hasSearched = true
        model.hadCriteria = true
        return model
    }
}

enum QueryTiming {
    static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }

    static func label(seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        let milliseconds = Int((seconds * 1000).rounded())
        if milliseconds < 1 { return "< 1 ms" }
        if milliseconds < 1000 { return "\(milliseconds) ms" }
        let scaled = Int((seconds * 10).rounded())
        let whole = scaled / 10
        let fraction = abs(scaled % 10)
        if fraction == 0 {
            return whole == 1 ? "1 second" : "\(whole) seconds"
        }
        return "\(whole).\(fraction) seconds"
    }
}

enum DatabaseNotice: Equatable {
    case missing
    case stale(Date)
}
