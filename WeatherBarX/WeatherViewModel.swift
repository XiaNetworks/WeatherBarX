import Foundation

struct WeatherSnapshot: Equatable {
    let summary: String
    let temperature: Int?
    let condition: WeatherCondition
    let isDaylight: Bool
    let sunrise: Date?
    let sunset: Date?
    let highTemperature: Int?
    let lowTemperature: Int?

    static let placeholder = WeatherSnapshot(
        summary: "Placeholder weather",
        temperature: 72,
        condition: .placeholder,
        isDaylight: true,
        sunrise: nil,
        sunset: nil,
        highTemperature: 76,
        lowTemperature: 64
    )

    static let networkUnavailable = WeatherSnapshot(
        summary: WeatherCondition.networkError.summary,
        temperature: nil,
        condition: .networkError,
        isDaylight: true,
        sunrise: nil,
        sunset: nil,
        highTemperature: nil,
        lowTemperature: nil
    )

    static let apiUnavailable = WeatherSnapshot(
        summary: WeatherCondition.apiError.summary,
        temperature: nil,
        condition: .apiError,
        isDaylight: true,
        sunrise: nil,
        sunset: nil,
        highTemperature: nil,
        lowTemperature: nil
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
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 15
    private static let liveSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession

    init(session: URLSession = liveSession) {
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
            URLQueryItem(name: "daily", value: "sunrise,sunset,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await session.data(for: request)
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
            isDaylight: isDaylight,
            sunrise: payload.sunriseDate,
            sunset: payload.sunsetDate,
            highTemperature: payload.daily.temperatureMax.first.map(roundedTemperature(from:)),
            lowTemperature: payload.daily.temperatureMin.first.map(roundedTemperature(from:))
        )
    }
}

struct OpenMeteoForecastResponse: Decodable {
    let timezone: String
    let current: CurrentWeather
    let daily: DailyWeather

    var isCurrentTimeInDaylight: Bool {
        guard
            let currentDate = localDate(from: current.time),
            let sunriseDate,
            let sunsetDate
        else {
            return true
        }

        return currentDate >= sunriseDate && currentDate < sunsetDate
    }

    var sunriseDate: Date? {
        localDate(from: daily.sunrise.first)
    }

    var sunsetDate: Date? {
        localDate(from: daily.sunset.first)
    }

    private func localDate(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: timezone)
        return formatter.date(from: value)
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
        let temperatureMax: [Double]
        let temperatureMin: [Double]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sunrise = try container.decodeIfPresent([String].self, forKey: .sunrise) ?? []
            sunset = try container.decodeIfPresent([String].self, forKey: .sunset) ?? []
            temperatureMax = try container.decodeIfPresent([Double].self, forKey: .temperatureMax) ?? []
            temperatureMin = try container.decodeIfPresent([Double].self, forKey: .temperatureMin) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case sunrise
            case sunset
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
        }
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var isMenuPresented = false
    @Published private(set) var isLoading: Bool
    @Published private(set) var snapshot: WeatherSnapshot
    @Published private(set) var lastCheckAt: Date?

    let settings: WeatherSettings
    private let weatherService: WeatherServing
    private let retryDelays: [Duration]
    private let postErrorRetryDelays: [Duration]
    private let successRefreshDelay: @Sendable () -> Duration
    private let now: @Sendable () -> Date
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
        now: @escaping @Sendable () -> Date = { Date() },
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
        self.now = now
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
        if isLoading {
            return "Loading weather..."
        }

        return snapshot.summary
    }

    var temperatureText: String {
        if isLoading {
            return "--"
        }

        return formatTemperature(snapshot.temperature)
    }

    var conditionIconName: String {
        snapshot.condition.iconName(isDaylight: snapshot.isDaylight)
    }

    var dailyRangeText: String {
        if isLoading {
            return "H: --  L: --"
        }

        let high = formatTemperature(snapshot.highTemperature)
        let low = formatTemperature(snapshot.lowTemperature)
        return "H: \(high)  L: \(low)"
    }

    var sunriseText: String {
        if isLoading {
            return "Sunrise: --"
        }

        return formatSunriseText()
    }

    var sunsetText: String {
        if isLoading {
            return "Sunset: --"
        }

        return formatSunsetText()
    }

    var lastCheckText: String {
        formatLastCheckText()
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

    func formatLastCheckText(using formatter: DateFormatter? = nil) -> String {
        guard let lastCheckAt else {
            return "Last checked: --"
        }

        let formatter = formatter ?? Self.timeFormatter
        return "Last checked: \(formatter.string(from: lastCheckAt))"
    }

    func formatSunriseText(using formatter: DateFormatter? = nil) -> String {
        "Sunrise: \(formatTime(snapshot.sunrise, using: formatter))"
    }

    func formatSunsetText(using formatter: DateFormatter? = nil) -> String {
        "Sunset: \(formatTime(snapshot.sunset, using: formatter))"
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
            lastCheckAt = now()
            return .success(snapshot)
        } catch let error as WeatherServiceError {
            lastCheckAt = now()
            return .failure(error)
        } catch {
            lastCheckAt = now()
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

    private func formatTemperature(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        return "\(value)°"
    }

    private func formatTime(_ value: Date?, using formatter: DateFormatter? = nil) -> String {
        guard let value else {
            return "--"
        }

        let formatter = formatter ?? Self.timeFormatter
        return formatter.string(from: value)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
