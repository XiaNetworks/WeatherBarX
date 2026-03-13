import Foundation

struct WeatherSnapshot: Equatable {
    let summary: String
    let temperature: Int?
    let condition: WeatherCondition
    let isDaylight: Bool

    static let placeholder = WeatherSnapshot(
        summary: "Placeholder weather",
        temperature: 72,
        condition: .placeholder,
        isDaylight: true
    )

    static let networkUnavailable = WeatherSnapshot(
        summary: WeatherCondition.networkError.summary,
        temperature: nil,
        condition: .networkError,
        isDaylight: true
    )

    static let apiUnavailable = WeatherSnapshot(
        summary: WeatherCondition.apiError.summary,
        temperature: nil,
        condition: .apiError,
        isDaylight: true
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
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto"),
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

        return try Self.decodeSnapshot(from: data)
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

    static func decodeSnapshot(from data: Data) throws -> WeatherSnapshot {
        do {
            let payload = try decoder.decode(OpenMeteoForecastResponse.self, from: data)
            return snapshot(from: payload)
        } catch {
            throw WeatherServiceError.decodeFailed
        }
    }

    static func roundedTemperature(from temperature: Double) -> Int {
        Int(temperature.rounded())
    }

    private static let decoder = JSONDecoder()

    private static func snapshot(from payload: OpenMeteoForecastResponse) -> WeatherSnapshot {
        let isDaylight = payload.isCurrentTimeInDaylight
        let condition = WeatherCondition(
            weatherCode: payload.current.weatherCode,
            isDaylight: isDaylight
        )

        return WeatherSnapshot(
            summary: condition.summary,
            temperature: roundedTemperature(from: payload.current.temperature),
            condition: condition,
            isDaylight: isDaylight
        )
    }
}

struct OpenMeteoForecastResponse: Decodable {
    let timezone: String
    let current: CurrentWeather
    let daily: DailyWeather

    var isCurrentTimeInDaylight: Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: timezone)

        guard
            let currentDate = formatter.date(from: current.time),
            let sunrise = formatter.date(from: daily.sunrise.first ?? ""),
            let sunset = formatter.date(from: daily.sunset.first ?? "")
        else {
            return true
        }

        return currentDate >= sunrise && currentDate < sunset
    }

    struct CurrentWeather: Decodable {
        let time: String
        let temperature: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct DailyWeather: Decodable {
        let sunrise: [String]
        let sunset: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sunrise = try container.decodeIfPresent([String].self, forKey: .sunrise) ?? []
            sunset = try container.decodeIfPresent([String].self, forKey: .sunset) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case sunrise
            case sunset
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
    private let postErrorRetryDelays: [Duration]
    private let successRefreshDelay: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var refreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        snapshot: WeatherSnapshot? = nil,
        weatherService: WeatherServing = OpenMeteoWeatherService(),
        refreshOnInit: Bool = true,
        retryDelays: [Duration] = [.seconds(10), .seconds(20), .seconds(30)],
        postErrorRetryDelays: [Duration] = [.seconds(120), .seconds(180), .seconds(300)],
        successRefreshDelay: @escaping @Sendable () -> Duration = {
            .seconds(Int.random(in: 600 ... 900))
        },
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
        self.postErrorRetryDelays = postErrorRetryDelays
        self.successRefreshDelay = successRefreshDelay
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

    var conditionIconName: String {
        snapshot.condition.iconName(isDaylight: snapshot.isDaylight)
    }

    func refreshWeather() async {
        while !Task.isCancelled {
            let didSucceed = await runRefreshCycle()
            guard didSucceed else {
                return
            }

            let delay = successRefreshDelay()
            await sleep(delay)

            if Task.isCancelled {
                return
            }
        }
    }

    func toggleMenuPresentation() {
        isMenuPresented.toggle()
    }

    private func runRefreshCycle() async -> Bool {
        let attemptDelays = [Duration.zero] + retryDelays

        for (index, delay) in attemptDelays.enumerated() {
            if index > 0 {
                await sleep(delay)
            }

            if Task.isCancelled {
                return false
            }

            switch await fetchSnapshot() {
            case .success(let snapshot):
                isLoading = false
                self.snapshot = snapshot
                return true
            case .failure(let error):
                if index == attemptDelays.count - 1 {
                    isLoading = false
                    snapshot = snapshotForError(error)
                }
            }
        }

        guard !postErrorRetryDelays.isEmpty else {
            return false
        }

        for delay in postErrorRetryDelays {
            await sleep(delay)

            if Task.isCancelled {
                return false
            }

            switch await fetchSnapshot() {
            case .success(let snapshot):
                isLoading = false
                self.snapshot = snapshot
                return true
            case .failure(let error):
                isLoading = false
                snapshot = snapshotForError(error)
            }
        }

        guard let repeatingDelay = postErrorRetryDelays.last else {
            return false
        }

        while !Task.isCancelled {
            await sleep(repeatingDelay)

            if Task.isCancelled {
                return false
            }

            switch await fetchSnapshot() {
            case .success(let snapshot):
                isLoading = false
                self.snapshot = snapshot
                return true
            case .failure(let error):
                isLoading = false
                snapshot = snapshotForError(error)
            }
        }

        return false
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
