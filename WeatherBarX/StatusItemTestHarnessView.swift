import AppKit
import SwiftUI

private struct HarnessQuitButton: NSViewRepresentable {
    let onQuit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onQuit: onQuit)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Quit", target: context.coordinator, action: #selector(Coordinator.handleClick))
        button.identifier = NSUserInterfaceItemIdentifier("quit-button")
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.target = context.coordinator
        nsView.action = #selector(Coordinator.handleClick)
    }

    final class Coordinator: NSObject {
        let onQuit: () -> Void

        init(onQuit: @escaping () -> Void) {
            self.onQuit = onQuit
        }

        @objc func handleClick() {
            onQuit()
        }
    }
}

struct StatusItemTestHarnessView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                viewModel.toggleMenuPresentation()
            }, label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isLoading ? "arrow.triangle.2.circlepath" : viewModel.conditionIconName)
                    if !viewModel.isLoading {
                        Text(viewModel.temperatureText)
                    }
                }
            })
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("status-item-button")

            if viewModel.isMenuPresented {
                VStack(spacing: 12) {
                    MenuContentView(viewModel: viewModel, onRefresh: {
                        viewModel.refreshNow()
                    }, onQuit: onQuit)

                    HarnessQuitButton(onQuit: onQuit)
                        .frame(width: 80, height: 30)
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("status-item-popover")
            }

            Text("UI Test Harness")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 280, minHeight: 160)
        .padding(24)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
