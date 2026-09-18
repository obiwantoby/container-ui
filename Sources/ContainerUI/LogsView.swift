import SwiftUI
import ContainerKit

struct LogsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let container: ContainerInfo

    @State private var lines: [String] = []
    @State private var follow = true
    @State private var cancel: (@Sendable () -> Void)?
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
        }
        .frame(minWidth: 640, minHeight: 420)
        .task { await beginStream() }
        .onDisappear { cancel?(); streamTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "text.alignleft")
            Text(container.id).font(.headline)
            StatusPill(state: container.runState)
            Spacer()
            Toggle("Follow", isOn: $follow).toggleStyle(.switch).controlSize(.small)
            Button("Clear") { lines.removeAll() }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) {
                if follow { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }

    private func beginStream() async {
        let (stream, cancelFn) = await store.cli.logStream(container.id, follow: true)
        cancel = cancelFn
        for await line in stream {
            lines.append(line)
            if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
        }
    }
}
