import XCTest
import Darwin
@testable import Kill9Core

final class Kill9CoreTests: XCTestCase {
    private func projectFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kill9-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testProjectNameFromNearestPackageInMonorepo() throws {
        let root = try projectFixture()
        let workspace = root.appendingPathComponent("apps/storefront", isDirectory: true)
        let cwd = workspace.appendingPathComponent(".next/server", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try Data(#"{"name":"monorepo"}"#.utf8).write(to: root.appendingPathComponent("package.json"))
        try Data(#"{"name":"@acme/storefront"}"#.utf8).write(to: workspace.appendingPathComponent("package.json"))
        let project = try XCTUnwrap(ProjectResolver.resolve(in: cwd))
        XCTAssertEqual(project.name, "@acme/storefront")
        XCTAssertEqual(project.directory.path, workspace.path)
        XCTAssertEqual(project.manifest?.lastPathComponent, "package.json")
    }

    func testDependencyWorkingDirectoryResolvesConsumerProject() throws {
        let root = try projectFixture()
        let cwd = root.appendingPathComponent("node_modules/vite/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try Data(#"{"name":"my-dashboard"}"#.utf8).write(to: root.appendingPathComponent("package.json"))
        try Data(#"{"name":"vite"}"#.utf8).write(to: root.appendingPathComponent("node_modules/vite/package.json"))
        XCTAssertEqual(ProjectResolver.resolve(in: cwd)?.name, "my-dashboard")
    }

    func testMissingMalformedUnnamedAndOversizedMetadataUseFolderFallback() throws {
        let root = try projectFixture()
        let manifest = root.appendingPathComponent("package.json")
        XCTAssertEqual(ProjectResolver.resolve(in: root)?.name, root.lastPathComponent)
        for content in ["broken JSON", "{}", #"{"name":"  "}"#, #"{"name":123}"#, String(repeating: "x", count: 262_145)] {
            try Data(content.utf8).write(to: manifest)
            let project = try XCTUnwrap(ProjectResolver.resolve(in: root))
            XCTAssertEqual(project.name, root.lastPathComponent)
            XCTAssertNil(project.manifest)
        }
        XCTAssertNil(ProjectResolver.resolve(in: URL(fileURLWithPath: "/")))
        XCTAssertNil(ProjectResolver.resolve(in: FileManager.default.homeDirectoryForCurrentUser))
    }

    func testUnnamedWorkspaceDoesNotInheritMonorepoName() throws {
        let root = try projectFixture()
        let workspace = root.appendingPathComponent("apps/api", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data(#"{"name":"monorepo"}"#.utf8).write(to: root.appendingPathComponent("package.json"))
        try Data("{}".utf8).write(to: workspace.appendingPathComponent("package.json"))
        XCTAssertEqual(ProjectResolver.resolve(in: workspace)?.name, "api")
    }

    func testMetadataRefreshReadsRenamedPackage() throws {
        let root = try projectFixture()
        let manifest = root.appendingPathComponent("package.json")
        try Data(#"{"name":"old-name"}"#.utf8).write(to: manifest)
        XCTAssertEqual(ProjectResolver.resolve(in: root)?.name, "old-name")
        try Data(#"{"name":"new-name"}"#.utf8).write(to: manifest)
        XCTAssertEqual(ProjectResolver.resolve(in: root)?.name, "new-name")
    }

    func testProjectResolutionUsesActualProcessWorkingDirectory() throws {
        let root = try projectFixture()
        try Data(#"{"name":"live-project"}"#.utf8).write(to: root.appendingPathComponent("package.json"))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        child.currentDirectoryURL = root
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        let identity = try XCTUnwrap(ProcessIdentity.read(pid: child.processIdentifier))
        let original = Listener(pid: identity.pid, port: 3000, command: "sleep", identity: identity)
        let result = try XCTUnwrap(ProjectResolver.enrich([original]).first)
        XCTAssertEqual(ProjectResolver.workingDirectory(pid: identity.pid)?.resolvingSymlinksInPath().path,
                       root.resolvingSymlinksInPath().path)
        XCTAssertEqual(result.displayName, "live-project")
        XCTAssertEqual(result.id, original.id)
        XCTAssertTrue(result.detail.contains("sleep"))
        XCTAssertTrue(result.helpText.contains(root.lastPathComponent))
        XCTAssertEqual(original.displayName, "sleep")
    }

    func testFieldParsingAndIPv4IPv6Deduplication() {
        let output = """
        p402
        cCode Helper
        f12
        n127.0.0.1:5173
        f13
        n[::1]:5173
        n*:3000
        p403
        cnode
        n*:3000
        ninvalid
        n*:99999
        """
        let rows = ListenerParser.parse(output, identity: { _ in nil })
        XCTAssertEqual(rows.map(\.port), [3000, 3000, 5173])
        XCTAssertEqual(rows.map(\.pid), [402, 403, 402])
        XCTAssertEqual(rows.last?.command, "Code Helper")
        XCTAssertFalse(rows[0].canTerminate)
    }

    func testEmptyAndMalformedSnapshots() {
        XCTAssertTrue(ListenerParser.parse("").isEmpty)
        XCTAssertTrue(ListenerParser.parse("pbad\ncnode\nn*:3000").isEmpty)
        XCTAssertTrue(ListenerParser.parse("p123\nn*:3000").isEmpty)
    }

    func testScrollThresholdAndHeight() {
        XCTAssertEqual(ListGeometry.height(for: 1), 62)
        XCTAssertEqual(ListGeometry.height(for: 6), 292)
        XCTAssertFalse(ListGeometry.needsScrolling(for: 6))
        XCTAssertEqual(ListGeometry.height(for: 7), 300)
        XCTAssertTrue(ListGeometry.needsScrolling(for: 7))
        XCTAssertEqual(ListGeometry.height(for: 1000), 300)
    }

    func testDevelopmentFilterKeepsServersAndExcludesDesktopServices() {
        func row(_ command: String, _ port: UInt16) -> Listener {
            Listener(pid: 999, port: port, command: command,
                     identity: ProcessIdentity(pid: 999, userID: getuid(), startSeconds: 1, startMicroseconds: 0))
        }
        for (command, port) in [("node", UInt16(3000)), ("bun", 5173), ("python3.12", 8000),
                                ("java", 8080), ("node", 4173), ("next-server", 3001)] {
            XCTAssertTrue(DevelopmentPortFilter.includes(row(command, port)), "\(command):\(port)")
        }
        XCTAssertFalse(DevelopmentPortFilter.includes(row("ControlCenter", 5000)))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("ControlCenter", 7000)))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("figma_agent", 44950)))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("figma_agent", 3000)))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("rapportd", 49266)))
        XCTAssertTrue(DevelopmentPortFilter.includes(row("node", 49199)))
        XCTAssertTrue(DevelopmentPortFilter.includes(row("bun", 12345)))
        XCTAssertTrue(DevelopmentPortFilter.includes(row("python3.12", 65535)))
        var custom = row("my-rust-api", 12345)
        custom.project = ProjectMetadata(name: "api", directory: URL(fileURLWithPath: "/Users/dev/project"),
                                         manifest: nil, hasProjectEvidence: true)
        XCTAssertTrue(DevelopmentPortFilter.includes(custom, executablePath: "/Users/dev/project/target/debug/my-rust-api"))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("unknown-daemon", 3000), executablePath: "/usr/local/bin/unknown-daemon"))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("NativeHelper", 8080), executablePath: "/Applications/Example.app/Contents/MacOS/NativeHelper"))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("system-service", 3000), executablePath: "/System/Library/Services/system-service"))
        XCTAssertFalse(DevelopmentPortFilter.includes(row("helper", 3000), executablePath: "/usr/libexec/helper"))
        XCTAssertTrue(DevelopmentPortFilter.includes(row("node", 3000), executablePath: "/Applications/IDE.app/Contents/Resources/node"))
        let unowned = Listener(pid: 999, port: 3000, command: "node", identity: nil)
        XCTAssertFalse(DevelopmentPortFilter.includes(unowned))
    }

    func testCustomPortRulesValidationAndBoundaries() throws {
        let rules = try PortRules("1, 12345, 20000-20100 65535")
        for port: UInt16 in [1, 12345, 20000, 20050, 20100, 65535] { XCTAssertTrue(rules.contains(port)) }
        for port: UInt16 in [0, 12344, 19999, 20101] { XCTAssertFalse(rules.contains(port)) }
        XCTAssertFalse(try PortRules("").contains(3000))
        for invalid in ["0", "65536", "-1", "abc", "3000-", "4000-3000", "1-2-3"] {
            XCTAssertThrowsError(try PortRules(invalid), invalid)
        }
    }

    func testConfiguredPortsOverrideAutomaticDiscoveryAndHideWins() throws {
        let identity = ProcessIdentity(pid: 999, userID: getuid(), startSeconds: 1, startMicroseconds: 0)
        let helper = Listener(pid: 999, port: 12345, command: "NativeHelper", identity: identity)
        let rules = try DiscoverySettings(automatic: false, included: "12345, 20000-20100", excluded: "20050")
        XCTAssertTrue(DevelopmentPortFilter.includes(helper, settings: rules))
        let hidden = Listener(pid: 999, port: 20050, command: "node", identity: identity)
        XCTAssertFalse(DevelopmentPortFilter.includes(hidden, settings: rules))
        let auto = Listener(pid: 999, port: 54321, command: "node", identity: identity)
        XCTAssertFalse(DevelopmentPortFilter.includes(auto, settings: rules))
        XCTAssertTrue(DevelopmentPortFilter.includes(auto))
        let unowned = Listener(pid: 999, port: 12345, command: "node", identity: nil)
        XCTAssertFalse(DevelopmentPortFilter.includes(unowned, settings: rules))
    }

    func testDiscoveryPreferencesPersistAndRecoverFromInvalidStoredRules() throws {
        let suite = "dev.kill9.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(DiscoverySettings.load(from: defaults), .defaults)
        let settings = try DiscoverySettings(automatic: false, included: "12000-13000", excluded: "12345")
        settings.save(to: defaults)
        XCTAssertEqual(DiscoverySettings.load(from: defaults), settings)
        defaults.set("invalid", forKey: "discovery.included")
        XCTAssertEqual(DiscoverySettings.load(from: defaults), .defaults)
    }

    func testProjectFolderOverrideCorrectsNameAndIsScopedToWorkingDirectoryAndPort() throws {
        let actual = try projectFixture()
        let chosen = try projectFixture()
        try Data(#"{"name":"actual-project"}"#.utf8).write(to: actual.appendingPathComponent("package.json"))
        try Data(#"{"name":"chosen-project"}"#.utf8).write(to: chosen.appendingPathComponent("package.json"))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        child.currentDirectoryURL = actual
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        let identity = try XCTUnwrap(ProcessIdentity.read(pid: child.processIdentifier))
        let original = Listener(pid: identity.pid, port: 12345, command: "sleep", identity: identity)
        let detected = try XCTUnwrap(ProjectResolver.enrich([original]).first)
        let key = try XCTUnwrap(detected.projectOverrideKey)
        let overrides = [key: chosen.path]
        let corrected = try XCTUnwrap(ProjectResolver.enrich([original], overrides: overrides).first)
        XCTAssertEqual(corrected.displayName, "chosen-project")
        XCTAssertEqual(corrected.project?.isUserSelected, true)
        XCTAssertTrue(corrected.helpText.contains("selected by you"))
        XCTAssertEqual(corrected.id, original.id)
        XCTAssertEqual(ProjectResolver.enrich([original]).first?.displayName, "actual-project")
        let otherPort = Listener(pid: identity.pid, port: 12346, command: "sleep", identity: identity)
        XCTAssertEqual(ProjectResolver.enrich([otherPort], overrides: overrides).first?.displayName, "actual-project")
        var otherDirectory = detected
        otherDirectory.workingDirectory = chosen
        XCTAssertNotEqual(otherDirectory.projectOverrideKey, key)
        XCTAssertEqual(ProjectResolver.enrich([original], overrides: [key: "/nonexistent-kill9-project"]).first?.displayName,
                       "actual-project")
    }

    func testSnapshotFindsRealListeningSocket() async throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(descriptor, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        XCTAssertEqual(named, 0)
        let port = UInt16(bigEndian: address.sin_port)
        let rows = try await PortService().snapshot()
        XCTAssertTrue(rows.contains { $0.pid == getpid() && $0.port == port })
    }

    func testGracefulTerminationOfOwnedChild() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let identity = try XCTUnwrap(ProcessIdentity.read(pid: child.processIdentifier))
        try await PortService().stop(identity)
        child.waitUntilExit()
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGTERM)
    }

    func testStaleIdentityCannotSignalChild() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        let real = try XCTUnwrap(ProcessIdentity.read(pid: child.processIdentifier))
        let stale = ProcessIdentity(pid: real.pid, userID: real.userID,
                                    startSeconds: real.startSeconds + 1,
                                    startMicroseconds: real.startMicroseconds)
        do {
            try await PortService().stop(stale)
            XCTFail("Stale PID identity must be rejected")
        } catch PortServiceError.processChanged { }
        XCTAssertTrue(child.isRunning)
    }

    func testExplicitForceTerminationOfOwnedChild() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let identity = try XCTUnwrap(ProcessIdentity.read(pid: child.processIdentifier))
        try await PortService().stop(identity, force: true)
        child.waitUntilExit()
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
    }

    func testRefusesSelfAndSystemProcesses() async throws {
        let own = try XCTUnwrap(ProcessIdentity.read(pid: getpid()))
        XCTAssertFalse(own.canTerminate)
        do {
            try await PortService().stop(own)
            XCTFail("Must not terminate the app itself")
        } catch PortServiceError.protectedProcess { }
        let system = ProcessIdentity(pid: 1, userID: getuid(), startSeconds: 0, startMicroseconds: 0)
        XCTAssertFalse(system.canTerminate)
    }
}
