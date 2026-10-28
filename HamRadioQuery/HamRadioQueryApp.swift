import AppKit
import SwiftUI

@main
struct HamRadioQueryApp: App {
    @State private var model = LookupModel()

    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 520)
        }
        .defaultSize(width: ResultColumns.defaultWindowWidth, height: 865)
        .commands {
            LookupCommands(model: model)
        }

        Settings {
            DatabaseStatusView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

struct LookupCommands: Commands {
    let model: LookupModel

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Export Results…") {
                model.isExporting = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model.filteredRecords.isEmpty)
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy Selected Rows") {
                model.copySelection()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.selection.isEmpty)
        }

        CommandMenu("Tools") {
            Button(model.maintenanceMenuTitle) {
                model.confirmDatabaseUpdate = true
            }
            .disabled(model.isUpdatingDatabase || model.isSearching)
        }
    }
}
