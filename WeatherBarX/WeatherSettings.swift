import Foundation

enum TemperatureUnit: String, Equatable {
    case fahrenheit
    case celsius

    var displayText: String {
        switch self {
        case .fahrenheit:
            return "°F"
        case .celsius:
            return "°C"
        }
    }

    mutating func toggle() {
        self = self == .fahrenheit ? .celsius : .fahrenheit
    }
}

struct SavedLocation: Codable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
}

struct WeatherSettings: Equatable {
    static let locationNameKey = "locationName"
    static let latitudeKey = "latitude"
    static let longitudeKey = "longitude"
    static let usesPlaceholderWeatherKey = "usesPlaceholderWeather"
    static let temperatureUnitKey = "temperatureUnit"
    static let savedLocationsKey = "savedLocations"
    static let selectedLocationIndexKey = "selectedLocationIndex"
    static let cachedWeatherByLocationKey = "cachedWeatherByLocation"

    static let defaultLocationName = "Washington, DC"
    static let defaultLatitude = 38.9072
    static let defaultLongitude = -77.0369
    static let defaultUsesPlaceholderWeather = false
    static let defaultTemperatureUnit: TemperatureUnit = .fahrenheit
    static let defaultPrimaryLocation = SavedLocation(
        name: defaultLocationName,
        latitude: defaultLatitude,
        longitude: defaultLongitude
    )
    static let defaultNorthPoleLocation = SavedLocation(
        name: "North Pole",
        latitude: 90,
        longitude: 0
    )
    static let defaultSouthPoleLocation = SavedLocation(
        name: "South Pole",
        latitude: -90,
        longitude: 0
    )
    static let defaultSavedLocations: [SavedLocation?] = [
        defaultPrimaryLocation,
        defaultNorthPoleLocation,
        defaultSouthPoleLocation,
    ]
    static let defaultSelectedLocationIndex = 0

    let locationName: String
    let latitude: Double
    let longitude: Double
    let usesPlaceholderWeather: Bool
    let temperatureUnit: TemperatureUnit
    let savedLocations: [SavedLocation?]
    let selectedLocationIndex: Int

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Self.locationNameKey: Self.defaultLocationName,
            Self.latitudeKey: Self.defaultLatitude,
            Self.longitudeKey: Self.defaultLongitude,
            Self.usesPlaceholderWeatherKey: Self.defaultUsesPlaceholderWeather,
            Self.temperatureUnitKey: Self.defaultTemperatureUnit.rawValue,
            Self.selectedLocationIndexKey: Self.defaultSelectedLocationIndex,
        ])

        usesPlaceholderWeather = defaults.object(forKey: Self.usesPlaceholderWeatherKey) as? Bool ?? Self.defaultUsesPlaceholderWeather
        let rawTemperatureUnit = defaults.string(forKey: Self.temperatureUnitKey) ?? Self.defaultTemperatureUnit.rawValue
        temperatureUnit = TemperatureUnit(rawValue: rawTemperatureUnit) ?? Self.defaultTemperatureUnit

        let decodedLocations = Self.decodeSavedLocations(from: defaults.data(forKey: Self.savedLocationsKey))
            ?? Self.legacySavedLocations(from: defaults)
        savedLocations = Self.normalizedLocations(from: decodedLocations)

        let storedIndex = defaults.object(forKey: Self.selectedLocationIndexKey) as? Int ?? Self.defaultSelectedLocationIndex
        selectedLocationIndex = Self.normalizedSelectedLocationIndex(storedIndex, savedLocations: savedLocations)

        let activeLocation = savedLocations[selectedLocationIndex] ?? Self.defaultPrimaryLocation
        locationName = activeLocation.name
        latitude = activeLocation.latitude
        longitude = activeLocation.longitude
    }

    private static func decodeSavedLocations(from data: Data?) -> [SavedLocation?]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([SavedLocation?].self, from: data)
    }

    private static func legacySavedLocations(from defaults: UserDefaults) -> [SavedLocation?] {
        let name = defaults.string(forKey: Self.locationNameKey) ?? Self.defaultLocationName
        let latitude = defaults.object(forKey: Self.latitudeKey) as? Double ?? Self.defaultLatitude
        let longitude = defaults.object(forKey: Self.longitudeKey) as? Double ?? Self.defaultLongitude

        return [SavedLocation(name: name, latitude: latitude, longitude: longitude), defaultNorthPoleLocation, defaultSouthPoleLocation]
    }

    private static func normalizedLocations(from savedLocations: [SavedLocation?]) -> [SavedLocation?] {
        var normalized = Array(savedLocations.prefix(3))
        while normalized.count < 3 {
            normalized.append(nil)
        }

        if normalized.allSatisfy({ $0 == nil }) {
            normalized[0] = defaultPrimaryLocation
        }

        return normalized
    }

    private static func normalizedSelectedLocationIndex(_ index: Int, savedLocations: [SavedLocation?]) -> Int {
        guard savedLocations.indices.contains(index), savedLocations[index] != nil else {
            return savedLocations.firstIndex(where: { $0 != nil }) ?? Self.defaultSelectedLocationIndex
        }

        return index
    }
}
