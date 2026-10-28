import Foundation
import SQLite3

enum DatabaseError: LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String, readonly: Bool) throws {
        let flags = readonly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, handle != nil else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open the database."
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.message(message)
        }
        sqlite3_busy_timeout(handle, 3_000)
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "SQLite error \(result)"
            sqlite3_free(errorPointer)
            throw DatabaseError.message(message)
        }
    }

    func query(_ sql: String, parameters: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw storedError()
        }
        defer { sqlite3_finalize(statement) }

        for (offset, parameter) in parameters.enumerated() {
            let position = Int32(offset + 1)
            let result = parameter.withCString { pointer in
                sqlite3_bind_text(statement, position, pointer, -1, transient)
            }
            guard result == SQLITE_OK else { throw storedError() }
        }

        let columnCount = sqlite3_column_count(statement)
        var names: [String] = []
        names.reserveCapacity(Int(columnCount))
        for index in 0..<columnCount {
            if let name = sqlite3_column_name(statement, index) {
                names.append(String(cString: name))
            } else {
                names.append("")
            }
        }

        var rows: [[String: String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                var row: [String: String] = [:]
                for index in 0..<columnCount {
                    let value: String
                    if let text = sqlite3_column_text(statement, index) {
                        value = String(cString: text)
                    } else {
                        value = ""
                    }
                    row[names[Int(index)]] = value
                }
                rows.append(row)
            } else if step == SQLITE_DONE {
                return rows
            } else {
                throw storedError()
            }
        }
    }

    private func storedError() -> DatabaseError {
        let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error"
        return .message(message)
    }
}
