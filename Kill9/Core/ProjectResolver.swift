import Foundation
import Darwin

struct ProjectMetadata: Hashable, Sendable {
    let name: String
    let directory: URL
    let manifest: URL?
    var hasProjectEvidence = false
    var isUserSelected = false

    var nameSource: String {
        if isUserSelected { return "Project folder selected by you" }
        if manifest != nil { return "Name from package.json" }
        return "Folder name (inferred) — choose a project folder to correct it"
    }
}

enum ProjectResolver {
    /// Runs on the snapshot worker. Resolve each process/directory once per scan;
    /// no additional shell process, HTTP probe, or persistent metadata cache.
    static func enrich(_ listeners: [Listener], overrides: [String: String] = [:],
                       settings: DiscoverySettings = .defaults) -> [Listener] {
        var byPID: [Int32: ProjectMetadata] = [:]
        var visitedPIDs: Set<Int32> = []
        var byDirectory: [URL: ProjectMetadata] = [:]
        var workingDirectories: [Int32: URL] = [:]
        return listeners.map { listener in
            var row = listener
            guard listener.canTerminate,
                  DevelopmentPortFilter.isAutomaticCandidate(listener) || settings.included.contains(listener.port),
                  let identity = listener.identity else { return row }
            if visitedPIDs.insert(listener.pid).inserted,
               ProcessIdentity.read(pid: listener.pid) == identity,
               let directory = workingDirectory(pid: listener.pid) {
                workingDirectories[listener.pid] = directory
                let metadata = byDirectory[directory] ?? resolve(in: directory)
                // Avoid attaching metadata read after the original process exited.
                if ProcessIdentity.read(pid: listener.pid) == identity {
                    byPID[listener.pid] = metadata
                    byDirectory[directory] = metadata
                }
            }
            row.project = byPID[listener.pid]
            row.workingDirectory = workingDirectories[listener.pid]
            if let key = row.projectOverrideKey, let chosenPath = overrides[key],
               ProcessIdentity.read(pid: listener.pid) == identity {
                let chosen = URL(fileURLWithPath: chosenPath, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: chosen.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    // Only inspect the explicitly selected folder; don't silently
                    // replace the user's selection with an ancestor project.
                    let manifest = chosen.appendingPathComponent("package.json")
                    let packageName = readPackage(manifest).flatMap { cleanName($0["name"] as? String) }
                    row.project = ProjectMetadata(name: packageName ?? chosen.lastPathComponent,
                                                  directory: chosen, manifest: packageName == nil ? nil : manifest,
                                                  hasProjectEvidence: true, isUserSelected: true)
                }
            }
            return row
        }
    }

    static func workingDirectory(pid: Int32) -> URL? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(size)) == Int32(size) else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func resolve(in workingDirectory: URL) -> ProjectMetadata? {
        var directory = workingDirectory.standardizedFileURL
        // A server launched from a dependency's directory belongs to its consumer,
        // rather than the nearest package under node_modules.
        let parts = directory.pathComponents
        if let dependencyIndex = parts.firstIndex(of: "node_modules") {
            directory = URL(fileURLWithPath: NSString.path(withComponents: Array(parts[..<dependencyIndex])),
                            isDirectory: true)
        }
        let fallbackDirectory = directory
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        for _ in 0..<12 {
            guard directory.path != "/", directory != home else { break }
            let manifest = directory.appendingPathComponent("package.json")
            if let package = readPackage(manifest), let name = cleanName(package["name"] as? String) {
                return ProjectMetadata(name: name, directory: directory, manifest: manifest, hasProjectEvidence: true)
            }
            // Stop at the closest package even when unnamed: don't label a monorepo
            // workspace using its parent package's unrelated name.
            if FileManager.default.fileExists(atPath: manifest.path)
                || FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                var metadata = folderMetadata(directory)
                metadata?.hasProjectEvidence = true
                return metadata
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        guard fallbackDirectory.path != "/", fallbackDirectory != home else { return nil }
        return folderMetadata(fallbackDirectory)
    }

    private static func readPackage(_ url: URL) -> [String: Any]? {
        let limit = 256 * 1024
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= limit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func cleanName(_ name: String?) -> String? {
        guard let name else { return nil }
        let cleaned = name.components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(120))
    }

    private static func folderMetadata(_ directory: URL) -> ProjectMetadata? {
        guard let name = cleanName(directory.lastPathComponent) else { return nil }
        return ProjectMetadata(name: name, directory: directory, manifest: nil)
    }
}
