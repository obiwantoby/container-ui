import SwiftUI
import ContainerKit

/// Visual language for the app: colors, status pills, and small reusable bits.
enum Theme {
    static let accent = Color.accentColor
    static let cardBG = Color(nsColor: .controlBackgroundColor)
    static let subtle = Color.secondary.opacity(0.7)
}

extension RunState {
    var color: Color {
        switch self {
        case .running: return .green
        case .stopped, .exited: return .orange
        case .created: return .blue
        case .unknown: return .gray
        }
    }
}

/// A small colored dot + label used throughout the UI. Calm and static.
struct StatusPill: View {
    let state: RunState
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.color)
                .frame(width: 7, height: 7)
            Text(state.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// A GPU-rendered animated mesh gradient ("aurora"). The interior control
/// points drift over time; the palette leans toward `tint`. This is the Metal
/// bit — MeshGradient composites on the GPU.
struct AuroraBackground: View {
    var tint: Color = .accentColor
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Slow, small drift so it breathes rather than lurches.
            let a = Float(sin(t * 0.18)) * 0.035
            let b = Float(cos(t * 0.14)) * 0.035
            let c = Float(sin(t * 0.22 + 1)) * 0.035
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5 + a, 0.0], [1.0, 0.0],
                    [0.0, 0.5 + b], [0.5 + c, 0.5 - a], [1.0, 0.5 - b],
                    [0.0, 1.0], [0.5 - c, 1.0], [1.0, 1.0],
                ],
                colors: [
                    tint.opacity(0.35), tint.opacity(0.20), .purple.opacity(0.25),
                    tint.opacity(0.22), tint.opacity(0.10), tint.opacity(0.30),
                    .blue.opacity(0.25), tint.opacity(0.18), tint.opacity(0.28),
                ]
            )
        }
    }
}

/// A labeled metric chip (CPU / RAM / IP), rendered as Liquid Glass.
struct MetricChip: View {
    let icon: String
    let value: String
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(value).font(.caption.monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .foregroundStyle(.secondary)
        .glassEffect(.regular, in: .capsule)
    }
}
