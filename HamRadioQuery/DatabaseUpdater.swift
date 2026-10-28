import Foundation

struct DatabaseUpdateSnapshot: Sendable {
    var status: String
    var fraction: Double?
    var detail: String
    var canCancel: Bool
}

final class DatabaseUpdateSession: @unchecked Sendable {
    private let lock = NSLock()
    private var download: FileDownload?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func setDownload(_ download: FileDownload?) {
        lock.lock()
        self.download = download
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            download?.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let download = self.download
        lock.unlock()
        download?.cancel()
    }
}

enum DatabaseUpdater {
    static let directory = URL(fileURLWithPath: "/tmp/ham-radio-lookup", isDirectory: true)
    static let fccURL = URL(string: "https://data.fcc.gov/download/pub/uls/complete/l_amat.zip")!
    static let radioIDURL = URL(string: "https://radioid.net/static/user.csv")!

    static func update(
        session: DatabaseUpdateSession,
        progress: @escaping @MainActor (DatabaseUpdateSnapshot) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try await perform(session: session, progress: progress)
        }.value
    }

    static func buildDatabase(
        hd: URL,
        en: URL,
        am: URL,
        csv: URL,
        to destination: URL,
        importedAt: Date = Date()
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let workingDirectory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try sqlite(
            DatabaseSchema.importScript(hd: hd.path, en: en.path, am: am.path),
            database: destination,
            workingDirectory: workingDirectory
        )
        try sqlite(
            DatabaseSchema.dmrScript(csv: csv.path),
            database: destination,
            workingDirectory: workingDirectory
        )
        let count = try sqlite(
            DatabaseSchema.finishScript(importedAt: LicenseStore.timestamp(importedAt)),
            database: destination,
            workingDirectory: workingDirectory
        )
        guard lastLine(count) != "0" else {
            throw DatabaseUpdateError.failed("The license file did not contain any records.", databaseReplaced: false)
        }
    }

    private static func perform(
        session: DatabaseUpdateSession,
        progress: @escaping @MainActor (DatabaseUpdateSnapshot) -> Void
    ) async throws {
        let relay = ProgressRelay(progress: progress)
        defer { relay.invalidate() }
        var databaseReplaced = false
        do {
            relay.phase(DatabaseUpdateSnapshot(
                status: "Preparing…",
                fraction: nil,
                detail: "",
                canCancel: true
            ))
            try prepareDirectory()
            try checkCancelled(session, databaseReplaced: false)

            let zipURL = directory.appendingPathComponent("l_amat.zip")
            let fccPhase = relay.phase(DatabaseUpdateSnapshot(
                status: "Downloading FCC license file…",
                fraction: nil,
                detail: "",
                canCancel: true
            ))
            try await download(fccURL, to: zipURL, session: session) { written, expected in
                relay.report(
                    DatabaseUpdateSnapshot(
                        status: "Downloading FCC license file…",
                        fraction: fraction(written, expected),
                        detail: byteDetail(written, expected),
                        canCancel: true
                    ),
                    generation: fccPhase
                )
            }
            try checkCancelled(session, databaseReplaced: false)
            try requireDownloadSize(at: zipURL, minimum: 1_000_000, name: "FCC license file")

            relay.phase(DatabaseUpdateSnapshot(
                status: "Extracting license files…",
                fraction: nil,
                detail: "",
                canCancel: false
            ))
            try extract(zipURL)
            let hd = try locate("HD.dat")
            let en = try locate("EN.dat")
            let am = try locate("AM.dat")

            let csvURL = directory.appendingPathComponent("user.csv")
            let radioPhase = relay.phase(DatabaseUpdateSnapshot(
                status: "Downloading RadioID user list…",
                fraction: nil,
                detail: "",
                canCancel: true
            ))
            try await download(radioIDURL, to: csvURL, session: session) { written, expected in
                relay.report(
                    DatabaseUpdateSnapshot(
                        status: "Downloading RadioID user list…",
                        fraction: fraction(written, expected),
                        detail: byteDetail(written, expected),
                        canCancel: true
                    ),
                    generation: radioPhase
                )
            }
            try checkCancelled(session, databaseReplaced: false)
            try requireDownloadSize(at: csvURL, minimum: 1_000, name: "RadioID user list")

            let staging = directory.appendingPathComponent("licenses.sqlite")
            relay.phase(DatabaseUpdateSnapshot(
                status: "Importing license records…",
                fraction: nil,
                detail: "This can take a few minutes.",
                canCancel: false
            ))
            if FileManager.default.fileExists(atPath: staging.path) {
                try FileManager.default.removeItem(at: staging)
            }
            try sqlite(
                DatabaseSchema.importScript(hd: hd.path, en: en.path, am: am.path),
                database: staging,
                workingDirectory: directory
            )
            relay.phase(DatabaseUpdateSnapshot(
                status: "Importing DMR IDs…",
                fraction: nil,
                detail: "",
                canCancel: false
            ))
            try sqlite(
                DatabaseSchema.dmrScript(csv: csvURL.path),
                database: staging,
                workingDirectory: directory
            )
            relay.phase(DatabaseUpdateSnapshot(
                status: "Indexing license records…",
                fraction: nil,
                detail: "This can take a few minutes.",
                canCancel: false
            ))
            let count = try sqlite(
                DatabaseSchema.finishScript(importedAt: LicenseStore.timestamp(Date())),
                database: staging,
                workingDirectory: directory
            )
            guard lastLine(count) != "0" else {
                throw DatabaseUpdateError.failed(
                    "The license file did not contain any records.",
                    databaseReplaced: false
                )
            }

            relay.phase(DatabaseUpdateSnapshot(
                status: "Installing the database…",
                fraction: nil,
                detail: LicenseStore.databaseURL.path,
                canCancel: false
            ))
            try LicenseStore.install(staging: staging)
            databaseReplaced = true
        } catch {
            throw map(error, databaseReplaced: databaseReplaced)
        }
    }

    @discardableResult
    private static func sqlite(_ script: String, database: URL, workingDirectory: URL) throws -> String {
        let output = try run(
            executable: "/usr/bin/sqlite3",
            arguments: ["-batch", database.path],
            currentDirectory: workingDirectory,
            standardInput: script
        )
        if output.stderr.contains("expected"), output.stderr.contains("columns") {
            throw DatabaseUpdateError.failed(
                "The license file did not match the expected columns.\n\(tail(output.stderr))",
                databaseReplaced: false
            )
        }
        return output.stdout
    }

    private static func prepareDirectory() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func download(
        _ url: URL,
        to destination: URL,
        session: DatabaseUpdateSession,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let download = FileDownload(destination: destination, onProgress: onProgress)
        session.setDownload(download)
        defer { session.setDownload(nil) }
        try await download.start(url: url)
    }

    private static func extract(_ zipURL: URL) throws {
        try run(
            executable: "/usr/bin/unzip",
            arguments: ["-o", "-q", zipURL.path],
            currentDirectory: directory,
            standardInput: nil
        )
    }

    private static func locate(_ name: String) throws -> URL {
        let fileManager = FileManager.default
        let direct = directory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: direct.path) {
            return direct
        }
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory, child.lastPathComponent != "__MACOSX" else { continue }
            let nested = child.appendingPathComponent(name)
            if fileManager.fileExists(atPath: nested.path) {
                return nested
            }
        }
        throw DatabaseUpdateError.failed(
            "The FCC archive did not contain \(name).",
            databaseReplaced: false
        )
    }

    private static func requireDownloadSize(at url: URL, minimum: Int, name: String) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size >= minimum else {
            throw DatabaseUpdateError.failed("The \(name) download was incomplete.", databaseReplaced: false)
        }
    }

    private static func checkCancelled(_ session: DatabaseUpdateSession, databaseReplaced: Bool) throws {
        if Task.isCancelled || session.isCancelled {
            throw DatabaseUpdateError.cancelled(databaseReplaced: databaseReplaced)
        }
    }

    private struct CommandOutput {
        var stdout: String
        var stderr: String
    }

    @discardableResult
    private static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        standardInput: String?
    ) throws -> CommandOutput {
        let token = UUID().uuidString
        let stdoutURL = currentDirectory.appendingPathComponent(".command-stdout-\(token)")
        let stderrURL = currentDirectory.appendingPathComponent(".command-stderr-\(token)")
        let fileManager = FileManager.default
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
            try? fileManager.removeItem(at: stdoutURL)
            try? fileManager.removeItem(at: stderrURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        process.qualityOfService = .userInitiated

        if let standardInput {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            try stdin.fileHandleForWriting.write(contentsOf: Data(standardInput.utf8))
            try stdin.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }
        process.waitUntilExit()

        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let errorText = (try? String(contentsOf: stderrURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            let name = URL(fileURLWithPath: executable).lastPathComponent
            if errorText.isEmpty {
                throw DatabaseUpdateError.failed(
                    "\(name) exited with status \(process.terminationStatus).",
                    databaseReplaced: false
                )
            }
            throw DatabaseUpdateError.failed(
                "\(name) exited with status \(process.terminationStatus).\n\(tail(errorText))",
                databaseReplaced: false
            )
        }
        return CommandOutput(stdout: output, stderr: errorText)
    }

    private static func map(_ error: Error, databaseReplaced: Bool) -> DatabaseUpdateError {
        if let update = error as? DatabaseUpdateError {
            switch update {
            case .cancelled:
                return .cancelled(databaseReplaced: databaseReplaced)
            case .failed(let message, _):
                return .failed(message, databaseReplaced: databaseReplaced)
            }
        }
        if error is CancellationError {
            return .cancelled(databaseReplaced: databaseReplaced)
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled(databaseReplaced: databaseReplaced)
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return .failed(message, databaseReplaced: databaseReplaced)
    }

    private static func fraction(_ written: Int64, _ expected: Int64) -> Double? {
        guard expected > 0 else { return nil }
        return min(1, Double(written) / Double(expected))
    }

    private static func byteDetail(_ written: Int64, _ expected: Int64) -> String {
        let writtenText = written.formatted(.byteCount(style: .file))
        guard expected > 0 else { return writtenText }
        return "\(writtenText) of \(expected.formatted(.byteCount(style: .file)))"
    }

    private static func lastLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
    }

    private static func tail(_ text: String) -> String {
        let limit = 1_200
        guard text.count > limit else { return text }
        return String(text.suffix(limit))
    }
}

private final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private let progress: @MainActor (DatabaseUpdateSnapshot) -> Void

    init(progress: @escaping @MainActor (DatabaseUpdateSnapshot) -> Void) {
        self.progress = progress
    }

    @discardableResult
    func phase(_ snapshot: DatabaseUpdateSnapshot) -> Int {
        let generation = nextGeneration()
        report(snapshot, generation: generation)
        return generation
    }

    func report(_ snapshot: DatabaseUpdateSnapshot, generation: Int) {
        Task { @MainActor in
            guard self.isCurrent(generation) else { return }
            self.progress(snapshot)
        }
    }

    func invalidate() {
        _ = nextGeneration()
    }

    private func nextGeneration() -> Int {
        lock.lock()
        generation += 1
        let generation = generation
        lock.unlock()
        return generation
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.generation == generation
    }
}

