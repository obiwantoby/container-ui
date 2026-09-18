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
                ScrollView {
                    GlassEffectContainer(spacing: 8) {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { img in ImageRow(image: img) }
                        }
                    }
                    .padding(12)
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

struct ImageRow: View {
    let image: ImageInfo
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title2).foregroundStyle(Color.accentColor.gradient).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(image.shortName).font(.headline)
                Text(image.name).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            MetricChip(icon: "number", value: image.shortDigest)
            MetricChip(icon: "internaldrive", value: Format.bytes(image.size))
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .contextMenu {
            Button("Copy name") { copy(image.name) }
            Button("Copy digest") { copy(image.digest) }
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
