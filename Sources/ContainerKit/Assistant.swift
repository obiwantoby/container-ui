import Foundation

/// Wraps the on-device Apple Foundation Models CLI (`fm`). Optional: if `fm`
/// isn't installed or the model isn't available, `isAvailable` is false and the
/// UI hides the assistant features.
public actor Assistant {
    public let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? Assistant.resolveBinary()
    }

    public static func resolveBinary() -> String {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["FM_BIN"],
           fm.isExecutableFile(atPath: env) { return env }
        for c in ["/usr/bin/fm", "/usr/local/bin/fm", "/opt/homebrew/bin/fm"]
        where fm.isExecutableFile(atPath: c) { return c }
        return "fm"
    }

    /// True when `fm available` reports the on-device model is ready.
    public func isAvailable() async -> Bool {
        guard let r = try? await run(["available"]) else { return false }
        return r.ok && r.stdout.lowercased().contains("available")
    }

    /// One-shot completion. Non-streaming so we can return the whole answer.
    public func respond(_ prompt: String, instructions: String? = nil) async -> String {
        var argv = ["respond", "--no-stream"]
        if let i = instructions { argv += ["-i", i] }
        argv.append(prompt)
        guard let r = try? await run(argv) else { return "The assistant is unavailable." }
        let text = (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No response." : text
    }

    // MARK: Task-specific prompts

    /// Plain-English explanation of a container's configuration.
    public func explain(containerJSON: String) async -> String {
        await respond(
            "Explain this container in 3-4 short sentences for a developer. "
            + "Mention its image, state, resources, and network. Be concise.\n\n\(containerJSON)",
            instructions: "You are a concise assistant that explains Linux containers running on macOS via Apple's `container` tool.")
    }

    /// Turn a natural-language request into `container run` flags.
    public func suggestRunFlags(_ request: String) async -> String {
        await respond(
            "Request: \(request)\n\nReturn ONLY the arguments that follow `container run` "
            + "(no code fences, no explanation). Example: -d --name web -p 8080:80 -m 512M nginx:latest",
            instructions: "You translate requests into Apple `container` CLI run flags. "
            + "Valid flags: -d, --name, -m (memory like 512M/2G), -c (cpus), -v host:container, "
            + "-p host:container, -e KEY=VALUE, followed by the image and optional command. "
            + "Output a single line of flags only.")
    }

    /// Summarize/diagnose a slice of container logs.
    public func diagnose(logs: String) async -> String {
        let slice = String(logs.suffix(4000))
        return await respond(
            "Here are recent container logs. Summarize what's happening and flag any errors "
            + "or likely problems in a few bullet points.\n\n\(slice)",
            instructions: "You are a concise assistant that diagnoses container logs.")
    }

    // MARK: Runner

    private func run(_ args: [String]) async throws -> RunResult {
        try await ContainerCLI.exec(binaryPath, args)
    }
}
