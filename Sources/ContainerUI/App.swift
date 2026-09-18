import SwiftUI
import ContainerKit

@main
struct ContainerUIApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Container", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
                .task { store.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        // Menu-bar companion: quick glance + quick actions.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .task { store.start() }
        } label: {
            // Icon reflects running count at a glance.
            Image(systemName: store.systemRunning
                  ? (store.runningCount > 0 ? "shippingbox.fill" : "shippingbox")
                  : "shippingbox")
            if store.runningCount > 0 { Text("\(store.runningCount)") }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Sidebar sections.
enum SidebarSection: String, CaseIterable, Identifiable {
    case containers, images, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .containers: return "Containers"
        case .images: return "Images"
        case .system: return "System"
        }
    }
    var icon: String {
        switch self {
        case .containers: return "shippingbox"
        case .images: return "square.stack.3d.up"
        case .system: return "gearshape.2"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var section: SidebarSection = .containers

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SidebarSection.allCases) { s in
                    Label(s.title, systemImage: s.icon).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(180)
            .safeAreaInset(edge: .bottom) { SystemBadge() }
        } detail: {
            switch section {
            case .containers: ContainersView()
            case .images: ImagesView()
            case .system: SystemView()
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.dismissError() } })) {
            Button("OK") { store.dismissError() }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

/// Small "engine running / stopped" badge pinned to the bottom of the sidebar.
struct SystemBadge: View {
    @EnvironmentObject var store: Store
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(store.systemRunning ? .green : .secondary)
                .frame(width: 8, height: 8)
            Text(store.systemRunning ? "Engine running" : "Engine stopped")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if store.busy { ProgressView().controlSize(.small) }
        }
        .padding(10)
        .background(.thinMaterial)
    }
}
