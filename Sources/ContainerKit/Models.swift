import Foundation

// MARK: - Container

/// A single container as reported by `container ls -a --format json`.
/// Decoding is intentionally lenient: only the fields the UI/TUI need are
/// modeled, and everything is optional-tolerant so a schema tweak upstream
/// degrades gracefully instead of crashing.
public struct ContainerInfo: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let configuration: Configuration
    public let status: Status

    public struct Configuration: Codable, Hashable, Sendable {
        public let image: Image
        public let resources: Resources

        public struct Image: Codable, Hashable, Sendable {
            public let reference: String
        }
        public struct Resources: Codable, Hashable, Sendable {
            public let cpus: Int
            public let memoryInBytes: Int64
        }
    }

    public struct Status: Codable, Hashable, Sendable {
        public let state: String
        public let startedDate: String?
        public let networks: [Network]?

        public struct Network: Codable, Hashable, Sendable {
            public let ipv4Address: String?
            public let hostname: String?
        }
    }

    // Convenience accessors ---------------------------------------------------

    public var image: String { configuration.image.reference }
    public var cpus: Int { configuration.resources.cpus }
    public var memoryBytes: Int64 { configuration.resources.memoryInBytes }
    public var ipv4: String? { status.networks?.first?.ipv4Address }

    public var runState: RunState { RunState(raw: status.state) }

    public var shortImage: String {
        // docker.io/library/ubuntu:latest -> ubuntu:latest
        let ref = image
        if let slash = ref.lastIndex(of: "/") {
            return String(ref[ref.index(after: slash)...])
        }
        return ref
    }
}

public enum RunState: String, Sendable {
    case running, stopped, created, exited, unknown

    init(raw: String) {
        self = RunState(rawValue: raw.lowercased()) ?? .unknown
    }

    public var isRunning: Bool { self == .running }
    public var label: String { rawValue.capitalized }
}

// MARK: - Image

/// A single image from `container image ls --format json`.
public struct ImageInfo: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let configuration: Configuration

    public struct Configuration: Codable, Hashable, Sendable {
        public let name: String
        public let descriptor: Descriptor

        public struct Descriptor: Codable, Hashable, Sendable {
            public let digest: String
            public let size: Int64
        }
    }

    public var name: String { configuration.name }
    public var size: Int64 { configuration.descriptor.size }
    public var digest: String { configuration.descriptor.digest }

    public var shortName: String {
        if let slash = name.lastIndex(of: "/") {
            return String(name[name.index(after: slash)...])
        }
        return name
    }
    public var shortDigest: String {
        let hex = digest.replacingOccurrences(of: "sha256:", with: "")
        return String(hex.prefix(12))
    }
}

// MARK: - Formatting helpers

public enum Format {
    public static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f.string(fromByteCount: n)
    }
}
