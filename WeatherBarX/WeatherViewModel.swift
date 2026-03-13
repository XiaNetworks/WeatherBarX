import Foundation
import ServiceManagement

struct WeatherSnapshot: Equatable {
    let summary: String
    let temperature: Int?
    let condition: WeatherCondition
    let isDaylight: Bool
    let sunrise: Date?
    let sunset: Date?
    let highTemperature: Int?
    let highTemperatureAt: Date?
    let lowTemperature: Int?
    let lowTemperatureAt: Date?

    static let placeholder = WeatherSnapshot(
        summary: "Placeholder weather",
        temperature: 72,
        condition: .placeholder,
        isDaylight: true,
        sunrise: nil,
        sunset: nil,
        highTemperature: 76,
        highTemperatureAt: nil,
        lowTemperature: 64,
        lowTemperatureAt: nil
    )

    static let networkUnavailable = WeatherSnapshot(
        summary: WeatherCondition.networkError.summary,
        temperature: nil,
        condition: .networkError,
        isDaylight: true,
        sunrise: nil,
        sunset: nil,
        highTemperature: nil,
        highTemperatureAt: nil,
        lowTemperature: nil,
        lowTemperatureAt: nil
    )

    static let apiUnavailable = WeatherSnapshot(
        summary: WeatherCondition.apiError.summary,
        temperature: nil,
        condition: .apiError,
        isDaylight: true,
        sunrise: nil,
        sunset: nil,
        highTemperature: nil,
        highTemperatureAt: nil,
        lowTemperature: nil,
        lowTemperatureAt: nil
    )
}

protocol WeatherServing {
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot
}

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
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
            URLQueryItem(name: "hourly", value: "temperature_2m"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
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
        let extrema = payload.hourly.dailyExtrema(in: payload.timezone)

        return WeatherSnapshot(
            summary: condition.summary,
            temperature: roundedTemperature(from: payload.current.temperature),
            condition: condition,
            isDaylight: isDaylight,
            sunrise: payload.sunriseDate,
            sunset: payload.sunsetDate,
            highTemperature: extrema.high.map { roundedTemperature(from: $0.temperature) },
            highTemperatureAt: extrema.high?.time,
            lowTemperature: extrema.low.map { roundedTemperature(from: $0.temperature) },
            lowTemperatureAt: extrema.low?.time
        )
    }
}

struct LaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return true
        case .notRegistered, .notFound, .requiresApproval:
            return false
        @unknown default:
            return false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

struct OpenMeteoForecastResponse: Decodable {
    let timezone: String
    let current: CurrentWeather
    let hourly: HourlyWeather
    let daily: DailyWeather

    private enum CodingKeys: String, CodingKey {
        case timezone
        case current
        case hourly
        case daily
    }

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

    struct HourlyWeather: Decodable {
        struct Entry: Equatable {
            let time: Date
            let temperature: Double
        }

        let time: [String]
        let temperature: [Double]

        func dailyExtrema(in timezone: String) -> (high: Entry?, low: Entry?) {
            let entries = parsedEntries(in: timezone)
            guard let first = entries.first else {
                return (nil, nil)
            }

            var high = first
            var low = first

            for entry in entries.dropFirst() {
                if entry.temperature > high.temperature {
                    high = entry
                }
                if entry.temperature < low.temperature {
                    low = entry
                }
            }

            return (high, low)
        }

