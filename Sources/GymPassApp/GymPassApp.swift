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
        .defaultSize(width: AppModel.initialWindowSize.width, height: AppModel.initialWindowSize.height)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Dashboard") { model.selectedDestination = .dashboard }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Wallet") { model.selectedDestination = .wallet }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Activity") { model.selectedDestination = .activity }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Diagnostics") { model.selectedDestination = .diagnostics }
                    .keyboardShortcut("4", modifiers: .command)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

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
                .frame(minWidth: 560, minHeight: 520)
        }
        .frame(minWidth: AppModel.minimumWindowSize.width, minHeight: AppModel.minimumWindowSize.height)
        .navigationTitle("GymPass")
        .sheet(isPresented: Binding(get: { model.showingOnboarding }, set: { model.showingOnboarding = $0 })) {
            OnboardingView()
                .environment(model)
        }
        .overlay(alignment: .bottom) {
            if let banner = model.banner {
                InlineBanner(message: banner, onDismiss: { model.dismissBanner() })
                    .padding(Spacing.l)
                    .frame(maxWidth: 520)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            if !model.hasAutoPresentedOnboarding, model.status == nil {
                await model.refreshAll()
            }
            if !model.hasAutoPresentedOnboarding, model.needsOnboarding {
                model.hasAutoPresentedOnboarding = true
                model.onboardingStartStep = 0
                model.showingOnboarding = true
            }
            if ProcessInfo.processInfo.environment["GYMPASS_OPEN_SETTINGS"] == "1" {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                openSettings()
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
