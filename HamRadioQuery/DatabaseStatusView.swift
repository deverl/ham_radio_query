import AppKit
import SwiftUI

struct DatabaseStatusView: View {
    @Bindable var model: LookupModel
    @State private var draft: ConnectionSettings
    @State private var status: String?
    @State private var testing = false

    init(model: LookupModel) {
        self.model = model
        _draft = State(initialValue: model.connectionSettings)
    }

    var body: some View {
        Form {
            Picker("Database", selection: $model.engine) {
                Text("SQLite").tag(DatabaseEngine.sqlite)
                Text("MySQL").tag(DatabaseEngine.mysql)
                Text("PostgreSQL").tag(DatabaseEngine.postgres)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .onChange(of: model.engine) { _, newValue in
                model.applyEngine(newValue)
                draft = model.connectionSettings
                status = nil
                fitSettingsWindow()
            }

            if model.engine == .mysql || model.engine == .postgres {
                Section("Server") {
                    TextField("Host", text: $draft.host)
                    TextField("Port", value: $draft.port, format: .number.grouping(.never))
                    TextField("Database", text: $draft.database)
                }
                Section("Account") {
                    TextField("Username", text: $draft.username)
                    SecureField("Password", text: $draft.password)
                }
                Section {
                    HStack {
                        Button("Use Local Defaults") {
                            draft = model.engine == .postgres ? .postgres : .standard
                            status = "Defaults filled in. Save to keep them."
                        }
                        Spacer()
                        if testing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Test Connection") {
                            Task { await testConnection() }
                        }
                        .disabled(testing)
                        Button("Save") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(testing)
                    }
                    Button("Update Database…") {
                        bringMainWindowForward()
                        model.confirmDatabaseUpdate = true
                    }
                    .disabled(model.isUpdatingDatabase || model.isSearching || testing)
                }
                if let status {
                    Section {
                        Text(status)
                            .foregroundStyle(succeeded(status) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    }
                }
                Section {
                    Text(model.engine == .postgres
                        ? "The local PostgreSQL defaults are host 127.0.0.1, port 5432, database fcc, and user fccuser."
                        : "The FCC web app uses host 127.0.0.1, port 3306, database fcc, and user fccuser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
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
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .background(SettingsScrollerHider())
        .padding(20)
        .frame(width: 560, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            draft = model.connectionSettings
            if model.engine == .sqlite {
                model.refreshFreshness()
            }
            fitSettingsWindow()
        }
    }

    private func succeeded(_ status: String) -> Bool {
        status.hasPrefix("Connected") || status.hasPrefix("Saved") || status.hasPrefix("Defaults")
    }

    private func save() {
        if let warning = model.updateConnection(draft) {
            status = warning
        } else {
            status = "Saved."
            draft = model.connectionSettings
        }
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        do {
            if model.engine == .postgres {
                try await PostgresLicenseDatabase.test(draft)
            } else {
                try await MySQLLicenseDatabase.test(draft)
            }
            let normalized = draft.normalized()
            status = "Connected to \(normalized.database) on \(normalized.host):\(normalized.port)."
        } catch {
            status = error.localizedDescription
        }
    }

    private func bringMainWindowForward() {
        NSApp.windows.first { $0.frameAutosaveName.contains("WindowGroup") }?.makeKeyAndOrderFront(nil)
    }

    /// The settings window remembers a short frame. Grow it so the MySQL buttons stay on screen.
    private func fitSettingsWindow() {
        let minimum: CGFloat = model.engine == .sqlite ? 340 : 680
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard let window = NSApp.windows.first(where: {
                $0.frameAutosaveName == "com_apple_SwiftUI_Settings_window"
            }) else { return }
            let fitting = window.contentView?.fittingSize.height ?? minimum
            let height = max(minimum, fitting)
            var frame = window.frame
            let width: CGFloat = 560
            if abs(frame.height - height) >= 2 || abs(frame.width - width) >= 2 {
                let delta = height - frame.height
                frame.size.width = width
                frame.size.height = height
                frame.origin.y -= delta
                window.setFrame(frame, display: true)
            }
            hideSettingsScrollers(in: window)
        }
    }

    /// The grouped form is a scroll view. Hide its bar when the contents already fit.
    private func hideSettingsScrollers(in window: NSWindow) {
        guard let content = window.contentView else { return }
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
                scroll.autohidesScrollers = true
                scroll.verticalScrollElasticity = .none
                scroll.horizontalScrollElasticity = .none
            }
            for subview in view.subviews {
                walk(subview)
            }
        }
        walk(content)
    }
}

/// The grouped settings form is a scroll view. Its bar stays hidden because the window is sized to the form.
private struct SettingsScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollerHidingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollerHidingView)?.hideEnclosingScrollers()
    }
}

private final class ScrollerHidingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideEnclosingScrollers()
    }

    override func layout() {
        super.layout()
        hideEnclosingScrollers()
    }

    func hideEnclosingScrollers() {
        var view: NSView? = superview
        while let current = view {
            if let scroll = current as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
                scroll.autohidesScrollers = true
                scroll.verticalScrollElasticity = .none
                scroll.horizontalScrollElasticity = .none
            }
            view = current.superview
        }
    }
}
