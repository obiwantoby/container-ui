import SwiftUI
import AppKit
import ContainerKit

struct ContainersView: View {
    @EnvironmentObject var store: Store
    @State private var showingRun = false
    @State private var logsFor: ContainerInfo?
    @State private var query = ""
    @State private var showInspector = true

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
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { c in
                            ContainerRow(container: c,
                                         selected: store.selection == c.id,
                                         onSelect: { store.selection = c.id },
                                         onLogs: { logsFor = c })
                        }
                    }
                    .padding(12)
                }
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
                }.help("Run a new container").disabled(!store.systemRunning)
                Button { showInspector.toggle() } label: {
                    Image(systemName: "sidebar.right")
                }.help("Toggle details")
            }
        }
        .inspector(isPresented: $showInspector) {
            if let c = store.selectedContainer {
                ContainerDetail(container: c, onLogs: { logsFor = c })
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
            } else {
                ContentUnavailableView("No selection", systemImage: "hand.point.up.left",
                    description: Text("Select a container to see details."))
            }
        }
        .sheet(isPresented: $showingRun) { RunSheet() }
        .sheet(item: $logsFor) { LogsView(container: $0) }
    }
}

// MARK: - Row (custom selection so text stays readable)

struct ContainerRow: View {
    @EnvironmentObject var store: Store
    let container: ContainerInfo
    let selected: Bool
    let onSelect: () -> Void
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
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Theme.cardBG.opacity(0.5))
        }
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor).frame(width: 3).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
            Button("Open shell in Terminal") { store.openShell(container.id) }
        } else {
            Button("Start") { store.startContainer(container.id) }
        }
        Button("Logs", action: onLogs)
        Button("Copy ID") { copy(container.id) }
        Divider()
        Button("Remove", role: .destructive) {
            store.removeContainer(container.id, force: container.runState.isRunning)
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(color)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }.help(help)
    }
}

// MARK: - Detail inspector

struct ContainerDetail: View {
    @EnvironmentObject var store: Store
    let container: ContainerInfo
    let onLogs: () -> Void
    @State private var execCommand = ""
    @State private var execOutput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .font(.largeTitle)
                        .foregroundStyle(container.runState.color.gradient)
                    VStack(alignment: .leading) {
                        Text(container.id).font(.title2.bold())
                        StatusPill(state: container.runState)
                    }
                }

                actionButtons

                Divider()

                field("Image", container.image, mono: true)
                if let ip = container.ipv4 {
                    field("IP address", ip, mono: true, copyable: true)
                }
                if let host = container.hostname { field("Hostname", host) }
                field("CPUs", "\(container.cpus)")
                field("Memory", Format.bytes(container.memoryBytes))
                field("Started", container.status.startedDate ?? "—")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Published ports").font(.caption.bold()).foregroundStyle(.secondary)
                    if container.portMappings.isEmpty {
                        Text("None").foregroundStyle(.tertiary)
                    } else {
                        ForEach(container.portMappings, id: \.self) { m in
                            Text(m).font(.system(.body, design: .monospaced))
                        }
                    }
                }

                if container.runState.isRunning {
                    Divider()
                    execSection
                }
            }
            .padding(16)
        }
    }

    private var actionButtons: some View {
        HStack {
            if container.runState.isRunning {
                Button { store.stopContainer(container.id) } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                Button { store.openShell(container.id) } label: {
                    Label("Shell", systemImage: "terminal")
                }.help("Open an interactive shell in Terminal.app")
            } else {
                Button { store.startContainer(container.id) } label: {
                    Label("Start", systemImage: "play.fill")
                }
            }
            Button { onLogs() } label: { Label("Logs", systemImage: "text.alignleft") }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var execSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run a command").font(.caption.bold()).foregroundStyle(.secondary)
            HStack {
                TextField("e.g. ls -la /", text: $execCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(runExec)
                Button("Run", action: runExec).disabled(execCommand.isEmpty)
            }
            if !execOutput.isEmpty {
                ScrollView {
                    Text(execOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func runExec() {
        let cmd = execCommand
        execOutput = "Running…"
        store.exec(container.id, command: cmd) { execOutput = $0.isEmpty ? "(no output)" : $0 }
    }

    private func field(_ label: String, _ value: String, mono: Bool = false, copyable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                if copyable {
                    Button { copy(value) } label: { Image(systemName: "doc.on.doc").font(.caption2) }
                        .buttonStyle(.borderless)
                }
            }
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared helpers

func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

struct EngineStopped: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ContentUnavailableView {
            Label("Engine stopped", systemImage: "bolt.slash")
        } description: {
            Text("The container services aren't running.")
        } actions: {
            Button { store.toggleSystem() } label: {
                Label("Start engine", systemImage: "play.fill")
            }.buttonStyle(.borderedProminent)
        }
    }
}
