import SwiftUI

struct DatabaseUpdateSheet: View {
    @Bindable var model: LookupModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Update License Database")
                    .font(.title2.weight(.semibold))
                Text(model.updateStatus)
                if let fraction = model.updateFraction {
                    ProgressView(value: fraction)
                } else if model.isUpdatingDatabase {
                    ProgressView()
                        .controlSize(.small)
                }
                if !model.updateDetail.isEmpty {
                    Text(model.updateDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let updateError = model.updateError {
                    Text(updateError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.isUpdatingDatabase && !model.updateCanCancel {
                    Text("This step cannot be cancelled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Downloaded files stay in /tmp/ham-radio-lookup until the next restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    if model.isUpdatingDatabase {
                        Button("Cancel") {
                            model.cancelDatabaseUpdate()
                        }
                        .disabled(!model.updateCanCancel)
                    } else {
                        Button("Done") {
                            model.isPresentingUpdate = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(24)
            .frame(width: 480, alignment: .leading)
        }
        .frame(maxHeight: 420)
        .interactiveDismissDisabled(model.isUpdatingDatabase)
    }
}

struct DatabaseConfirmSheet: View {
    @Binding var buildStateIndex: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shownTitle: String
    @State private var shownMessage: String
    @State private var shownConfirm: String
    @State private var shownCancel: String

    init(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String,
        buildStateIndex: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) {
        self._buildStateIndex = buildStateIndex
        self.onConfirm = onConfirm
        _shownTitle = State(initialValue: title)
        _shownMessage = State(initialValue: message)
        _shownConfirm = State(initialValue: confirmTitle)
        _shownCancel = State(initialValue: cancelTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(shownTitle)
                .font(.title2.weight(.semibold))
            Text(shownMessage)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $buildStateIndex) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build an index for state-only searches")
                    Text("This adds significant time to database creation, and speeds up state-only searches.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(shownCancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(shownConfirm) {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
    }
}
