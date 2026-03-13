enum WeatherCondition: String, Equatable {
    case placeholder
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

    var symbol: String {
        switch self {
        case .placeholder:
            return "☀️"
        case .clear:
            return "☀️"
        case .partlyCloudy:
            return "⛅️"
        case .cloudy:
            return "☁️"
        case .fog:
            return "🌫️"
        case .drizzle:
            return "🌦️"
        case .rain:
            return "🌧️"
        case .snow:
            return "❄️"
        case .thunderstorm:
            return "⛈️"
        }
    }

    var iconName: String {
        switch self {
        case .placeholder:
            return "sun.max.fill"
        case .clear:
            return "sun.max.fill"
        case .partlyCloudy:
            return "cloud.sun.fill"
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
            return "Placeholder weather"
        case .clear:
            return "Clear sky"
        case .partlyCloudy:
            return "Partly cloudy"
        case .cloudy:
            return "Cloudy"
        case .fog:
            return "Foggy"
        case .drizzle:
            return "Drizzle"
        case .rain:
            return "Rain"
        case .snow:
            return "Snow"
        case .thunderstorm:
            return "Thunderstorm"
        }
    }
}
