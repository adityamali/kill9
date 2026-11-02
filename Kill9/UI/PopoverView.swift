import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: PortStore
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("KILL9")
                    .font(.custom("Impact", size: 17))
                    .foregroundStyle(LinearGradient(colors: [Color.primary, Color.secondary],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.mini).accessibilityLabel("Refreshing ports")
                }
                Button(action: store.toggleDiscoverySettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Discovery settings (⌘,)")
                .accessibilityLabel("Discovery settings")
                .keyboardShortcut(",", modifiers: .command)
                Button(action: store.refresh) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh ports (⌘R)")
                .accessibilityLabel("Refresh ports")
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)

            Divider().opacity(0.5)

            if store.showingDiscoverySettings {
                DiscoveryPreferencesView(settings: store.discoverySettings,
                                         save: store.updateDiscoverySettings,
                                         cancel: store.toggleDiscoverySettings)
            } else if store.listeners.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: store.isRefreshing ? "network" : "checkmark.circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(store.isRefreshing ? "Scanning dev ports…" : (store.errorMessage != nil ? "Ports unavailable" : "No matching dev servers"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: store.bodyHeight)
            } else if ListGeometry.needsScrolling(for: store.listeners.count) {
                ScrollView(.vertical) {
                    rows
                }
                .frame(height: ListGeometry.ceiling)
            } else {
                rows.frame(height: store.bodyHeight)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 52)
                    .help(error)
                    .accessibilityLabel(error)
            }

            Divider().opacity(0.5)
            HStack {
                Text(store.hasSnapshot ? "\(store.listeners.count) dev port\(store.listeners.count == 1 ? "" : "s")" : "Development ports")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit", action: quit)
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
        }
        .frame(width: ListGeometry.width)
        .background(VisualEffectView())
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            ForEach(store.listeners) { listener in
                PortRow(listener: listener,
                        isStopping: listener.identity.map { store.stopping.contains($0) } ?? false,
                        canForce: listener.identity.map { store.forceAvailable.contains($0) } ?? false) {
                    store.stop(listener)
                }
                .contextMenu {
                    Button("Choose Project Folder…") { store.chooseProjectFolder(for: listener) }
                        .disabled(listener.projectOverrideKey == nil)
                    if listener.project?.isUserSelected == true {
                        Button("Use Detected Project") { store.resetProjectFolder(for: listener) }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
