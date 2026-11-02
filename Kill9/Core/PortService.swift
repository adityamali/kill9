import Foundation
import Darwin

enum PortServiceError: LocalizedError {
    case scanFailed(String)
    case scanTimedOut
    case processChanged
    case protectedProcess
    case signalFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .scanFailed(let detail): return "Couldn’t read listening ports. \(detail)"
        case .scanTimedOut: return "Port scan timed out. Try refreshing."
        case .processChanged: return "This process has exited or changed. Refresh and try again."
        case .protectedProcess: return "Only your own processes can be stopped."
        case .signalFailed(let code): return "Couldn’t stop process: \(String(cString: strerror(code)))."
        }
    }
}

struct PortService: Sendable {
    func snapshot(settings: DiscoverySettings = .defaults,
                  projectOverrides: [String: String] = [:]) async throws -> [Listener] {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            // Same TCP LISTEN snapshot as `lsof -iTCP -sTCP:LISTEN -n -P`,
            // with field output to avoid fragile whitespace/table parsing.
            process.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P", "-Fpcn"]
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            try process.run()

            let timeout = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    // Bound a stuck scanner, never the user's selected process.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            // Drain before waitUntilExit: a full pipe must never deadlock lsof.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            let output = String(decoding: data, as: UTF8.self)
            if process.terminationReason == .uncaughtSignal { throw PortServiceError.scanTimedOut }
            if process.terminationStatus == 1 && output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [] // lsof uses 1 when no descriptors match.
            }
            guard process.terminationStatus == 0 else {
                throw PortServiceError.scanFailed(String(output.prefix(240)))
            }
            return ProjectResolver.enrich(ListenerParser.parse(output), overrides: projectOverrides, settings: settings)
        }.value
    }

    func stop(_ identity: ProcessIdentity, force: Bool = false) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard identity.canTerminate else { throw PortServiceError.protectedProcess }
            // Recheck birth time and owner immediately before signaling to reject
            // stale rows/PID reuse. No shell interpolation, sudo, or elevated helper.
            guard ProcessIdentity.read(pid: identity.pid) == identity else {
                throw PortServiceError.processChanged
            }
            guard Darwin.kill(identity.pid, force ? SIGKILL : SIGTERM) == 0 else {
                let code = errno
                throw PortServiceError.signalFailed(code)
            }
        }.value
    }
}
