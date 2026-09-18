import SwiftUI
import ContainerKit

struct ContainersView: View {
    @EnvironmentObject var store: Store
    @State private var showingRun = false
    @State private var logsFor: ContainerInfo?
    @State private var query = ""

    var filtered: [ContainerInfo] {
        query.isEmpty ? store.containers
            : store.containers.filter {
                $0.id.localizedCaseInsensitiveContains(query)
                || $0.image.localizedCaseInsensitiveContains(query)
            }
    }

    var body: some View {
        Group {
            if !store.systemRunning {
                EngineStopped()
            } else if store.containers.isEmpty {
                ContentUnavailableView("No containers",
                    systemImage: "shippingbox",
                    description: Text("Launch one with the + button."))
            } else {
                List(selection: $store.selection) {
                    ForEach(filtered) { c in
                        ContainerRow(container: c,
                                     onLogs: { logsFor = c })
                        .tag(c.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Containers")
        .searchable(text: $query, prompt: "Filter by name or image")
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Refresh")
                Button { showingRun = true } label: {
                    Image(systemName: "plus")
                }.help("Run a new container")
                    .disabled(!store.systemRunning)
            }
        }
        .sheet(isPresented: $showingRun) { RunSheet() }
        .sheet(item: $logsFor) { LogsView(container: $0) }
    }
}

struct ContainerRow: View {
    @EnvironmentObject var store: Store
    let container: ContainerInfo
    let onLogs: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(container.runState.color.gradient)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(container.id).font(.headline)
                    StatusPill(state: container.runState)
                }
                Text(container.shortImage)
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                MetricChip(icon: "cpu", value: "\(container.cpus)")
                MetricChip(icon: "memorychip", value: Format.bytes(container.memoryBytes))
                if let ip = container.ipv4 {
                    MetricChip(icon: "network", value: ip.split(separator: "/").first.map(String.init) ?? ip)
                }
            }

            actions
        }
        .padding(.vertical, 6)
        .contextMenu { menuButtons }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 4) {
            if container.runState.isRunning {
                iconButton("stop.fill", "Stop", .orange) { store.stopContainer(container.id) }
            } else {
                iconButton("play.fill", "Start", .green) { store.startContainer(container.id) }
            }
            iconButton("text.alignleft", "Logs", .secondary, action: onLogs)
            iconButton("trash", "Remove", .red) {
                store.removeContainer(container.id, force: container.runState.isRunning)
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private var menuButtons: some View {
        if container.runState.isRunning {
            Button("Stop") { store.stopContainer(container.id) }
        } else {
            Button("Start") { store.startContainer(container.id) }
        }
        Button("Logs", action: onLogs)
        Divider()
        Button("Remove", role: .destructive) {
            store.removeContainer(container.id, force: container.runState.isRunning)
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(color)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .help(help)
    }
}

struct EngineStopped: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ContentUnavailableView {
            Label("Engine stopped", systemImage: "bolt.slash")
        } description: {
            Text("The container services aren't running.")
        } actions: {
            Button {
                store.toggleSystem()
            } label: {
                Label("Start engine", systemImage: "play.fill")
            }.buttonStyle(.borderedProminent)
        }
    }
}
