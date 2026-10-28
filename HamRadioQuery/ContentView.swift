import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: LookupModel
    @FocusState private var filterFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            SearchPanel(model: model)
                .background(.bar)
            Divider()

            if let errorMessage = model.errorMessage, !model.records.isEmpty {
                errorBanner(errorMessage)
                Divider()
            }

            if !model.records.isEmpty {
                filterBar
                Divider()
            }

            resultsArea

            if let summary = model.resultSummary {
                Divider()
                statusBar(summary)
            }
        }
        .navigationTitle("Ham Radio Lookup")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.isExporting = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.filteredRecords.isEmpty)
                .help("Export the rows in the table as CSV")
            }
            ToolbarItem {
                Button {
                    showDatabaseSettings()
                } label: {
                    Label("Database", systemImage: "server.rack")
                }
                .help("License database")
            }
        }
        .task {
            model.offerDatabaseMaintenanceIfNeeded()
        }
        .alert(model.databaseNoticeTitle, isPresented: databaseNoticePresented) {
            Button(model.databaseNoticeButton) {
                Task { @MainActor in
                    await Task.yield()
                    model.startDatabaseUpdate()
                }
            }
            Button(model.freshness.isMissing ? "Not Now" : "Later", role: .cancel) {}
        } message: {
            Text(model.databaseNoticeMessage)
        }
        .alert(model.maintenanceConfirmTitle, isPresented: $model.confirmDatabaseUpdate) {
            Button(model.maintenanceConfirmButton) {
                Task { @MainActor in
                    await Task.yield()
                    model.startDatabaseUpdate()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.maintenanceConfirmMessage)
        }
        .sheet(isPresented: $model.isPresentingUpdate) {
            DatabaseUpdateSheet(model: model)
        }
        .fileExporter(
            isPresented: $model.isExporting,
            document: CSVDocument(text: LicenseRecord.csv(model.filteredRecords)),
            contentType: .commaSeparatedText,
            defaultFilename: "Ham Radio Lookup"
        ) { result in
            if case .failure(let error) = result {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Text("Filter results:")
                .foregroundStyle(.secondary)
            TextField("Type to filter by any field…", text: $model.filter)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($filterFocused)
                .accessibilityLabel("Filter results")
            Button("Filter Results") {
                filterFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .labelStyle(.iconOnly)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var resultsArea: some View {
        if let errorMessage = model.errorMessage, model.records.isEmpty {
            ContentUnavailableView {
                Label("Can't Reach the Database", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Database Settings…") {
                    showDatabaseSettings()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isSearching && model.records.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.records.isEmpty && model.hasSearched && model.hadCriteria {
            ContentUnavailableView(
                "No Results Found",
                systemImage: "magnifyingglass",
                description: Text("No licenses matched this search.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.hasSearched && !model.hadCriteria {
            ContentUnavailableView(
                "Enter a Search",
                systemImage: "text.magnifyingglass",
                description: Text("Enter a call sign, name, city, or state.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.freshness.isMissing && model.records.isEmpty {
            ContentUnavailableView {
                Label("License Database Needed", systemImage: "externaldrive.badge.plus")
            } description: {
                Text("The license database has not been created. Create it before searching.")
            } actions: {
                Button("Create Database…") {
                    model.confirmDatabaseUpdate = true
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.records.isEmpty {
            ContentUnavailableView {
                Label("Ham Radio Lookup", systemImage: "antenna.radiowaves.left.and.right")
            } description: {
                Text("Search FCC license records by call sign, name, city, or state.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.filteredRecords.isEmpty {
            ContentUnavailableView(
                "No Matching Rows",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Nothing in these results contains “\(model.filter.trimmingCharacters(in: .whitespacesAndNewlines))”.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ResultsTable(model: model)
        }
    }

    private func statusBar(_ summary: String) -> some View {
        HStack {
            Text(summary)
            Spacer()
            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityLabel(summary)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Database Settings…") {
                showDatabaseSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var databaseNoticePresented: Binding<Bool> {
        Binding(
            get: { model.databaseNotice != nil },
            set: { isPresented in
                if !isPresented {
                    model.databaseNotice = nil
                }
            }
        )
    }

    private func showDatabaseSettings() {
        openSettings()
        Task { @MainActor in
            if await revealSettingsWindow() { return }
            performSettingsMenuItem()
            _ = await revealSettingsWindow()
        }
    }

    /// SwiftUI creates the settings window on a later turn, and it can open behind this window.
    private func revealSettingsWindow() async -> Bool {
        for _ in 0..<8 {
            if let window = NSApp.windows.first(where: { $0.frameAutosaveName == "com_apple_SwiftUI_Settings_window" }) {
                placeOnScreen(window)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    private func performSettingsMenuItem() {
        let selector = Selector(("showSettingsWindow:"))
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items {
            guard let submenu = item.submenu,
                  let index = submenu.items.firstIndex(where: { $0.action == selector })
            else { continue }
            submenu.performActionForItem(at: index)
            return
        }
    }

    private func placeOnScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        let visiblePart = visible.intersection(frame)
        if visiblePart.width > 80, visiblePart.height > 80 { return }
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#Preview {
    ContentView(model: .preview)
        .frame(width: 1100, height: 720)
}
