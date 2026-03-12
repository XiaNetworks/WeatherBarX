import Foundation

struct WeatherSettings: Equatable {
    static let locationNameKey = "locationName"
    static let usesPlaceholderWeatherKey = "usesPlaceholderWeather"

    static let defaultLocationName = "WeatherX"
    static let defaultUsesPlaceholderWeather = true

    let locationName: String
    let usesPlaceholderWeather: Bool

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Self.locationNameKey: Self.defaultLocationName,
            Self.usesPlaceholderWeatherKey: Self.defaultUsesPlaceholderWeather,
        ])

        locationName = defaults.string(forKey: Self.locationNameKey) ?? Self.defaultLocationName
        usesPlaceholderWeather = defaults.object(forKey: Self.usesPlaceholderWeatherKey) as? Bool ?? Self.defaultUsesPlaceholderWeather
    }
}
