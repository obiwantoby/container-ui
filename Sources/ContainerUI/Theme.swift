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

/// A small colored dot + label used throughout the UI.
struct StatusPill: View {
    let state: RunState
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
                .shadow(color: state.color.opacity(state.isRunning ? 0.8 : 0), radius: 4)
            Text(state.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// A labeled metric chip (CPU / RAM / IP).
struct MetricChip: View {
    let icon: String
    let value: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(value).font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.cardBG, in: Capsule())
        .foregroundStyle(.secondary)
    }
}
