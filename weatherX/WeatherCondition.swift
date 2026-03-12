enum WeatherCondition: String, Equatable {
    case placeholder

    var symbol: String {
        switch self {
        case .placeholder:
            return "☀️"
        }
    }

    var iconName: String {
        switch self {
        case .placeholder:
            return "sun.max.fill"
        }
    }
}
