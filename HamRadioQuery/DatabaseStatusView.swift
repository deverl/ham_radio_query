import AppKit
import SwiftUI

struct DatabaseStatusView: View {
    @Bindable var model: LookupModel

    var body: some View {
        Form {
            LabeledContent("Location") {
                Text(LicenseStore.databaseURL.path)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Last built") {
                Text(model.freshnessDescription)
            }
            if case .stale = model.freshness {
                Text("This database is more than 8 days old and should be updated.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(model.freshness.isMissing ? "Create Database…" : "Update Database…") {
                bringMainWindowForward()
                model.confirmDatabaseUpdate = true
            }
            .disabled(model.isUpdatingDatabase || model.isSearching)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
        .onAppear {
            model.refreshFreshness()
        }
    }

    private func bringMainWindowForward() {
        NSApp.windows.first { $0.frameAutosaveName.contains("WindowGroup") }?.makeKeyAndOrderFront(nil)
    }
}
