import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: LookupModel
    @FocusState private var filterFocused: Bool

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
                    openSettings()
                } label: {
                    Label("Database", systemImage: "server.rack")
                }
                .help("Database connection settings")
            }
        }
        .alert("Update License Database?", isPresented: $model.confirmDatabaseUpdate) {
            Button("Update") {
                Task { @MainActor in
                    await Task.yield()
                    model.startDatabaseUpdate()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This downloads the latest FCC amateur license file (about 190 MB) and the RadioID user list, then rebuilds the database. The current license tables are replaced. Downloaded files are left in /tmp/ham-radio-lookup.")
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
                    openSettings()
                }
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
                openSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
