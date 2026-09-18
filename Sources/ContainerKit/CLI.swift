import Foundation

/// Errors surfaced by the CLI wrapper.
public struct CLIError: Error, LocalizedError, Sendable {
    public let command: String
    public let exitCode: Int32
    public let stderr: String
    public var errorDescription: String? {
        let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "`\(command)` failed (exit \(exitCode))" + (msg.isEmpty ? "" : ":\n\(msg)")
    }
}

/// Result of a completed process run.
public struct RunResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var ok: Bool { exitCode == 0 }
}

/// Options for launching a new container (mirrors the flags of `container run`).
public struct RunSpec: Sendable {
    public var image: String
    public var name: String
    public var command: String        // optional entrypoint override, space-split
    public var memory: String         // e.g. "2G"; empty = default
    public var cpus: String           // e.g. "2"; empty = default
    public var volumes: [String]      // "host:container[:ro]"
    public var ports: [String]        // "host:container"
    public var env: [String]          // "KEY=VALUE"
    public var detach: Bool

    public init(image: String, name: String = "", command: String = "",
                memory: String = "", cpus: String = "", volumes: [String] = [],
                ports: [String] = [], env: [String] = [], detach: Bool = true) {
        self.image = image; self.name = name; self.command = command
        self.memory = memory; self.cpus = cpus; self.volumes = volumes
        self.ports = ports; self.env = env; self.detach = detach
    }

    /// Value-level validation so a command is known-good before save/run.
    /// Flag *syntax* is guaranteed because `arguments` assembles it; this
    /// checks the values the user (or the assistant) supplied.
    public var validationIssues: [String] {
        var issues: [String] = []
        if image.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Image is required.")
        }
        if !memory.isEmpty, memory.range(of: #"^\d+(\.\d+)?\s*[KMGTPkmgtp]?[Bb]?$"#, options: .regularExpression) == nil {
            issues.append("Memory “\(memory)” isn't valid (try 512M or 2G).")
        }
        if !cpus.isEmpty, Int(cpus) == nil || (Int(cpus) ?? 0) <= 0 {
            issues.append("CPUs “\(cpus)” must be a positive whole number.")
        }
        for p in ports where !p.isEmpty {
            let parts = p.split(separator: "/").first.map(String.init) ?? p
            let hc = parts.split(separator: ":")
            let valid = hc.count == 2 && Int(hc[0]) != nil && Int(hc[1]) != nil
            if !valid { issues.append("Port “\(p)” must be host:container (e.g. 8080:80).") }
        }
        for v in volumes where !v.isEmpty && !v.contains(":") {
            issues.append("Mount “\(v)” must be host:container.")
        }
        for e in env where !e.isEmpty && !e.contains("=") {
            issues.append("Env “\(e)” must be KEY=VALUE.")
        }
        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }

    public var arguments: [String] {
        var a = ["run"]
        if detach { a.append("-d") }
        if !name.isEmpty { a += ["--name", name] }
        if !memory.isEmpty { a += ["-m", memory] }
        if !cpus.isEmpty { a += ["-c", cpus] }
        for v in volumes where !v.isEmpty { a += ["-v", v] }
        for p in ports where !p.isEmpty { a += ["-p", p] }
        for e in env where !e.isEmpty { a += ["-e", e] }
        a.append(image)
        if !command.isEmpty { a += command.split(separator: " ").map(String.init) }
        return a
    }
}

