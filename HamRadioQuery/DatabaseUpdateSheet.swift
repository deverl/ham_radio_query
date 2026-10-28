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
