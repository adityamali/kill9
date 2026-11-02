import Foundation
import Darwin

struct ProcessIdentity: Hashable, Sendable {
    let pid: Int32
    let userID: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64

    static func read(pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == Int32(size) else {
            return nil
        }
        return ProcessIdentity(pid: pid, userID: info.pbi_uid,
                               startSeconds: info.pbi_start_tvsec,
                               startMicroseconds: info.pbi_start_tvusec)
    }

    var canTerminate: Bool {
        pid > 1 && pid != getpid() && userID == getuid()
    }
}

struct Listener: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let pid: Int32
        let port: UInt16
        let identity: ProcessIdentity?
    }

    let pid: Int32
    let port: UInt16
    let command: String
    let identity: ProcessIdentity?
    var project: ProjectMetadata? = nil
    var workingDirectory: URL? = nil

    var id: ID { ID(pid: pid, port: port, identity: identity) }
    var canTerminate: Bool { identity?.canTerminate == true }
    var displayName: String { project?.name ?? command }
    var detail: String { project == nil ? "PID \(pid)" : "\(command) · PID \(pid)" }
    var helpText: String {
        [displayName, project?.nameSource ?? "Project not identified — showing process name",
         project?.directory.path, "\(command) · PID \(pid) · port \(port)"]
            .compactMap { $0 }.joined(separator: "\n")
    }
    /// Scope a manual mapping to this runtime, working directory, and port,
    /// rather than a PID or a port that another project could later reuse.
    var projectOverrideKey: String? {
        workingDirectory.map { [command, $0.path, String(port)].joined(separator: "\u{1F}") }
    }
}

enum ListenerParser {
    /// lsof field output preserves command names containing spaces. One row per
    /// process/port, even when IPv4 and IPv6 descriptors share that port.
    static func parse(_ output: String,
                      identity: (Int32) -> ProcessIdentity? = ProcessIdentity.read) -> [Listener] {
        var pid: Int32?
        var command = ""
        var rows: [Listener.ID: Listener] = [:]
        var identities: [Int32: ProcessIdentity] = [:]

        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                pid = Int32(value)
                command = ""
                if let pid, let token = identity(pid) { identities[pid] = token }
            case "c": command = value
            case "n":
                guard let pid, !command.isEmpty,
                      let suffix = value.split(separator: ":").last,
                      let port = UInt16(suffix), port > 0 else { continue }
                let row = Listener(pid: pid, port: port, command: command, identity: identities[pid])
                rows[row.id] = row
            default: continue
            }
        }
        return rows.values.sorted {
            $0.port == $1.port ? $0.pid < $1.pid : $0.port < $1.port
        }
    }
}

enum DevelopmentPortFilter {
    static func includes(_ listener: Listener, settings: DiscoverySettings = .defaults,
                         executablePath: String? = nil) -> Bool {
        guard listener.canTerminate, !settings.excluded.contains(listener.port) else { return false }
        // An explicit include can opt a user-owned helper into the list.
        if settings.included.contains(listener.port) { return true }
        guard settings.automatic, isAutomaticCandidate(listener, executablePath: executablePath) else { return false }
        return isDevelopmentRuntime(listener.command.lowercased())
            || listener.project?.hasProjectEvidence == true
            || listener.project?.isUserSelected == true
    }

    /// Inspect custom binaries for project evidence without admitting desktop
    /// applications or system helpers to automatic discovery.
    static func isAutomaticCandidate(_ listener: Listener, executablePath: String? = nil) -> Bool {
        guard listener.canTerminate else { return false }
        let command = listener.command.lowercased()
        // Also exclude these when proc_pidpath is unavailable or names are truncated.
        guard !command.hasPrefix("controlce"), !command.hasPrefix("figma"),
              command != "rapportd", command != "sharingd" else { return false }

        // Runtimes may legitimately live inside an IDE's application bundle.
        if isDevelopmentRuntime(command) { return true }

        guard let path = executablePath ?? pathForProcess(listener.pid) else { return false }
        let normalized = path.lowercased()
        // Allow custom Go/Rust/etc. server binaries without admitting native
        // desktop application helpers merely because they use a common port.
        return !normalized.hasPrefix("/system/")
            && !normalized.hasPrefix("/usr/libexec/")
            && !normalized.hasPrefix("/usr/sbin/")
            && !normalized.contains(".app/")
    }

    private static func isDevelopmentRuntime(_ command: String) -> Bool {
        let exact: Set<String> = [
            "node", "nodejs", "bun", "deno", "ruby", "php", "java", "dotnet",
            "go", "npm", "npx", "pnpm", "yarn", "vite", "uvicorn", "gunicorn",
            "flask", "django", "rails", "puma", "http-server", "httpd"
        ]
        if exact.contains(command) || command.hasPrefix("next-server") { return true }
        // python3, python3.12, ruby3.3, and php8.3 are common binary names.
        return ["python", "ruby", "php"].contains { prefix in
            guard command.hasPrefix(prefix) else { return false }
            let suffix = command.dropFirst(prefix.count)
            return suffix.allSatisfy { $0.isNumber || $0 == "." }
        }
    }

    private static func pathForProcess(_ pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is a C expression macro unavailable in Swift.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = buffer.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard count > 0 else { return nil }
        return String(cString: buffer)
    }
}

enum ListGeometry {
    static let width: CGFloat = 290
    static let rowHeight: CGFloat = 46
    static let ceiling: CGFloat = 300
    static func height(for count: Int) -> CGFloat {
        min(CGFloat(max(0, count)) * rowHeight + 16, ceiling)
    }
    static func needsScrolling(for count: Int) -> Bool {
        CGFloat(count) * rowHeight + 16 > ceiling
    }
}