/// Thin async wrapper around the `container` CLI. All calls are off the main
/// actor; JSON parsing produces the typed models in `Models.swift`.
public actor ContainerCLI {
    public nonisolated let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? ContainerCLI.resolveBinary()
    }

    /// Locate the `container` binary: env override → cloned repo → /usr/local → PATH.
    public static func resolveBinary() -> String {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["CONTAINER_BIN"],
           fm.isExecutableFile(atPath: env) { return env }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/container/bin/container",
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) { return c }
        return "container" // fall back to PATH lookup at exec time
    }

    // MARK: Core runner

    @discardableResult
    public func run(_ args: [String]) async throws -> RunResult {
        try await Self.exec(binaryPath, args)
    }

    /// Run and throw a rich error unless the process exits 0.
    @discardableResult
    public func runChecked(_ args: [String]) async throws -> String {
        let r = try await run(args)
        guard r.ok else {
            throw CLIError(command: "container " + args.joined(separator: " "),
                           exitCode: r.exitCode, stderr: r.stderr.isEmpty ? r.stdout : r.stderr)
        }
        return r.stdout
    }

    // MARK: Typed queries

    public func listContainers(all: Bool = true) async throws -> [ContainerInfo] {
        var argv = ["ls"]
        if all { argv.append("-a") }
        argv += ["--format", "json"]
        let out = try await runChecked(argv)
        return try decode([ContainerInfo].self, from: out)
    }

    public func listImages() async throws -> [ImageInfo] {
        let out = try await runChecked(["image", "ls", "--format", "json"])
        return try decode([ImageInfo].self, from: out)
    }

    /// Raw `--help` text for a subcommand (e.g. ["run"]). Used to ground the
    /// assistant in the binary's actual flags, so it stays correct as the CLI
    /// evolves.
    public func help(_ subcommand: [String]) async -> String {
        (try? await run(subcommand + ["--help"]))?.stdout ?? ""
    }

    public func systemStatus() async -> Bool {
        // Returns true if services are running.
        guard let r = try? await run(["system", "status"]) else { return false }
        return r.ok && r.stdout.lowercased().contains("running")
    }

    // MARK: Lifecycle

    public func start(_ id: String) async throws { try await runChecked(["start", id]) }
    public func stop(_ id: String) async throws { try await runChecked(["stop", id]) }
    public func remove(_ id: String, force: Bool = false) async throws {
        try await runChecked(force ? ["rm", "-f", id] : ["rm", id])
    }
    public func systemStart() async throws { try await runChecked(["system", "start"]) }
    public func systemStop() async throws { try await runChecked(["system", "stop"]) }

    @discardableResult
    public func runContainer(_ spec: RunSpec) async throws -> String {
        try await runChecked(spec.arguments)
    }

    /// Run a one-shot command inside a running container and return its output.
    public func exec(_ id: String, command: String) async throws -> String {
        var argv = ["exec", id]
        argv += command.split(separator: " ").map(String.init)
        let r = try await run(argv)
        return r.stdout + (r.stderr.isEmpty ? "" : r.stderr)
    }

    /// Command a user can run in a real terminal to get an interactive shell.
    public nonisolated func interactiveShellCommand(_ id: String, shell: String = "bash") -> String {
        "\(binaryPath) exec -it \(id) \(shell)"
    }

    // MARK: Streaming logs

    /// Stream a container's logs. Returns the async line stream and a handle to
    /// terminate the underlying process.
    public func logStream(_ id: String, follow: Bool = true, tail: Int = 200)
        -> (lines: AsyncStream<String>, cancel: @Sendable () -> Void)
    {
        var argv = ["logs", "-n", String(tail)]
        if follow { argv.append("-f") }
        argv.append(id)
        return Self.stream(binaryPath, argv)
    }

    // MARK: - Private plumbing

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Run a process to completion, capturing stdout/stderr.
    static func exec(_ path: String, _ args: [String]) async throws -> RunResult {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            configure(p, path: path, args: args)
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do {
                try p.run()
            } catch {
                cont.resume(throwing: error); return
            }
            let o = out.fileHandleForReading.readDataToEndOfFile()
            let e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            cont.resume(returning: RunResult(
                stdout: String(decoding: o, as: UTF8.self),
                stderr: String(decoding: e, as: UTF8.self),
                exitCode: p.terminationStatus))
        }
    }

    /// Holds the running process + line buffer. The readability/termination
    /// handlers fire serially on the same queue, so unchecked-Sendable is safe.
    private final class StreamProc: @unchecked Sendable {
        let process = Process()
        var buffer = Data()
        func terminate() { if process.isRunning { process.terminate() } }
    }

    /// Launch a long-running process and yield stdout line-by-line.
    static func stream(_ path: String, _ args: [String])
        -> (lines: AsyncStream<String>, cancel: @Sendable () -> Void)
    {
        let holder = StreamProc()
        let p = holder.process
        configure(p, path: path, args: args)
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out

        let stream = AsyncStream<String> { continuation in
            let handle = out.fileHandleForReading
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty { return }
                holder.buffer.append(chunk)
                while let nl = holder.buffer.firstIndex(of: 0x0A) {
                    let line = holder.buffer.subdata(in: holder.buffer.startIndex..<nl)
                    continuation.yield(String(decoding: line, as: UTF8.self))
                    holder.buffer.removeSubrange(holder.buffer.startIndex...nl)
                }
            }
            p.terminationHandler = { _ in
                if !holder.buffer.isEmpty {
                    continuation.yield(String(decoding: holder.buffer, as: UTF8.self))
                }
                handle.readabilityHandler = nil
                continuation.finish()
            }
            do { try p.run() } catch { continuation.finish() }
        }

        let cancel: @Sendable () -> Void = { holder.terminate() }
        return (stream, cancel)
    }

    private static func configure(_ p: Process, path: String, args: [String]) {
        if path.contains("/") {
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
        } else {
            // Bare name (e.g. "container"/"fm"): resolve via PATH.
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = [path] + args
        }
    }
}