final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()
    private var finished = false
    private var cancelRequested = false
    private var moveError: Error?
    private var moved = false
    private var lastReport = Date.distantPast
    private var lastPercent = -1

    init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func start(url: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("HamRadioQuery", forHTTPHeaderField: "User-Agent")
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request)
            lock.lock()
            self.continuation = continuation
            self.task = task
            let shouldCancel = cancelRequested
            lock.unlock()
            task.resume()
            if shouldCancel {
                task.cancel()
            }
        }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let percent = totalBytesExpectedToWrite > 0
            ? Int(totalBytesWritten * 100 / totalBytesExpectedToWrite)
            : -1
        let now = Date()
        lock.lock()
        let shouldReport = percent != lastPercent || now.timeIntervalSince(lastReport) >= 0.2
        if shouldReport {
            lastPercent = percent
            lastReport = now
        }
        lock.unlock()
        if shouldReport {
            onProgress(totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            moveError = DatabaseUpdateError.failed(
                "The download failed (HTTP \(response.statusCode)).",
                databaseReplaced: false
            )
            return
        }
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            moved = true
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error>
        if let moveError {
            result = .failure(moveError)
        } else if let error {
            result = .failure(error)
        } else if moved {
            result = .success(())
        } else if let response = task.response as? HTTPURLResponse,
                  !(200..<300).contains(response.statusCode) {
            result = .failure(DatabaseUpdateError.failed(
                "The download failed (HTTP \(response.statusCode)).",
                databaseReplaced: false
            ))
        } else {
            result = .failure(DatabaseUpdateError.failed("The download did not finish.", databaseReplaced: false))
        }
        finish(result)
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation: CheckedContinuation<Void, Error>?
        if finished {
            continuation = nil
        } else {
            finished = true
            continuation = self.continuation
            self.continuation = nil
        }
        lock.unlock()
        continuation?.resume(with: result)
    }
}
