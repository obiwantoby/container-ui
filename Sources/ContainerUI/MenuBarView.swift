import SwiftUI
import ContainerKit

/// Compact popover shown from the menu-bar icon.
struct MenuBarView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !store.systemRunning {
                stoppedState
            } else if store.containers.isEmpty {
                Text("No containers")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.containers) { c in row(c) }
                    }
                }
                .frame(maxHeight: 300)
            }
            Divider()
            footer
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Circle().fill(store.systemRunning ? .green : .secondary).frame(width: 8, height: 8)
            Text("Container").font(.headline)
            Spacer()
            Text(store.systemRunning ? "\(store.runningCount) running" : "stopped")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(10)
    }

    private func row(_ c: ContainerInfo) -> some View {
        HStack(spacing: 8) {
            Circle().fill(c.runState.color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.id).font(.system(.body, design: .default)).lineLimit(1)
                Text(c.shortImage).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if c.runState.isRunning {
                button("stop.fill", .orange) { store.stopContainer(c.id) }
            } else {
                button("play.fill", .green) { store.startContainer(c.id) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var stoppedState: some View {
        VStack(spacing: 8) {
            Text("Engine stopped").foregroundStyle(.secondary)
            Button { store.toggleSystem() } label: {
                Label("Start engine", systemImage: "play.fill")
            }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Button { openWindow(id: "main") } label: {
                Label("Open window", systemImage: "macwindow")
            }.buttonStyle(.borderless)
            Spacer()
            Button { store.toggleSystem() } label: {
                Text(store.systemRunning ? "Stop engine" : "Start engine")
            }.buttonStyle(.borderless)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }.buttonStyle(.borderless).help("Quit")
        }.padding(8)
    }

    private func button(_ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(color)
        }.buttonStyle(.borderless)
    }
}
