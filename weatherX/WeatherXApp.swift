import SwiftUI
import AppKit

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var locationName = "WeatherX"
    @Published var summary = "Placeholder weather"
    @Published var conditionSymbol = "☀️"
    @Published var temperatureText = "72°"

    var menuBarTitle: String {
        "\(conditionSymbol) \(temperatureText)"
    }
}

@main
struct WeatherXApp: App {
    @StateObject private var viewModel = WeatherViewModel()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.locationName)
                    .font(.headline)
                Text(viewModel.summary)
                    .foregroundStyle(.secondary)
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 200)
        } label: {
            Text(viewModel.menuBarTitle)
        }
    }
}
