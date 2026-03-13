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

struct WeatherSettings: Equatable {
    static let locationNameKey = "locationName"
    static let latitudeKey = "latitude"
    static let longitudeKey = "longitude"
    static let usesPlaceholderWeatherKey = "usesPlaceholderWeather"
    static let temperatureUnitKey = "temperatureUnit"

    static let defaultLocationName = "Washington, DC"
    static let defaultLatitude = 38.9072
    static let defaultLongitude = -77.0369
    static let defaultUsesPlaceholderWeather = false
    static let defaultTemperatureUnit: TemperatureUnit = .fahrenheit

    let locationName: String
    let latitude: Double
    let longitude: Double
    let usesPlaceholderWeather: Bool
    let temperatureUnit: TemperatureUnit

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Self.locationNameKey: Self.defaultLocationName,
            Self.latitudeKey: Self.defaultLatitude,
            Self.longitudeKey: Self.defaultLongitude,
            Self.usesPlaceholderWeatherKey: Self.defaultUsesPlaceholderWeather,
            Self.temperatureUnitKey: Self.defaultTemperatureUnit.rawValue,
        ])

        locationName = defaults.string(forKey: Self.locationNameKey) ?? Self.defaultLocationName
        latitude = defaults.object(forKey: Self.latitudeKey) as? Double ?? Self.defaultLatitude
        longitude = defaults.object(forKey: Self.longitudeKey) as? Double ?? Self.defaultLongitude
        usesPlaceholderWeather = defaults.object(forKey: Self.usesPlaceholderWeatherKey) as? Bool ?? Self.defaultUsesPlaceholderWeather
        let rawTemperatureUnit = defaults.string(forKey: Self.temperatureUnitKey) ?? Self.defaultTemperatureUnit.rawValue
        temperatureUnit = TemperatureUnit(rawValue: rawTemperatureUnit) ?? Self.defaultTemperatureUnit
    }
}
