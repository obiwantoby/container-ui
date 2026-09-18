import Foundation
import SwiftUI
import IOKit.ps
import ContainerKit

/// The app's single source of truth. Polls the CLI on a timer and exposes
/// lifecycle actions. Lives on the main actor so views can bind directly.
@MainActor
final class Store: ObservableObject {
    @Published var containers: [ContainerInfo] = []
    @Published var images: [ImageInfo] = []
    @Published var systemRunning = false
    @Published var lastError: String?
    @Published var busy = false
    @Published var selection: String?          // selected container id

    let cli = ContainerCLI()
    let ai = Assistant()
    var binaryPath: String { cli.binaryPath }
    @Published var aiAvailable = false
    private var runHelp = ""

    private var pollTask: Task<Void, Never>?
    private var tick = 0

    /// Adaptive poll cadence: idle when nothing runs, gentler on battery, snappy
    /// when active and plugged in. Halves idle wakeups without any felt lag.
    private var currentInterval: Duration {
        if runningCount == 0 { return .seconds(5) }
        return onBattery ? .seconds(3) : .seconds(2)
    }

    /// True when the Mac is running on battery (IOKit power source).
    private var onBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }
    private let imageEveryNTicks = 5          // refetch images ~every 10s, not 2s
    var active = true                         // paused when the app is inactive

    // MARK: Derived

    var running: [ContainerInfo] { containers.filter { $0.runState.isRunning } }
    var selectedContainer: ContainerInfo? {
        guard let id = selection else { return nil }
        return containers.first { $0.id == id }
    }
    var runningCount: Int { running.count }

    // MARK: Lifecycle of the poller

    func start() {
        Task {
            aiAvailable = await ai.isAvailable()
            runHelp = await cli.help(["run"])
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.active == true { await self?.refresh() }
                try? await Task.sleep(for: self?.currentInterval ?? .seconds(2))
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    // MARK: Data

    /// Full refresh (used by manual refresh and the poll loop). Images are only
    /// refetched every few ticks since they change rarely.
    func refresh() async {
        let includeImages = (tick % imageEveryNTicks == 0)
        tick &+= 1
        await refresh(includeImages: includeImages)
    }

    func refresh(includeImages: Bool) async {
        let running = await cli.systemStatus()
        self.systemRunning = running
        guard running else {
            containers = []; images = []
            return
        }
        do {
            self.containers = try await cli.listContainers(all: true).sorted { $0.id < $1.id }
            if includeImages {
                self.images = try await cli.listImages().sorted { $0.name < $1.name }
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: Actions

    private func perform(_ label: String, _ op: @escaping () async throws -> Void) {
        Task {
            busy = true; defer { busy = false }
            do { try await op(); await refresh() }
            catch { lastError = "\(label): \(error.localizedDescription)" }
        }
    }

    func startContainer(_ id: String) { perform("Start") { try await self.cli.start(id) } }
    func stopContainer(_ id: String) { perform("Stop") { try await self.cli.stop(id) } }
    func removeContainer(_ id: String, force: Bool) { perform("Remove") { try await self.cli.remove(id, force: force) } }
    func toggleSystem() {
        perform(systemRunning ? "System stop" : "System start") {
            if await self.cli.systemStatus() { try await self.cli.systemStop() }
            else { try await self.cli.systemStart() }
        }
    }
    func run(_ spec: RunSpec) { perform("Run") { _ = try await self.cli.runContainer(spec) } }

    /// Run raw `container run <args>` (used by the AI-suggested command).
    func runRaw(flags: [String]) { perform("Run") { try await self.cli.runChecked(["run"] + flags) } }

    /// Apply config changes (e.g. new mounts) to an existing container by
    /// replacing it: a container's mounts/resources are fixed at creation, so
    /// we remove the old one and run a new one with the updated spec.
    func recreate(oldID: String, spec: RunSpec) {
        perform("Recreate") {
            try await self.cli.remove(oldID, force: true)
            _ = try await self.cli.runContainer(spec)
        }
    }

    /// Run a one-shot command in a container; returns output via completion.
    func exec(_ id: String, command: String, then completion: @escaping (String) -> Void) {
        Task {
            do { completion(try await cli.exec(id, command: command)) }
            catch { completion("Error: \(error.localizedDescription)") }
        }
    }

    /// Open an interactive shell in Terminal.app (the interactive session the
    /// GUI itself can't host).
    func openShell(_ id: String, shell: String = "bash") {
        let cmd = cli.interactiveShellCommand(id, shell: shell)
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    // MARK: On-device assistant (Apple Foundation Models)

    func explain(_ c: ContainerInfo, then completion: @escaping (String) -> Void) {
        Task {
            let json = (try? JSONEncoder().encode(c)).flatMap { String(data: $0, encoding: .utf8) } ?? c.id
            completion(await ai.explain(containerJSON: json))
        }
    }

    /// Natural language → a structured, grounded draft the Run form fills in.
    func suggestRunDraft(_ request: String, then completion: @escaping (Assistant.RunSpecDraft?) -> Void) {
        Task { completion(await ai.suggestRunDraft(request, help: runHelp)) }
    }

    func diagnose(_ id: String, then completion: @escaping (String) -> Void) {
        Task {
            let (stream, cancel) = await cli.logStream(id, follow: false, tail: 300)
            var buf = ""
            for await line in stream { buf += line + "\n" }
            cancel()
            completion(await ai.diagnose(logs: buf))
        }
    }

    func dismissError() { lastError = nil }
}
