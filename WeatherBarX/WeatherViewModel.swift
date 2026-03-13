import Foundation

struct WeatherSnapshot: Equatable {
    let summary: String
    let temperature: Int
    let condition: WeatherCondition

    static let placeholder = WeatherSnapshot(
        summary: "Placeholder weather",
        temperature: 72,
        condition: .placeholder
    )
}

protocol WeatherServing {
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot
}

struct OpenMeteoWeatherService: WeatherServing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw WeatherServiceError.requestFailed
        }

        let payload = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        let condition = WeatherCondition(
            weatherCode: payload.current.weatherCode,
            isDaylight: payload.current.isDay == 1
        )

        return WeatherSnapshot(
            summary: condition.summary,
            temperature: Int(payload.current.temperature.rounded()),
            condition: condition
        )
    }
}

enum WeatherServiceError: Error {
    case invalidRequest
    case requestFailed
}

private struct OpenMeteoForecastResponse: Decodable {
    let current: CurrentWeather

    struct CurrentWeather: Decodable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var isMenuPresented = false
    @Published private(set) var snapshot: WeatherSnapshot

    let settings: WeatherSettings
    private let weatherService: WeatherServing

    init(
        defaults: UserDefaults = .standard,
        snapshot: WeatherSnapshot? = nil,
        weatherService: WeatherServing = OpenMeteoWeatherService(),
        refreshOnInit: Bool = true
    ) {
        let settings = WeatherSettings(defaults: defaults)
        self.settings = settings
        self.snapshot = snapshot ?? .placeholder
        self.weatherService = weatherService

        if refreshOnInit && !settings.usesPlaceholderWeather {
            Task {
                await refreshWeather()
            }
        }
    }

    var locationName: String {
        settings.locationName
    }

    var summaryText: String {
        snapshot.summary
    }

    var temperatureText: String {
        "\(snapshot.temperature)\u{00B0}"
    }

    var conditionSymbol: String {
        snapshot.condition.symbol
    }

    var conditionIconName: String {
        snapshot.condition.iconName
    }

    var menuBarTitle: String {
        "\(conditionSymbol) \(temperatureText)"
    }

    func refreshWeather() async {
        do {
            snapshot = try await weatherService.fetchCurrentWeather(
                latitude: settings.latitude,
                longitude: settings.longitude
            )
        } catch {
            snapshot = .placeholder
        }
    }

    func toggleMenuPresentation() {
        isMenuPresented.toggle()
    }
}
