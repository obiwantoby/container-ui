import SwiftUI
import ContainerKit

/// A form to launch a new container — the GUI equivalent of `container run`.
struct RunSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var image = "ubuntu"
    @State private var name = ""
    @State private var command = ""
    @State private var memory = ""
    @State private var cpus = ""
    @State private var volumesText = ""     // one "host:container[:ro]" per line
    @State private var portsText = ""       // one "host:container" per line
    @State private var envText = ""         // one "KEY=VALUE" per line
    @State private var aiPrompt = ""
    @State private var aiFlags = ""
    @State private var aiBusy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Run a container", systemImage: "plus.app")
                    .font(.headline)
                Spacer()
            }.padding()
            Divider()

            if store.aiAvailable { assistant }

            Form {
                Section("Image") {
                    TextField("Image", text: $image, prompt: Text("ubuntu:latest"))
                    TextField("Name", text: $name, prompt: Text("optional"))
                    TextField("Command", text: $command, prompt: Text("optional, e.g. sleep infinity"))
                }
                Section("Resources") {
                    TextField("Memory", text: $memory, prompt: Text("default — e.g. 2G"))
                    TextField("CPUs", text: $cpus, prompt: Text("default — e.g. 2"))
                }
                Section("Mounts (one per line: host:container[:ro])") {
                    TextEditor(text: $volumesText).frame(height: 54)
                        .font(.system(.body, design: .monospaced))
                }
                Section("Ports (one per line: host:container)") {
                    TextEditor(text: $portsText).frame(height: 44)
                        .font(.system(.body, design: .monospaced))
                }
                Section("Environment (one per line: KEY=VALUE)") {
                    TextEditor(text: $envText).frame(height: 44)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text(previewCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Run") { launch() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(image.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding()
        }
        .frame(width: 520, height: 640)
    }

    /// Natural-language → `container run` flags, on-device.
    private var assistant: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: aiBusy)
                TextField("Describe it, e.g. “nginx on port 8080 with 512MB”", text: $aiPrompt)
                    .textFieldStyle(.plain)
                    .onSubmit(suggest)
                Button("Suggest", action: suggest)
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(aiPrompt.isEmpty || aiBusy)
            }
            if !aiFlags.isEmpty {
                HStack {
                    Text("container run \(aiFlags)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).lineLimit(2)
                    Spacer()
                    Button("Run it") {
                        store.runRaw(flags: aiFlags.split(separator: " ").map(String.init))
                        dismiss()
                    }.buttonStyle(.glassProminent).controlSize(.small)
                }
                .padding(8)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
                .transition(.opacity)
            }
        }
        .padding(12)
        .animation(.smooth, value: aiFlags)
    }

    private func suggest() {
        guard !aiPrompt.isEmpty else { return }
        aiBusy = true; aiFlags = ""
        store.suggestRun(aiPrompt) { flags in
            // Keep a single clean line of flags.
            aiFlags = flags.split(whereSeparator: \.isNewline).first.map(String.init) ?? flags
            aiBusy = false
        }
    }

    private var spec: RunSpec {
        RunSpec(
            image: image.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            command: command.trimmingCharacters(in: .whitespaces),
            memory: memory.trimmingCharacters(in: .whitespaces),
            cpus: cpus.trimmingCharacters(in: .whitespaces),
            volumes: lines(volumesText),
            ports: lines(portsText),
            env: lines(envText),
            detach: true)
    }

    private var previewCommand: String {
        "container " + spec.arguments.joined(separator: " ")
    }

    private func lines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func launch() {
        store.run(spec)
        dismiss()
    }
}
