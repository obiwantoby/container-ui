import SwiftUI
import ContainerKit

/// A form to launch a new container — the GUI equivalent of `container run`.
/// The assistant fills the fields; the app assembles the flags; a validator
/// gates the Run button. Bad syntax can't reach the binary.
struct RunSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /// When set, the sheet edits (recreates) this container instead of running
    /// a fresh one: fields are prefilled and Run replaces the container.
    var editing: ContainerInfo? = nil

    @State private var didPrefill = false
    @State private var image = "ubuntu"
    @State private var name = ""
    @State private var command = ""
    @State private var memory = ""
    @State private var cpus = ""
    @State private var detach = true
    @State private var volumesText = ""     // one "host:container[:ro]" per line
    @State private var portsText = ""       // one "host:container" per line
    @State private var envText = ""         // one "KEY=VALUE" per line
    @State private var aiPrompt = ""
    @State private var aiBusy = false
    @State private var aiNote = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(editing == nil ? "Run a container" : "Edit “\(editing!.id)” (recreate)",
                      systemImage: editing == nil ? "plus.app" : "pencil")
                    .font(.headline)
                Spacer()
            }.padding()
            Divider()

            if editing != nil {
                Label("Changes are applied by replacing the container. It restarts briefly.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.top, 6)
            }

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
                    Toggle("Detach (run in background)", isOn: $detach)
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

            footer
        }
        .frame(width: 520, height: 720)
        .onAppear(perform: prefill)
    }

    /// Seed the form from the container being edited (once), preserving its
    /// existing mounts, ports, env, and command so a recreate keeps them.
    private func prefill() {
        guard let c = editing, !didPrefill else { return }
        didPrefill = true
        image = c.image
        name = c.id
        cpus = "\(c.cpus)"
        memory = "\(c.memoryBytes / (1024 * 1024))M"
        command = c.commandSpec
        volumesText = c.mountSpecs.joined(separator: "\n")
        portsText = c.portMappings.map { $0.replacingOccurrences(of: "→", with: ":") }
                                   .joined(separator: "\n")
        envText = c.envSpecs.joined(separator: "\n")
        detach = true
    }

    // MARK: Assistant (natural language → fills the fields)

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: aiBusy)
                TextField("Describe it, e.g. “nginx on port 8080 with 512MB”", text: $aiPrompt)
                    .textFieldStyle(.plain)
                    .onSubmit(suggest)
                Button("Fill", action: suggest)
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(aiPrompt.isEmpty || aiBusy)
            }
            if !aiNote.isEmpty {
                Text(aiNote).font(.caption).foregroundStyle(.secondary).transition(.opacity)
            }
        }
        .padding(12)
        .animation(.smooth, value: aiNote)
    }

    private func suggest() {
        guard !aiPrompt.isEmpty else { return }
        aiBusy = true; aiNote = "Thinking…"
        store.suggestRunDraft(aiPrompt) { draft in
            aiBusy = false
            guard let d = draft else { aiNote = "Couldn't build a suggestion. Try rephrasing."; return }
            apply(d)
            aiNote = spec.isValid ? "Filled in — review and Run."
                                  : "Filled in — a couple values need a look."
        }
    }

    /// Overlay the model's draft onto the form (only where it proposed a value).
    private func apply(_ d: Assistant.RunSpecDraft) {
        if let v = d.image, !v.isEmpty { image = v }
        if let v = d.name { name = v }
        if let v = d.memory { memory = v }
        if let v = d.cpus { cpus = v }
        if let v = d.detach { detach = v }
        if let v = d.command { command = v }
        if let v = d.ports { portsText = v.joined(separator: "\n") }
        if let v = d.volumes { volumesText = v.joined(separator: "\n") }
        if let v = d.env { envText = v.joined(separator: "\n") }
    }

    // MARK: Footer with validation gate

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            if !spec.validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(spec.validationIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .transition(.opacity)
            }
            HStack {
                Text(previewCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(spec.isValid ? Color.secondary : Color.orange)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Run" : "Apply & recreate") { launch() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(!spec.isValid)
            }.padding([.horizontal, .bottom])
        }
        .animation(.smooth, value: spec.validationIssues)
    }

    // MARK: Spec + helpers

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
            detach: detach)
    }

    private var previewCommand: String { "container " + spec.arguments.joined(separator: " ") }

    private func lines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func launch() {
        guard spec.isValid else { return }
        if let old = editing { store.recreate(oldID: old.id, spec: spec) }
        else { store.run(spec) }
        dismiss()
    }
}
