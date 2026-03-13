import AppKit
import SwiftUI

private enum MenuDetailColors {
    static let detail = Color(nsColor: NSColor.labelColor)
    static let meta = Color(nsColor: NSColor.secondaryLabelColor)
    static let iconColumnWidth: CGFloat = 20
}

private struct DetailRow: View {
    let iconName: String
    let text: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .frame(width: MenuDetailColors.iconColumnWidth, alignment: .center)

            Text(text)

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct MenuContentView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.locationName)
                .font(.headline)
                .accessibilityIdentifier("location-name-text")

            Text(viewModel.summaryText)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("weather-summary-text")

            Group {
                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading")
                    }
                } else {
                    Label(viewModel.temperatureText, systemImage: viewModel.conditionIconName)
                }
            }
            .accessibilityIdentifier("temperature-label")

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                DetailRow(
                    iconName: "thermometer.high",
                    text: viewModel.highDetailText,
                    accessibilityIdentifier: "high-detail-text"
                )

                DetailRow(
                    iconName: "thermometer.low",
                    text: viewModel.lowDetailText,
                    accessibilityIdentifier: "low-detail-text"
                )
            }
            .font(.subheadline)
            .foregroundColor(MenuDetailColors.detail)

            VStack(alignment: .leading, spacing: 4) {
                DetailRow(
                    iconName: "sunrise",
                    text: viewModel.sunriseText,
                    accessibilityIdentifier: "sunrise-text"
                )

                DetailRow(
                    iconName: "sunset.fill",
                    text: viewModel.sunsetText,
                    accessibilityIdentifier: "sunset-text"
                )
            }
            .font(.subheadline)
            .foregroundColor(MenuDetailColors.detail)

            Divider()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    Text(viewModel.lastCheckText)
                        .font(.caption)
                        .foregroundColor(MenuDetailColors.meta)
                        .accessibilityIdentifier("last-check-text")

                    Spacer()

                    Button(action: onRefresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!viewModel.isRefreshButtonEnabled(at: context.date))
                    .help("Refresh weather")
                    .accessibilityIdentifier("refresh-button")
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button("Quit", action: onQuit)
                    .keyboardShortcut("q")
                    .accessibilityIdentifier("quit-button")

                Spacer()

                Button(viewModel.temperatureUnitButtonText, action: viewModel.toggleTemperatureUnit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("temperature-unit-button")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
