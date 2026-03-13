import AppKit
import SwiftUI

private enum MenuDetailColors {
    static let detail = Color(nsColor: NSColor.labelColor)
    static let meta = Color(nsColor: NSColor.secondaryLabelColor)
}

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

            Text(viewModel.dailyRangeText)
                .font(.subheadline)
                .foregroundColor(MenuDetailColors.detail)
                .accessibilityIdentifier("daily-range-text")

            HStack(spacing: 12) {
                Text(viewModel.sunriseText)
                    .accessibilityIdentifier("sunrise-text")

                Text(viewModel.sunsetText)
                    .accessibilityIdentifier("sunset-text")
            }
            .font(.caption)
            .foregroundColor(MenuDetailColors.detail)

            Text(viewModel.lastCheckText)
                .font(.caption)
                .foregroundColor(MenuDetailColors.meta)
                .accessibilityIdentifier("last-check-text")

            Divider()

            Button("Quit", action: onQuit)
                .keyboardShortcut("q")
                .accessibilityIdentifier("quit-button")
        }
        .padding()
        .frame(width: 260)
    }
}