        private func parsedEntries(in timezone: String) -> [Entry] {
            zip(time, temperature).compactMap { rawTime, value in
                guard let date = OpenMeteoForecastResponse.localDate(from: rawTime, timezone: timezone) else {
                    return nil
                }
                return Entry(time: date, temperature: value)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decodeIfPresent([String].self, forKey: .time) ?? []
            temperature = try container.decodeIfPresent([Double].self, forKey: .temperature) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timezone = try container.decode(String.self, forKey: .timezone)
        current = try container.decode(CurrentWeather.self, forKey: .current)
        hourly = try container.decode(HourlyWeather.self, forKey: .hourly)
        daily = try container.decode(DailyWeather.self, forKey: .daily)
    }

    private static func localDate(from value: String?, timezone: String) -> Date? {
        guard let value else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: timezone)
        return formatter.date(from: value)
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var isMenuPresented = false
    @Published private(set) var isLoading: Bool
    @Published private(set) var snapshot: WeatherSnapshot
    @Published private(set) var lastCheckAt: Date?
    @Published private(set) var isLaunchAtLoginEnabled: Bool
    @Published private(set) var temperatureUnit: TemperatureUnit

    let settings: WeatherSettings
    private let defaults: UserDefaults
    private let launchAtLoginManager: any LaunchAtLoginManaging
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
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager(),
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
        self.defaults = defaults
        self.snapshot = snapshot ?? .placeholder
        self.isLoading = refreshOnInit && !settings.usesPlaceholderWeather
        self.isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        self.temperatureUnit = settings.temperatureUnit
        self.launchAtLoginManager = launchAtLoginManager
        self.weatherService = weatherService
        self.retryDelays = retryDelays
        self.postErrorRetryDelays = postErrorRetryDelays
        self.successRefreshDelay = successRefreshDelay
        self.now = now
        self.sleep = sleep

        if refreshOnInit && !settings.usesPlaceholderWeather {
            startRefreshLoop(showLoadingState: false)
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

    var temperatureUnitButtonText: String {
        temperatureUnit.displayText
    }

    var launchAtLoginButtonText: String {
        "Launch at Login"
    }

    var conditionIconName: String {
        snapshot.condition.iconName(isDaylight: snapshot.isDaylight)
    }

    var highDetailText: String {
        if isLoading {
            return "High: -- at --"
        }

        return "High: \(formatTemperature(snapshot.highTemperature)) at \(formatTime(snapshot.highTemperatureAt))"
    }

    var lowDetailText: String {
        if isLoading {
            return "Low: -- at --"
        }

        return "Low: \(formatTemperature(snapshot.lowTemperature)) at \(formatTime(snapshot.lowTemperatureAt))"
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
        formatLastCheckText(referenceDate: now())
    }

    var isRefreshButtonEnabled: Bool {
        isRefreshButtonEnabled(at: now())
    }

    func isRefreshButtonEnabled(at referenceDate: Date) -> Bool {
        guard !isLoading else {
            return false
        }

        guard let lastCheckAt else {
            return true
        }

        return referenceDate.timeIntervalSince(lastCheckAt) >= 60
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

    func refreshNow() {
        guard isRefreshButtonEnabled else {
            return
        }

        startRefreshLoop(showLoadingState: true)
    }

    func toggleTemperatureUnit() {
        temperatureUnit.toggle()
        defaults.set(temperatureUnit.rawValue, forKey: WeatherSettings.temperatureUnitKey)
        objectWillChange.send()
    }

    func toggleLaunchAtLogin() {
        let nextValue = !isLaunchAtLoginEnabled

        do {
            try launchAtLoginManager.setEnabled(nextValue)
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        } catch {
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        }
    }

    func toggleMenuPresentation() {
        isMenuPresented.toggle()
    }

    func formatLastCheckText(referenceDate: Date? = nil, using formatter: DateFormatter? = nil) -> String {
        guard let lastCheckAt else {
            return "Last checked: --"
        }

        let referenceDate = referenceDate ?? now()
        if referenceDate.timeIntervalSince(lastCheckAt) < 60 {
            return "Last checked: <1 min ago"
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

    private func startRefreshLoop(showLoadingState: Bool) {
        refreshTask?.cancel()

        if showLoadingState {
            isLoading = true
        }

        refreshTask = Task { [weak self] in
            await self?.refreshWeather()
        }
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

        let displayValue: Int
        switch temperatureUnit {
        case .fahrenheit:
            displayValue = value
        case .celsius:
            displayValue = Int((((Double(value) - 32) * 5) / 9).rounded())
        }

        return "\(displayValue)°"
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
