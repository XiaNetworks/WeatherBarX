import Foundation

struct WeatherSnapshot: Equatable {
    let summary: String
    let temperature: Int?
    let condition: WeatherCondition

    static let placeholder = WeatherSnapshot(
        summary: "Placeholder weather",
        temperature: 72,
        condition: .placeholder
    )

    static let networkUnavailable = WeatherSnapshot(
        summary: WeatherCondition.networkError.summary,
        temperature: nil,
        condition: .networkError
    )

    static let apiUnavailable = WeatherSnapshot(
        summary: WeatherCondition.apiError.summary,
        temperature: nil,
        condition: .apiError
    )
}

protocol WeatherServing {
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot
}

enum WeatherServiceError: Error, Equatable {
    case networkUnavailable
    case invalidRequest
    case invalidResponse
    case requestFailed
    case decodeFailed
}

struct OpenMeteoWeatherService: WeatherServing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        do {
            return try await fetchSnapshot(latitude: latitude, longitude: longitude)
        } catch let error as WeatherServiceError {
            throw error
        } catch let error as URLError {
            throw classify(urlError: error)
        } catch {
            throw WeatherServiceError.requestFailed
        }
    }

    private func fetchSnapshot(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
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
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw WeatherServiceError.requestFailed
        }

        let payload: OpenMeteoForecastResponse
        do {
            payload = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        } catch {
            throw WeatherServiceError.decodeFailed
        }

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

    private func classify(urlError: URLError) -> WeatherServiceError {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .timedOut:
            return .networkUnavailable
        default:
            return .requestFailed
        }
    }
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
    @Published private(set) var isLoading: Bool
    @Published private(set) var snapshot: WeatherSnapshot

    let settings: WeatherSettings
    private let weatherService: WeatherServing
    private let retryDelays: [Duration]
    private let repeatedRetryDelay: Duration?
    private let sleep: @Sendable (Duration) async -> Void
    private var refreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        snapshot: WeatherSnapshot? = nil,
        weatherService: WeatherServing = OpenMeteoWeatherService(),
        refreshOnInit: Bool = true,
        retryDelays: [Duration] = [.seconds(10), .seconds(20), .seconds(30)],
        repeatedRetryDelay: Duration? = .seconds(300),
        sleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        let settings = WeatherSettings(defaults: defaults)
        self.settings = settings
        self.snapshot = snapshot ?? .placeholder
        self.isLoading = refreshOnInit && !settings.usesPlaceholderWeather
        self.weatherService = weatherService
        self.retryDelays = retryDelays
        self.repeatedRetryDelay = repeatedRetryDelay
        self.sleep = sleep

        if refreshOnInit && !settings.usesPlaceholderWeather {
            refreshTask = Task { [weak self] in
                await self?.refreshWeather()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var locationName: String {
        settings.locationName
    }

    var summaryText: String {
        snapshot.summary
    }

    var temperatureText: String {
        guard let temperature = snapshot.temperature else {
            return "--"
        }

        return "\(temperature)\u{00B0}"
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
        let attemptDelays = [Duration.zero] + retryDelays

        for (index, delay) in attemptDelays.enumerated() {
            if index > 0 {
                await sleep(delay)
            }

            if Task.isCancelled {
                return
            }

            switch await fetchSnapshot() {
            case .success(let snapshot):
                isLoading = false
                self.snapshot = snapshot
                return
            case .failure(let error):
                if index == attemptDelays.count - 1 {
                    isLoading = false
                    snapshot = snapshotForError(error)
                }
            }
        }

        guard let repeatedRetryDelay else {
            return
        }

        while !Task.isCancelled {
            await sleep(repeatedRetryDelay)

            if Task.isCancelled {
                return
            }

            switch await fetchSnapshot() {
            case .success(let snapshot):
                isLoading = false
                self.snapshot = snapshot
                return
            case .failure(let error):
                isLoading = false
                snapshot = snapshotForError(error)
            }
        }
    }

    func toggleMenuPresentation() {
        isMenuPresented.toggle()
    }

    private func fetchSnapshot() async -> Result<WeatherSnapshot, WeatherServiceError> {
        do {
            let snapshot = try await weatherService.fetchCurrentWeather(
                latitude: settings.latitude,
                longitude: settings.longitude
            )
            return .success(snapshot)
        } catch let error as WeatherServiceError {
            return .failure(error)
        } catch {
            return .failure(.requestFailed)
        }
    }

    private func snapshotForError(_ error: WeatherServiceError) -> WeatherSnapshot {
        switch error {
        case .networkUnavailable:
            return .networkUnavailable
        case .invalidRequest, .invalidResponse, .requestFailed, .decodeFailed:
            return .apiUnavailable
        }
    }
}
