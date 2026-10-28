import SwiftUI

struct SearchPanel: View {
    @Bindable var model: LookupModel
    @State private var optionsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    field("Call Sign", prompt: "Exact", text: callSignBinding, monospaced: true)
                    field("First Name", prompt: "Starts with", text: $model.firstName)
                    field("Last Name", prompt: "Starts with", text: $model.lastName)
                }
                GridRow {
                    field("City", prompt: "Starts with", text: $model.city)
                    field("State", prompt: "ID", text: $model.state)
                        .frame(maxWidth: 160, alignment: .leading)
                    Color.clear.frame(height: 1)
                        .accessibilityHidden(true)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        optionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: optionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .frame(width: 12)
                        Text("Options")
                            .font(.subheadline.weight(.semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Options")
                .accessibilityValue(optionsExpanded ? "Expanded" : "Collapsed")

                Spacer()

                Button("Clear") {
                    model.clear()
                }
                .disabled(model.isSearching)
                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Search") {
                    model.search()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSearching)
            }

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    checkboxSection(title: "License Status") {
                        ForEach(LicenseStatus.allCases) { status in
                            Toggle(isOn: statusBinding(status)) {
                                Text("\(status.rawValue)  \(status.title)")
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    if model.licenseStatuses.isEmpty {
                        Text("None selected, so every status matches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    checkboxSection(title: "Operator Class") {
                        ForEach(OperatorClass.allCases) { operatorClass in
                            Toggle(isOn: classBinding(operatorClass)) {
                                Text("\(operatorClass.rawValue)  \(operatorClass.title)")
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    if model.operatorClasses.isEmpty {
                        Text("None selected, so every class matches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Call sign matches the whole value. Name and city match from the start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Apply Title Case", isOn: $model.applyTitleCase)
                        .toggleStyle(.checkbox)
                        .help("Capitalize names, street addresses, and cities in the results.")
                }
                .padding(.leading, 18)
            }
        }
        .padding(16)
    }

    private var callSignBinding: Binding<String> {
        Binding(
            get: { model.callSign },
            set: { model.callSign = $0.uppercased() }
        )
    }

    private func field(
        _ title: String,
        prompt: String,
        text: Binding<String>,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(monospaced ? .body.monospaced() : .body)
                .autocorrectionDisabled()
                .accessibilityLabel(title)
        }
    }

    private func checkboxSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            FlowLayout {
                content()
            }
        }
    }

    private func statusBinding(_ status: LicenseStatus) -> Binding<Bool> {
        Binding(
            get: { model.licenseStatuses.contains(status.rawValue) },
            set: { isOn in
                if isOn {
                    model.licenseStatuses.insert(status.rawValue)
                } else {
                    model.licenseStatuses.remove(status.rawValue)
                }
            }
        )
    }

    private func classBinding(_ operatorClass: OperatorClass) -> Binding<Bool> {
        Binding(
            get: { model.operatorClasses.contains(operatorClass.rawValue) },
            set: { isOn in
                if isOn {
                    model.operatorClasses.insert(operatorClass.rawValue)
                } else {
                    model.operatorClasses.remove(operatorClass.rawValue)
                }
            }
        )
    }
}
