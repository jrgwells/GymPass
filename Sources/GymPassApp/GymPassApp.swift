import SwiftUI
import AppKit
import GymPassShared

@main
struct GymPassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .task { model.start() }
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Refresh Access Code") {
                    Task { await model.refreshQR() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window must not quit GymPass; the menu bar item and
        // background service stay available.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var didAutoPresent = false

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: binding) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 460)
        }
        .navigationTitle("GymPass")
        .sheet(isPresented: Binding(get: { model.showingOnboarding }, set: { model.showingOnboarding = $0 })) {
            OnboardingView()
                .environment(model)
        }
        .overlay(alignment: .bottom) {
            if let banner = model.banner {
                InlineBanner(message: banner)
                    .padding(Spacing.l)
                    .frame(maxWidth: 520)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await model.refreshAll()
            if !didAutoPresent, model.needsOnboarding {
                didAutoPresent = true
                model.showingOnboarding = true
            }
        }
    }

    private var binding: Binding<SidebarDestination?> {
        Binding(
            get: { model.selectedDestination },
            set: { model.selectedDestination = $0 }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedDestination ?? .dashboard {
        case .dashboard: DashboardView()
        case .wallet: WalletView()
        case .activity: ActivityView()
        case .diagnostics: DiagnosticsView()
        }
    }
}
