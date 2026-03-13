import AppKit
import SwiftUI

private enum AppLaunchMode {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var harnessWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppLaunchMode.isUITesting else {
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)

        let defaults = UserDefaults(suiteName: "WeatherBarXUITesting")!
        defaults.set(true, forKey: WeatherSettings.usesPlaceholderWeatherKey)

        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            refreshOnInit: false
        )
        let rootView = StatusItemTestHarnessView(viewModel: viewModel) {
            NSApplication.shared.terminate(nil)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "WeatherBarX Test Harness"
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        harnessWindow = window
    }
}

@main
struct WeatherBarXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = WeatherViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel, onQuit: quit)
        } label: {
            Text(viewModel.menuBarTitle)
                .accessibilityIdentifier("status-item-button")
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
