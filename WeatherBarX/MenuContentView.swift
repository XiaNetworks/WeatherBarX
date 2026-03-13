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

private struct AddLocationEditorView: View {
    @Binding var locationName: String
    @Binding var latitudeText: String
    @Binding var longitudeText: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Location")
                .font(.subheadline.weight(.semibold))

            TextField("Location name", text: $locationName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-name-field")

            TextField("Latitude", text: $latitudeText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-latitude-field")

            TextField("Longitude", text: $longitudeText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-longitude-field")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("add-location-error-text")
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .accessibilityIdentifier("add-location-cancel-button")

                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("add-location-save-button")
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

struct MenuContentView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let onRefresh: () -> Void
    let onQuit: () -> Void

    @State private var isShowingLocationOptions = false
    @State private var editingLocationSlotIndex: Int?
    @State private var draftLocationName = ""
    @State private var draftLatitude = ""
    @State private var draftLongitude = ""
    @State private var addLocationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: toggleLocationOptions) {
                    HStack(spacing: 8) {
                        Text(viewModel.locationName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: isShowingLocationOptions ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )
                .accessibilityIdentifier("location-picker-button")

                if isShowingLocationOptions {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.alternateLocationSlots) { slot in
                            HStack(spacing: 8) {
                                Button(action: {
                                    handleLocationSlotTap(slot)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: slot.isEmpty ? "plus.circle" : "mappin.and.ellipse")
                                            .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                                        Text(slot.title)
                                            .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("location-slot-\(slot.index)")

                                if !slot.isEmpty && viewModel.canDeleteLocation(at: slot.index) {
                                    Button(role: .destructive, action: {
                                        viewModel.deleteLocation(at: slot.index)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete location")
                                    .accessibilityIdentifier("delete-location-slot-\(slot.index)")
                                }
                            }
                        }

                        if editingLocationSlotIndex != nil {
                            AddLocationEditorView(
                                locationName: $draftLocationName,
                                latitudeText: $draftLatitude,
                                longitudeText: $draftLongitude,
                                errorMessage: addLocationError,
                                onCancel: dismissAddLocationEditor,
                                onSave: submitLocation
                            )
                            .accessibilityIdentifier("add-location-editor")
                        }
                    }
                    .padding(.leading, 2)
                }
            }

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

                Button(action: viewModel.toggleLaunchAtLogin) {
                    Label(viewModel.launchAtLoginButtonText, systemImage: viewModel.isLaunchAtLoginEnabled ? "checkmark.circle.fill" : "circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("launch-at-login-button")

                Button(viewModel.temperatureUnitButtonText, action: viewModel.toggleTemperatureUnit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("temperature-unit-button")
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func toggleLocationOptions() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isShowingLocationOptions.toggle()
        }

        if !isShowingLocationOptions {
            dismissAddLocationEditor()
        }
    }

    private func handleLocationSlotTap(_ slot: LocationSlot) {
        if slot.isEmpty {
            draftLocationName = ""
            draftLatitude = ""
            draftLongitude = ""
            addLocationError = nil
            editingLocationSlotIndex = slot.index
        } else {
            viewModel.selectLocation(at: slot.index)
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        }
    }

    private func dismissAddLocationEditor() {
        editingLocationSlotIndex = nil
        addLocationError = nil
    }

    private func submitLocation() {
        guard let slotIndex = editingLocationSlotIndex else {
            return
        }

        do {
            try viewModel.addLocation(
                at: slotIndex,
                name: draftLocationName,
                latitudeText: draftLatitude,
                longitudeText: draftLongitude
            )
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        } catch let error as LocationInputError {
            addLocationError = error.errorDescription
        } catch {
            addLocationError = "Unable to save location."
        }
    }
}
