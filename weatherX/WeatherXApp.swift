import SwiftUI
import AppKit

@main
struct WeatherXApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("WeatherX")
                    .font(.headline)
                Text("Placeholder weather")
                    .foregroundStyle(.secondary)
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 200)
        } label: {
            Text("☀️ 72°")
        }
    }
}
