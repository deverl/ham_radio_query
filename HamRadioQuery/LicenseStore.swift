import Foundation

enum LicenseStore {
    static let folderName = "Ham Radio Query"
    static let fileName = "licenses.sqlite"
    static let maximumAge: TimeInterval = 8 * 24 * 60 * 60

    static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static var databaseURL: URL {
        directory.appendingPathComponent(fileName)
    }

    enum Freshness: Equatable {
        case missing
        case stale(importedAt: Date)
        case current(importedAt: Date)

        var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }
    }

    static func freshness(at url: URL = databaseURL, now: Date = Date()) -> Freshness {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let database = try SQLiteDatabase(path: url.path, readonly: true)
            let rows = try database.query("SELECT imported_at FROM app_info LIMIT 1")
            guard let text = rows.first?["imported_at"], let importedAt = parse(text) else {
                return .missing
            }
            if now.timeIntervalSince(importedAt) > maximumAge {
                return .stale(importedAt: importedAt)
            }
            return .current(importedAt: importedAt)
        } catch {
            return .missing
        }
    }

    static func install(staging: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = databaseURL
        let previous = directory.appendingPathComponent("licenses.sqlite.previous")
        if fileManager.fileExists(atPath: previous.path) {
            try fileManager.removeItem(at: previous)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: previous)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            try? fileManager.removeItem(at: previous)
        } catch {
            if fileManager.fileExists(atPath: previous.path),
               !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: previous, to: destination)
            }
            throw error
        }
    }

    static func timestamp(_ date: Date) -> String {
        dateFormatter().string(from: date)
    }

    static func parse(_ text: String) -> Date? {
        dateFormatter().date(from: text)
    }

    private static func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
