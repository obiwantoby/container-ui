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

    /// A structured draft of a container to run. FM fills this against a JSON
    /// schema; the app assembles the actual flags, so the syntax can't be wrong.
    public struct RunSpecDraft: Codable, Sendable {
        public var image: String?
        public var name: String?
        public var memory: String?
        public var cpus: String?
        public var detach: Bool?
        public var ports: [String]?
        public var volumes: [String]?
        public var env: [String]?
        public var command: String?
    }

    /// JSON schema (fm-native) describing RunSpecDraft.
    private static let runSpecSchema = """
    {"type":"object","required":["image"],"additionalProperties":false,"title":"RunSpec",
     "properties":{
      "image":{"type":"string","description":"container image like nginx:latest"},
      "name":{"type":"string"},
      "memory":{"type":"string","description":"memory like 512M or 2G"},
      "cpus":{"type":"string","description":"number of cpus"},
      "detach":{"type":"boolean"},
      "ports":{"type":"array","items":{"type":"string"},"description":"host:container"},
      "volumes":{"type":"array","items":{"type":"string"},"description":"hostPath:containerPath"},
      "env":{"type":"array","items":{"type":"string"},"description":"KEY=VALUE"},
      "command":{"type":"string"}}}
    """

    /// Turn a natural-language request into a structured, validated draft,
    /// grounded in the binary's own `run --help` so it uses real options.
    public func suggestRunDraft(_ request: String, help: String) async -> RunSpecDraft? {
        // fm needs the schema as a file path.
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("container-ui-runspec-\(UUID().uuidString).json")
        guard (try? Self.runSpecSchema.write(to: file, atomically: true, encoding: .utf8)) != nil
        else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }

        let grounding = """
        You configure a container to run with Apple's `container` tool. Map the user's request
        to the fields. Only use values the request implies. Memory uses suffixes K/M/G/T/P.
        Ports and volumes are "host:container". Env is "KEY=VALUE". Prefer detach=true for services.
        The binary's own reference for `container run` follows; respect it:
        \(String(help.prefix(3000)))
        """
        guard let r = try? await run(["respond", "--no-stream", "--schema", file.path,
                                      "-i", grounding, request]),
              r.ok else { return nil }
        let json = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Model may wrap JSON in prose; grab the outermost object.
        guard let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}") else { return nil }
        let obj = String(json[start...end])
        return try? JSONDecoder().decode(RunSpecDraft.self, from: Data(obj.utf8))
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
