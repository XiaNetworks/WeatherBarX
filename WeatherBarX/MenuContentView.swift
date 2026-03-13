import AppKit
import SwiftUI

private enum MenuDetailColors {
    static let detail = Color(nsColor: NSColor.labelColor)
    static let meta = Color(nsColor: NSColor.secondaryLabelColor)
    static let iconColumnWidth: CGFloat = 20
}

private enum AddLocationMode: String, CaseIterable, Identifiable {
    case search
    case detect
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .detect:
            return "Detect"
        case .search:
            return "Search"
        }
    }
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
    @Binding var mode: AddLocationMode
    @Binding var locationName: String
    @Binding var latitudeText: String
    @Binding var longitudeText: String
    @Binding var searchQuery: String
    let detectedLocation: SavedLocation?
    let searchedLocation: SavedLocation?
    let isDetectingLocation: Bool
    let isSearchingLocation: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onManualSave: () -> Void
    let onDetect: () -> Void
    let onDetectedSave: () -> Void
    let onSearch: () -> Void
    let onSearchedSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Add Location Mode", selection: $mode) {
                ForEach(AddLocationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("add-location-mode-picker")

            Group {
                switch mode {
                case .manual:
                    manualContent
                case .detect:
                    detectContent
                case .search:
                    searchContent
                }
            }

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

                switch mode {
                case .manual:
                    Button("Save", action: onManualSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("add-location-save-button")
                case .detect:
                    Button("Use Detected", action: onDetectedSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(detectedLocation == nil || isDetectingLocation)
                        .accessibilityIdentifier("add-detected-location-button")
                case .search:
                    Button("Use Search Result", action: onSearchedSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(searchedLocation == nil || isSearchingLocation)
                        .accessibilityIdentifier("add-searched-location-button")
                }
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

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Location name", text: $locationName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-name-field")

            TextField("Latitude", text: $latitudeText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-latitude-field")

            TextField("Longitude", text: $longitudeText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-longitude-field")
        }
    }

    private var detectContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onDetect) {
                HStack(spacing: 8) {
                    if isDetectingLocation {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text(isDetectingLocation ? "Detecting..." : "Detect Current Location")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDetectingLocation)
            .accessibilityIdentifier("detect-current-location-button")

            Group {
                if let detectedLocation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detectedLocation.name)
                            .font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("detected-location-name")
                        Text(String(format: "%.4f, %.4f", detectedLocation.latitude, detectedLocation.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("detected-location-coordinates")
                    }
                } else {
                    Text("Use your Mac's current location to fill this slot automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("ZIP code or city name", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("search-location-query-field")

            Button(action: onSearch) {
                HStack(spacing: 8) {
                    if isSearchingLocation {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(isSearchingLocation ? "Searching..." : "Search")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSearchingLocation)
            .accessibilityIdentifier("search-location-button")

            Group {
                if let searchedLocation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(searchedLocation.name)
                            .font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("searched-location-name")
                        Text(String(format: "%.4f, %.4f", searchedLocation.latitude, searchedLocation.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("searched-location-coordinates")
                    }
                } else {
                    Text("Search by ZIP code or city name and save the best match into this slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let onRefresh: () -> Void
    let onQuit: () -> Void

    @State private var isShowingLocationOptions = false
    @State private var editingLocationSlotIndex: Int?
    @State private var addLocationMode: AddLocationMode = .search
    @State private var draftLocationName = ""
    @State private var draftLatitude = ""
    @State private var draftLongitude = ""
    @State private var searchQuery = ""
    @State private var detectedLocation: SavedLocation?
    @State private var searchedLocation: SavedLocation?
    @State private var isDetectingLocation = false
    @State private var isSearchingLocation = false
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
                                mode: $addLocationMode,
                                locationName: $draftLocationName,
                                latitudeText: $draftLatitude,
                                longitudeText: $draftLongitude,
                                searchQuery: $searchQuery,
                                detectedLocation: detectedLocation,
                                searchedLocation: searchedLocation,
                                isDetectingLocation: isDetectingLocation,
                                isSearchingLocation: isSearchingLocation,
                                errorMessage: addLocationError,
                                onCancel: dismissAddLocationEditor,
                                onManualSave: submitManualLocation,
                                onDetect: detectCurrentLocation,
                                onDetectedSave: submitDetectedLocation,
                                onSearch: searchForLocation,
                                onSearchedSave: submitSearchedLocation
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
            searchQuery = ""
            detectedLocation = nil
            searchedLocation = nil
            addLocationMode = .search
            addLocationError = nil
            isDetectingLocation = false
            isSearchingLocation = false
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
        searchQuery = ""
        detectedLocation = nil
        searchedLocation = nil
        isDetectingLocation = false
        isSearchingLocation = false
        addLocationMode = .search
    }

    private func submitManualLocation() {
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

    private func detectCurrentLocation() {
        guard !isDetectingLocation else {
            return
        }

        addLocationMode = .detect
        isDetectingLocation = true
        addLocationError = nil
        detectedLocation = nil

        Task {
            do {
                let location = try await viewModel.detectCurrentLocation()
                await MainActor.run {
                    detectedLocation = location
                    isDetectingLocation = false
                }
            } catch let error as LocationInputError {
                await MainActor.run {
                    addLocationError = error.errorDescription
                    isDetectingLocation = false
                }
            } catch {
                await MainActor.run {
                    addLocationError = "Unable to determine your current location."
                    isDetectingLocation = false
                }
            }
        }
    }

    private func searchForLocation() {
        guard !isSearchingLocation else {
            return
        }

        addLocationMode = .search
        isSearchingLocation = true
        addLocationError = nil
        searchedLocation = nil

        Task {
            do {
                let location = try await viewModel.searchLocation(query: searchQuery)
                await MainActor.run {
                    searchedLocation = location
                    isSearchingLocation = false
                }
            } catch let error as LocationInputError {
                await MainActor.run {
                    addLocationError = error.errorDescription
                    isSearchingLocation = false
                }
            } catch {
                await MainActor.run {
                    addLocationError = "Unable to find that location."
                    isSearchingLocation = false
                }
            }
        }
    }

    private func submitSearchedLocation() {
        guard let slotIndex = editingLocationSlotIndex, let searchedLocation else {
            return
        }

        do {
            try viewModel.addDetectedLocation(searchedLocation, at: slotIndex)
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        } catch let error as LocationInputError {
            addLocationError = error.errorDescription
        } catch {
            addLocationError = "Unable to save location."
        }
    }

    private func submitDetectedLocation() {
        guard let slotIndex = editingLocationSlotIndex, let detectedLocation else {
            return
        }

        do {
            try viewModel.addDetectedLocation(detectedLocation, at: slotIndex)
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        } catch let error as LocationInputError {
            addLocationError = error.errorDescription
        } catch {
            addLocationError = "Unable to save location."
        }
    }
}
