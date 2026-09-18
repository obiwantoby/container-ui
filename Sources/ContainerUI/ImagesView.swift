import SwiftUI
import ContainerKit

struct ImagesView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""

    var filtered: [ImageInfo] {
        query.isEmpty ? store.images
            : store.images.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if !store.systemRunning {
                EngineStopped()
            } else if store.images.isEmpty {
                ContentUnavailableView("No images", systemImage: "square.stack.3d.up",
                    description: Text("Pull one by running a container from it."))
            } else {
                Table(filtered) {
                    TableColumn("Name") { img in
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(.tint)
                            Text(img.shortName).fontWeight(.medium)
                        }
                    }
                    TableColumn("Repository") { Text($0.name).foregroundStyle(.secondary) }
                    TableColumn("Digest") {
                        Text($0.shortDigest).font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Size") { Text(Format.bytes($0.size)).monospacedDigit() }
                }
            }
        }
        .navigationTitle("Images")
        .searchable(text: $query, prompt: "Filter images")
        .toolbar {
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }.help("Refresh")
        }
    }
}

struct SystemView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Form {
            LabeledContent("Status") {
                StatusPill(state: store.systemRunning ? .running : .stopped)
            }
            LabeledContent("Running containers", value: "\(store.runningCount)")
            LabeledContent("Total containers", value: "\(store.containers.count)")
            LabeledContent("Images", value: "\(store.images.count)")
            LabeledContent("CLI binary") {
                Text(store.binaryPath).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section {
                Button(role: store.systemRunning ? .destructive : nil) {
                    store.toggleSystem()
                } label: {
                    Label(store.systemRunning ? "Stop engine" : "Start engine",
                          systemImage: store.systemRunning ? "stop.fill" : "play.fill")
                }
            } footer: {
                Text("Services do not start automatically at login — this is manual by design.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System")
    }
}
