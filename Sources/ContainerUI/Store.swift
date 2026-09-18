import Foundation
import SwiftUI
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
    var binaryPath: String { cli.binaryPath }

    private var pollTask: Task<Void, Never>?
    private let interval: Duration = .seconds(2)

    // MARK: Derived

    var running: [ContainerInfo] { containers.filter { $0.runState.isRunning } }
    var selectedContainer: ContainerInfo? {
        guard let id = selection else { return nil }
        return containers.first { $0.id == id }
    }
    var runningCount: Int { running.count }

    // MARK: Lifecycle of the poller

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.interval ?? .seconds(2))
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    // MARK: Data

    func refresh() async {
        let running = await cli.systemStatus()
        self.systemRunning = running
        guard running else {
            containers = []; images = []
            return
        }
        do {
            async let c = cli.listContainers(all: true)
            async let i = cli.listImages()
            let (cs, imgs) = try await (c, i)
            self.containers = cs.sorted { $0.id < $1.id }
            self.images = imgs.sorted { $0.name < $1.name }
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

    func dismissError() { lastError = nil }
}
