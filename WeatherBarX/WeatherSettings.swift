import Foundation

struct WeatherSettings: Equatable {
    static let locationNameKey = "locationName"
    static let latitudeKey = "latitude"
    static let longitudeKey = "longitude"
    static let usesPlaceholderWeatherKey = "usesPlaceholderWeather"

    static let defaultLocationName = "Washington, DC"
    static let defaultLatitude = 38.9072
    static let defaultLongitude = -77.0369
    static let defaultUsesPlaceholderWeather = false

    let locationName: String
    let latitude: Double
    let longitude: Double
    let usesPlaceholderWeather: Bool

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Self.locationNameKey: Self.defaultLocationName,
            Self.latitudeKey: Self.defaultLatitude,
            Self.longitudeKey: Self.defaultLongitude,
            Self.usesPlaceholderWeatherKey: Self.defaultUsesPlaceholderWeather,
        ])

        locationName = defaults.string(forKey: Self.locationNameKey) ?? Self.defaultLocationName
        latitude = defaults.object(forKey: Self.latitudeKey) as? Double ?? Self.defaultLatitude
        longitude = defaults.object(forKey: Self.longitudeKey) as? Double ?? Self.defaultLongitude
        usesPlaceholderWeather = defaults.object(forKey: Self.usesPlaceholderWeatherKey) as? Bool ?? Self.defaultUsesPlaceholderWeather
    }
}
