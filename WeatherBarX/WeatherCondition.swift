enum WeatherCondition: String, Codable, Equatable {
    case placeholder
    case networkError
    case apiError
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm

    init(weatherCode: Int, isDaylight: Bool) {
        switch weatherCode {
        case 0:
            self = .clear
        case 1, 2, 3:
            self = weatherCode == 3 ? .cloudy : .partlyCloudy
        case 45, 48:
            self = .fog
        case 51, 53, 55, 56, 57:
            self = .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82:
            self = .rain
        case 71, 73, 75, 77, 85, 86:
            self = .snow
        case 95, 96, 99:
            self = .thunderstorm
        default:
            self = isDaylight ? .partlyCloudy : .cloudy
        }
    }

    func iconName(isDaylight: Bool) -> String {
        switch self {
        case .placeholder:
            return "sun.max.fill"
        case .networkError:
            return "wifi.slash"
        case .apiError:
            return "cloud.slash"
        case .clear:
            return isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy:
            return isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy:
            return "cloud.fill"
        case .fog:
            return "cloud.fog.fill"
        case .drizzle:
            return "cloud.drizzle.fill"
        case .rain:
            return "cloud.rain.fill"
        case .snow:
            return "cloud.snow.fill"
        case .thunderstorm:
            return "cloud.bolt.rain.fill"
        }
    }

    var summary: String {
        switch self {
        case .placeholder:
            return L10n.tr("Placeholder weather")
        case .networkError:
            return L10n.tr("Network unavailable")
        case .apiError:
            return L10n.tr("Weather API unavailable")
        case .clear:
            return L10n.tr("Clear sky")
        case .partlyCloudy:
            return L10n.tr("Partly cloudy")
        case .cloudy:
            return L10n.tr("Cloudy")
        case .fog:
            return L10n.tr("Foggy")
        case .drizzle:
            return L10n.tr("Drizzle")
        case .rain:
            return L10n.tr("Rain")
        case .snow:
            return L10n.tr("Snow")
        case .thunderstorm:
            return L10n.tr("Thunderstorm")
        }
    }
}
