import SwiftUI
import AppKit

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var listeners: [Listener] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var stopping: Set<ProcessIdentity> = []
    @Published private(set) var forceAvailable: Set<ProcessIdentity> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasSnapshot = false
    @Published private(set) var discoverySettings = DiscoverySettings.load()
    @Published private(set) var showingDiscoverySettings = false
    var onLayoutChange: (() -> Void)?

    private let service = PortService()
    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false
    private var projectOverrides = UserDefaults.standard.dictionary(forKey: "discovery.projectFolders") as? [String: String] ?? [:]

    func toggleDiscoverySettings() {
        showingDiscoverySettings.toggle()
        onLayoutChange?()
    }

    func updateDiscoverySettings(_ settings: DiscoverySettings) {
        settings.save()
        discoverySettings = settings
        showingDiscoverySettings = false
        onLayoutChange?()
        refresh()
    }

    func chooseProjectFolder(for listener: Listener) {
        guard let key = listener.projectOverrideKey else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Project Folder"
        panel.message = "Use this folder to identify \(listener.command) on port \(listener.port)."
        panel.prompt = "Use Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = listener.project?.directory ?? listener.workingDirectory
        panel.begin { [weak self] response in
            guard response == .OK, let directory = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.projectOverrides[key] = directory.path
                UserDefaults.standard.set(self.projectOverrides, forKey: "discovery.projectFolders")
                self.refresh()
            }
        }
    }

    func resetProjectFolder(for listener: Listener) {
        guard let key = listener.projectOverrideKey else { return }
        projectOverrides.removeValue(forKey: key)
        UserDefaults.standard.set(projectOverrides, forKey: "discovery.projectFolders")
        refresh()
    }

    func refresh() {
        // Coalesce rapid clicks, but guarantee an invocation made during an older
        // scan gets a new snapshot once that scan finishes.
        guard refreshTask == nil else { refreshAgain = true; return }
        refreshTask = Task {
            repeat {
                refreshAgain = false
                isRefreshing = true
                do {
                    let snapshot = try await service.snapshot(settings: discoverySettings, projectOverrides: projectOverrides)
                    listeners = snapshot.filter { DevelopmentPortFilter.includes($0, settings: discoverySettings) }
                    hasSnapshot = true
                    errorMessage = nil
                    let live = Set(listeners.compactMap(\.identity))
                    forceAvailable.formIntersection(live)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isRefreshing = false
                onLayoutChange?()
            } while refreshAgain
            refreshTask = nil
        }
    }

    func stop(_ listener: Listener) {
        guard let identity = listener.identity, !stopping.contains(identity) else { return }
        let force = forceAvailable.contains(identity)
        stopping.insert(identity)
        errorMessage = nil
        onLayoutChange?()
        Task {
            defer { stopping.remove(identity) }
            do {
                try await service.stop(identity, force: force)
                // Give graceful shutdown a chance to release the socket. Waiting
                // suspends the task; AppKit and SwiftUI stay responsive.
                try await Task.sleep(nanoseconds: force ? 250_000_000 : 1_200_000_000)
                if !force { forceAvailable.insert(identity) }
                refresh()
            } catch {
                errorMessage = error.localizedDescription
                onLayoutChange?()
                // Preserve this actionable error until the next explicit refresh.
            }
        }
    }

    var bodyHeight: CGFloat {
        if showingDiscoverySettings { return 274 }
        if listeners.isEmpty { return 92 }
        return ListGeometry.height(for: listeners.count)
    }
    var popoverHeight: CGFloat { 40 + 1 + bodyHeight + 1 + 30 + (errorMessage == nil ? 0 : 52) }
}
