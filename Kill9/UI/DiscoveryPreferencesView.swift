import SwiftUI

struct DiscoveryPreferencesView: View {
    let save: (DiscoverySettings) -> Void
    let cancel: () -> Void
    @State private var automatic: Bool
    @State private var included: String
    @State private var excluded: String
    @State private var validationError: String?

    init(settings: DiscoverySettings, save: @escaping (DiscoverySettings) -> Void, cancel: @escaping () -> Void) {
        self.save = save
        self.cancel = cancel
        _automatic = State(initialValue: settings.automatic)
        _included = State(initialValue: settings.includedText)
        _excluded = State(initialValue: settings.excludedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Discovery").font(.system(size: 12, weight: .semibold))
            Toggle("Detect dev servers on any port", isOn: $automatic)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            portField("Always include ports", placeholder: "12345, 20000-20100", text: $included)
            portField("Always hide ports", placeholder: "9229, 50000-50100", text: $excluded)
            Text(validationError ?? "Comma-separated ports or ranges. Hide rules take priority. Includes can show any listener you own.")
                .font(.system(size: 10))
                .foregroundStyle(validationError == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 40, alignment: .topLeading)
                .accessibilityLabel(validationError ?? "Hide rules override includes. Explicit includes can show any listener you own.")
            HStack {
                Button("Cancel", action: cancel)
                Spacer()
                Button("Save") {
                    do {
                        let settings = try DiscoverySettings(automatic: automatic, included: included, excluded: excluded)
                        save(settings)
                    } catch { validationError = error.localizedDescription }
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 274)
    }

    private func portField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .accessibilityLabel(title)
        }
    }
}
