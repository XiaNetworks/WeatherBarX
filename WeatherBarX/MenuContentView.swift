import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.locationName)
                .font(.headline)
                .accessibilityIdentifier("location-name-text")

            Text(viewModel.summaryText)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("weather-summary-text")

            Label(viewModel.temperatureText, systemImage: viewModel.conditionIconName)
                .accessibilityIdentifier("temperature-label")

            Text(viewModel.lastCheckText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("last-check-text")

            Divider()

            Button("Quit", action: onQuit)
                .keyboardShortcut("q")
                .accessibilityIdentifier("quit-button")
        }
        .padding()
        .frame(width: 220)
    }
}
