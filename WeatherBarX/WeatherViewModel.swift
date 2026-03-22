import CoreLocation
import Foundation
import ServiceManagement

struct WeatherSnapshot: Codable, Equatable {
    struct DailyForecast: Codable, Equatable, Identifiable {
        let date: Date
        let highTemperature: Int
        let lowTemperature: Int
        let precipitationProbability: Int
        let condition: WeatherCondition

        var id: Date { date }
    }

    struct HourlyTemperature: Codable, Equatable {
        let time: Date
        let temperature: Int
    }

    struct HourlyPrecipitationProbability: Codable, Equatable {
        let time: Date
        let probability: Int
    }

    struct HourlyWindSpeed: Codable, Equatable {
        let time: Date
        let speed: Int
    }

    let summary: String
    let temperature: Int?
    let condition: WeatherCondition
    let isDaylight: Bool
    let timezoneIdentifier: String?
    let currentObservationTime: Date?
    let sunrise: Date?
    let sunset: Date?
    let sunriseTimes: [Date]
    let sunsetTimes: [Date]
    let highTemperature: Int?
    let highTemperatureAt: Date?
    let lowTemperature: Int?
    let lowTemperatureAt: Date?
    let windSpeed: Int?
    let humidity: Int?
    let precipitationChance: Int?
    let hourlyTemperatures: [HourlyTemperature]
    let hourlyPrecipitationProbabilities: [HourlyPrecipitationProbability]
    let hourlyWindSpeeds: [HourlyWindSpeed]
    let dailyForecasts: [DailyForecast]

    init(
        summary: String,
        temperature: Int?,
        condition: WeatherCondition,
        isDaylight: Bool,
        timezoneIdentifier: String? = nil,
        currentObservationTime: Date? = nil,
        sunrise: Date?,
        sunset: Date?,
        sunriseTimes: [Date] = [],
        sunsetTimes: [Date] = [],
        highTemperature: Int?,
        highTemperatureAt: Date?,
        lowTemperature: Int?,
        lowTemperatureAt: Date?,
        windSpeed: Int? = nil,
        humidity: Int? = nil,
        precipitationChance: Int? = nil,
        hourlyTemperatures: [HourlyTemperature] = [],
        hourlyPrecipitationProbabilities: [HourlyPrecipitationProbability] = [],
        hourlyWindSpeeds: [HourlyWindSpeed] = [],
        dailyForecasts: [DailyForecast] = []
    ) {
        self.summary = summary
        self.temperature = temperature
        self.condition = condition
        self.isDaylight = isDaylight
        self.timezoneIdentifier = timezoneIdentifier
        self.currentObservationTime = currentObservationTime
        self.sunrise = sunrise
        self.sunset = sunset
        self.sunriseTimes = sunriseTimes
        self.sunsetTimes = sunsetTimes
        self.highTemperature = highTemperature
        self.highTemperatureAt = highTemperatureAt
        self.lowTemperature = lowTemperature
        self.lowTemperatureAt = lowTemperatureAt
        self.windSpeed = windSpeed
        self.humidity = humidity
        self.precipitationChance = precipitationChance
        self.hourlyTemperatures = hourlyTemperatures
        self.hourlyPrecipitationProbabilities = hourlyPrecipitationProbabilities
        self.hourlyWindSpeeds = hourlyWindSpeeds
        self.dailyForecasts = dailyForecasts
    }

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

protocol DeviceLocationProviding {
    func detectLocation() async throws -> SavedLocation
}

protocol SearchLocationProviding {
    func searchLocation(query: String) async throws -> SavedLocation
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
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "sunrise,sunset,temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code"),
            URLQueryItem(name: "forecast_days", value: "10"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
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
        let hourlyTemperatures = payload.hourly.temperatureSeries(in: payload.timezone).map {
            WeatherSnapshot.HourlyTemperature(
                time: $0.time,
                temperature: roundedTemperature(from: $0.temperature)
            )
        }
        let hourlyPrecipitationProbabilities = payload.hourly.precipitationProbabilitySeries(in: payload.timezone).map {
            WeatherSnapshot.HourlyPrecipitationProbability(
                time: $0.time,
                probability: roundedTemperature(from: $0.probability)
            )
        }
        let hourlyWindSpeeds = payload.hourly.windSpeedSeries(in: payload.timezone).map {
            WeatherSnapshot.HourlyWindSpeed(
                time: $0.time,
                speed: roundedTemperature(from: $0.speed)
            )
        }
        let dailyForecasts = payload.daily.forecastSeries(in: payload.timezone).map {
            WeatherSnapshot.DailyForecast(
                date: $0.date,
                highTemperature: roundedTemperature(from: $0.highTemperature),
                lowTemperature: roundedTemperature(from: $0.lowTemperature),
                precipitationProbability: roundedTemperature(from: $0.precipitationProbability),
                condition: WeatherCondition(weatherCode: $0.weatherCode, isDaylight: true)
            )
        }
        let extrema = payload.hourly.dailyExtrema(
            in: payload.timezone,
            onSameDayAs: payload.currentDate
        )
        let precipitationChance = payload.hourly.currentPrecipitationProbability(
            at: payload.currentDate,
            in: payload.timezone
        )

        return WeatherSnapshot(
            summary: condition.summary,
            temperature: roundedTemperature(from: payload.current.temperature),
            condition: condition,
            isDaylight: isDaylight,
            timezoneIdentifier: payload.timezone,
            currentObservationTime: payload.currentDate,
            sunrise: payload.sunriseDate,
            sunset: payload.sunsetDate,
            sunriseTimes: payload.sunriseDates,
            sunsetTimes: payload.sunsetDates,
            highTemperature: extrema.high.map { roundedTemperature(from: $0.temperature) },
            highTemperatureAt: extrema.high?.time,
            lowTemperature: extrema.low.map { roundedTemperature(from: $0.temperature) },
            lowTemperatureAt: extrema.low?.time,
            windSpeed: payload.current.windSpeed.map(roundedTemperature(from:)),
            humidity: payload.current.relativeHumidity.map(roundedTemperature(from:)),
            precipitationChance: precipitationChance.map(roundedTemperature(from:)),
            hourlyTemperatures: hourlyTemperatures,
            hourlyPrecipitationProbabilities: hourlyPrecipitationProbabilities,
            hourlyWindSpeeds: hourlyWindSpeeds,
            dailyForecasts: dailyForecasts
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

struct CachedWeatherEntry: Codable, Equatable {
    let snapshot: WeatherSnapshot
    let checkedAt: Date
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

    var currentDate: Date? {
        localDate(from: current.time)
    }

    var sunriseDate: Date? {
        sunriseDates.first
    }

    var sunsetDate: Date? {
        sunsetDates.first
    }

    var sunriseDates: [Date] {
        daily.sunrise.compactMap(localDate(from:))
    }

    var sunsetDates: [Date] {
        daily.sunset.compactMap(localDate(from:))
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
        let windSpeed: Double?
        let relativeHumidity: Double?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case relativeHumidity = "relative_humidity_2m"
        }
    }

    struct HourlyWeather: Decodable {
        struct Entry: Equatable {
            let time: Date
            let temperature: Double
        }

        struct PrecipitationEntry: Equatable {
            let time: Date
            let probability: Double
        }

        struct WindSpeedEntry: Equatable {
            let time: Date
            let speed: Double
        }

        let time: [String]
        let temperature: [Double]
        let precipitationProbability: [Double]
        let windSpeed: [Double]

        func dailyExtrema(in timezone: String, onSameDayAs referenceDate: Date?) -> (high: Entry?, low: Entry?) {
            let entries = temperatureSeries(in: timezone)
            let filteredEntries: [Entry]
            if let referenceDate {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
                filteredEntries = entries.filter { calendar.isDate($0.time, inSameDayAs: referenceDate) }
            } else {
                filteredEntries = entries
            }

            guard let first = filteredEntries.first else {
                return (nil, nil)
            }

            var high = first
            var low = first

            for entry in filteredEntries.dropFirst() {
                if entry.temperature > high.temperature {
                    high = entry
                }
                if entry.temperature < low.temperature {
                    low = entry
                }
            }

            return (high, low)
        }

        func temperatureSeries(in timezone: String) -> [Entry] {
            zip(time, temperature).compactMap { rawTime, value in
                guard let date = OpenMeteoForecastResponse.localDate(from: rawTime, timezone: timezone) else {
                    return nil
                }
                return Entry(time: date, temperature: value)
            }
        }

        func precipitationProbabilitySeries(in timezone: String) -> [PrecipitationEntry] {
            zip(time, precipitationProbability).compactMap { rawTime, value in
                guard let date = OpenMeteoForecastResponse.localDate(from: rawTime, timezone: timezone) else {
                    return nil
                }
                return PrecipitationEntry(time: date, probability: value)
            }
        }

        func windSpeedSeries(in timezone: String) -> [WindSpeedEntry] {
            zip(time, windSpeed).compactMap { rawTime, value in
                guard let date = OpenMeteoForecastResponse.localDate(from: rawTime, timezone: timezone) else {
                    return nil
                }
                return WindSpeedEntry(time: date, speed: value)
            }
        }

        func currentPrecipitationProbability(at currentDate: Date?, in timezone: String) -> Double? {
            guard let currentDate else {
                return precipitationProbability.first
            }

            let entries = parsedPrecipitationEntries(in: timezone)
            guard let nearest = entries.min(by: { abs($0.time.timeIntervalSince(currentDate)) < abs($1.time.timeIntervalSince(currentDate)) }) else {
                return nil
            }

            return nearest.value
        }

        private func parsedPrecipitationEntries(in timezone: String) -> [(time: Date, value: Double)] {
            zip(time, precipitationProbability).compactMap { rawTime, value in
                guard let date = OpenMeteoForecastResponse.localDate(from: rawTime, timezone: timezone) else {
                    return nil
                }
                return (time: date, value: value)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decodeIfPresent([String].self, forKey: .time) ?? []
            temperature = try container.decodeIfPresent([Double].self, forKey: .temperature) ?? []
            precipitationProbability = try container.decodeIfPresent([Double].self, forKey: .precipitationProbability) ?? []
            windSpeed = try container.decodeIfPresent([Double].self, forKey: .windSpeed) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct DailyWeather: Decodable {
        struct ForecastEntry: Equatable {
            let date: Date
            let highTemperature: Double
            let lowTemperature: Double
            let precipitationProbability: Double
            let weatherCode: Int
        }

        let time: [String]
        let sunrise: [String]
        let sunset: [String]
        let temperatureMax: [Double]
        let temperatureMin: [Double]
        let precipitationProbabilityMax: [Double]
        let weatherCode: [Int]

        func forecastSeries(in timezone: String) -> [ForecastEntry] {
            zip(time, zip(temperatureMax, zip(temperatureMin, zip(precipitationProbabilityMax, weatherCode)))).compactMap { rawDate, values in
                guard let date = OpenMeteoForecastResponse.localDay(from: rawDate, timezone: timezone) else {
                    return nil
                }
                return ForecastEntry(
                    date: date,
                    highTemperature: values.0,
                    lowTemperature: values.1.0,
                    precipitationProbability: values.1.1.0,
                    weatherCode: values.1.1.1
                )
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decodeIfPresent([String].self, forKey: .time) ?? []
            sunrise = try container.decodeIfPresent([String].self, forKey: .sunrise) ?? []
            sunset = try container.decodeIfPresent([String].self, forKey: .sunset) ?? []
            temperatureMax = try container.decodeIfPresent([Double].self, forKey: .temperatureMax) ?? []
            temperatureMin = try container.decodeIfPresent([Double].self, forKey: .temperatureMin) ?? []
            precipitationProbabilityMax = try container.decodeIfPresent([Double].self, forKey: .precipitationProbabilityMax) ?? []
            weatherCode = try container.decodeIfPresent([Int].self, forKey: .weatherCode) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case time
            case sunrise
            case sunset
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case weatherCode = "weather_code"
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

    private static func localDay(from value: String?, timezone: String) -> Date? {
        guard let value else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: timezone)
        return formatter.date(from: value)
    }
}

@MainActor
struct LocationSlot: Identifiable, Equatable {
    let index: Int
    let location: SavedLocation?

    var id: Int { index }

    var title: String {
        location?.name ?? L10n.tr("Add Location")
    }

    var isEmpty: Bool {
        location == nil
    }
}

enum LocationInputError: LocalizedError, Equatable {
    case emptyName
    case invalidLatitude
    case invalidLongitude
    case invalidSlot
    case detectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return L10n.tr("Enter a location name.")
        case .invalidLatitude:
            return L10n.tr("Enter a latitude between -90 and 90.")
        case .invalidLongitude:
            return L10n.tr("Enter a longitude between -180 and 180.")
        case .invalidSlot:
            return L10n.tr("Unable to save this location slot.")
        case .detectionFailed(let message):
            return message
        }
    }
}

private struct GeocodedSearchLocationProvider: SearchLocationProviding {
    private let geocoder = CLGeocoder()

    func searchLocation(query: String) async throws -> SavedLocation {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw LocationInputError.detectionFailed(L10n.tr("Enter a ZIP code or city name to search."))
        }

        let placemarks = try await geocoder.geocodeAddressString(trimmedQuery)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw LocationInputError.detectionFailed(L10n.tr("No matching location was found."))
        }

        let name = CurrentDeviceLocationProvider.locationName(from: placemark, coordinate: location.coordinate)
        return SavedLocation(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

private final class CurrentDeviceLocationProvider: NSObject, DeviceLocationProviding, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func detectLocation() async throws -> SavedLocation {
        let location = try await requestLocation()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        let name = Self.locationName(from: placemarks.first, coordinate: location.coordinate)

        return SavedLocation(
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private func requestLocation() async throws -> CLLocation {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            throw LocationInputError.detectionFailed(L10n.tr("Allow location access in System Settings to detect your current location."))
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.locationManager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            continuation?.resume(throwing: LocationInputError.detectionFailed(L10n.tr("Unable to determine your current location.")))
            continuation = nil
            return
        }

        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: LocationInputError.detectionFailed(L10n.tr("Unable to determine your current location.")))
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(throwing: LocationInputError.detectionFailed(L10n.tr("Allow location access in System Settings to detect your current location.")))
            continuation = nil
        }
    }

    static func locationName(from placemark: CLPlacemark?, coordinate: CLLocationCoordinate2D) -> String {
        let parts = [placemark?.locality, placemark?.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }
        if let name = placemark?.name, !name.isEmpty {
            return name
        }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    struct DailyForecastChartPoint: Identifiable, Equatable {
        let date: Date
        let highTemperature: Int
        let lowTemperature: Int
        let precipitationProbability: Int
        let condition: WeatherCondition

        var id: Date { date }
    }

    struct TemperatureChartPoint: Identifiable, Equatable {
        let time: Date
        let temperature: Int

        var id: Date { time }
    }

    struct TimeMarker: Identifiable, Equatable {
        enum Kind: Equatable {
            case sunrise
            case current
            case sunset
        }

        let kind: Kind
        let time: Date

        var id: String {
            "\(kind)-\(time.timeIntervalSince1970)"
        }
    }

    @Published var isMenuPresented = false
    @Published private(set) var isLoading: Bool
    @Published private(set) var snapshot: WeatherSnapshot
    @Published private(set) var lastCheckAt: Date?
    @Published private(set) var isLaunchAtLoginEnabled: Bool
    @Published private(set) var temperatureUnit: TemperatureUnit
    @Published private(set) var savedLocations: [SavedLocation?]
    @Published private(set) var selectedLocationIndex: Int

    let settings: WeatherSettings
    private let defaults: UserDefaults
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let deviceLocationProvider: any DeviceLocationProviding
    private let searchLocationProvider: any SearchLocationProviding
    private let weatherService: WeatherServing
    private let retryDelays: [Duration]
    private let postErrorRetryDelays: [Duration]
    private let successRefreshDelay: @Sendable () -> Duration
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private var cachedWeatherByLocation: [String: CachedWeatherEntry]
    private var refreshTask: Task<Void, Never>?

    private static let cacheFreshnessInterval: TimeInterval = 15 * 60

    init(
        defaults: UserDefaults = .standard,
        snapshot: WeatherSnapshot? = nil,
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager(),
        deviceLocationProvider: any DeviceLocationProviding = CurrentDeviceLocationProvider(),
        searchLocationProvider: any SearchLocationProviding = GeocodedSearchLocationProvider(),
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
        Self.initializeLaunchAtLoginIfNeeded(defaults: defaults, launchAtLoginManager: launchAtLoginManager)

        self.settings = settings
        self.defaults = defaults
        self.snapshot = snapshot ?? .placeholder
        self.isLoading = refreshOnInit && !settings.usesPlaceholderWeather
        self.isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        self.temperatureUnit = settings.temperatureUnit
        self.savedLocations = settings.savedLocations
        self.selectedLocationIndex = settings.selectedLocationIndex
        self.launchAtLoginManager = launchAtLoginManager
        self.deviceLocationProvider = deviceLocationProvider
        self.searchLocationProvider = searchLocationProvider
        self.weatherService = weatherService
        self.retryDelays = retryDelays
        self.postErrorRetryDelays = postErrorRetryDelays
        self.successRefreshDelay = successRefreshDelay
        self.now = now
        self.sleep = sleep
        self.cachedWeatherByLocation = Self.decodeCachedWeather(from: defaults.data(forKey: WeatherSettings.cachedWeatherByLocationKey)) ?? [:]

        if refreshOnInit && !settings.usesPlaceholderWeather {
            restoreCachedWeatherIfFreshForCurrentLocation()
        }
    }

    private static func initializeLaunchAtLoginIfNeeded(
        defaults: UserDefaults,
        launchAtLoginManager: any LaunchAtLoginManaging
    ) {
        guard !defaults.bool(forKey: WeatherSettings.hasInitializedLaunchAtLoginKey) else {
            return
        }

        defer {
            defaults.set(true, forKey: WeatherSettings.hasInitializedLaunchAtLoginKey)
        }

        guard !launchAtLoginManager.isEnabled else {
            return
        }

        try? launchAtLoginManager.setEnabled(true)
    }

    deinit {
        refreshTask?.cancel()
    }

    var locationName: String {
        currentLocation.name
    }

    var alternateLocationSlots: [LocationSlot] {
        savedLocations.enumerated().compactMap { index, location in
            guard index != selectedLocationIndex else {
                return nil
            }

            return LocationSlot(index: index, location: location)
        }
    }

    var summaryText: String {
        if isLoading {
            return L10n.tr("Loading weather...")
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
        L10n.tr("Start at Login")
    }

    var conditionIconName: String {
        snapshot.condition.iconName(isDaylight: snapshot.isDaylight)
    }

    var highDetailText: String {
        if isLoading {
            return L10n.tr("High: -- at --")
        }

        return L10n.format("High: %@ at %@", formatTemperature(snapshot.highTemperature), formatTime(snapshot.highTemperatureAt))
    }

    var lowDetailText: String {
        if isLoading {
            return L10n.tr("Low: -- at --")
        }

        return L10n.format("Low: %@ at %@", formatTemperature(snapshot.lowTemperature), formatTime(snapshot.lowTemperatureAt))
    }

    var sunriseText: String {
        if isLoading {
            return L10n.tr("Sunrise: --")
        }

        return formatSunriseText()
    }

    var sunsetText: String {
        if isLoading {
            return L10n.tr("Sunset: --")
        }

        return formatSunsetText()
    }

    var next24HourHighDetailText: String {
        if isLoading {
            return L10n.tr("High: -- at --")
        }

        return L10n.format("High: %@ at %@", temperatureChartValueText(next24HourTemperatureChartHigh), formatRelativeDayTime(next24HourTemperatureChartHighAt))
    }

    var next24HourLowDetailText: String {
        if isLoading {
            return L10n.tr("Low: -- at --")
        }

        return L10n.format("Low: %@ at %@", temperatureChartValueText(next24HourTemperatureChartLow), formatRelativeDayTime(next24HourTemperatureChartLowAt))
    }

    var next24HourSunriseText: String {
        if isLoading {
            return L10n.tr("Sunrise: --")
        }

        return L10n.format("Sunrise: %@", formatRelativeDayTime(next24HourSunriseTime))
    }

    var next24HourSunsetText: String {
        if isLoading {
            return L10n.tr("Sunset: --")
        }

        return L10n.format("Sunset: %@", formatRelativeDayTime(next24HourSunsetTime))
    }

    var windText: String {
        if isLoading {
            return L10n.tr("Wind: --")
        }

        return formatWindText()
    }

    var humidityText: String {
        if isLoading {
            return L10n.tr("Humidity: --")
        }

        return formatHumidityText()
    }

    var precipitationText: String {
        if isLoading {
            return L10n.tr("Precipitation: --")
        }

        return formatPrecipitationText()
    }

    var windInlineText: String {
        if isLoading {
            return "--"
        }

        return formatWindSpeedValue()
    }

    var humidityInlineText: String {
        if isLoading {
            return "--"
        }

        return formatPercent(snapshot.humidity)
    }

    var precipitationInlineText: String {
        if isLoading {
            return "--"
        }

        return formatPercent(snapshot.precipitationChance)
    }

    var lastCheckText: String {
        formatLastCheckText(referenceDate: now())
    }

    var temperatureChartPoints: [TemperatureChartPoint] {
        currentDayHourlyTemperatures.map { point in
            TemperatureChartPoint(time: point.time, temperature: displayTemperatureValue(point.temperature))
        }
    }

    var temperatureChartTimeMarkers: [TimeMarker] {
        [
            snapshot.sunrise.map { TimeMarker(kind: .sunrise, time: $0) },
            snapshot.currentObservationTime.map { TimeMarker(kind: .current, time: $0) },
            snapshot.sunset.map { TimeMarker(kind: .sunset, time: $0) },
        ]
        .compactMap { $0 }
        .sorted { $0.time < $1.time }
    }

    var next24HourTemperatureChartPoints: [TemperatureChartPoint] {
        next24HourHourlyTemperatures.map { point in
            TemperatureChartPoint(time: point.time, temperature: displayTemperatureValue(point.temperature))
        }
    }

    var next24HourTemperatureChartTimeMarkers: [TimeMarker] {
        guard let domain = next24HourTemperatureChartXDomain else {
            return []
        }

        let solarMarkers = snapshot.sunriseTimes.map { TimeMarker(kind: .sunrise, time: $0) } +
            snapshot.sunsetTimes.map { TimeMarker(kind: .sunset, time: $0) }

        return ([snapshot.currentObservationTime.map { TimeMarker(kind: .current, time: $0) }] + solarMarkers.map(Optional.some))
            .compactMap { $0 }
            .filter { domain.contains($0.time) }
            .sorted { $0.time < $1.time }
    }

    var temperatureChartHigh: Int? {
        snapshot.highTemperature.map(displayTemperatureValue(_:))
    }

    var temperatureChartHighAt: Date? {
        snapshot.highTemperatureAt
    }

    var temperatureChartLow: Int? {
        snapshot.lowTemperature.map(displayTemperatureValue(_:))
    }

    var temperatureChartLowAt: Date? {
        snapshot.lowTemperatureAt
    }

    var next24HourTemperatureChartHigh: Int? {
        next24HourHourlyTemperatures.max(by: { $0.temperature < $1.temperature }).map { displayTemperatureValue($0.temperature) }
    }

    var next24HourTemperatureChartHighAt: Date? {
        next24HourHourlyTemperatures.max(by: { $0.temperature < $1.temperature })?.time
    }

    var next24HourTemperatureChartLow: Int? {
        next24HourHourlyTemperatures.min(by: { $0.temperature < $1.temperature }).map { displayTemperatureValue($0.temperature) }
    }

    var next24HourTemperatureChartLowAt: Date? {
        next24HourHourlyTemperatures.min(by: { $0.temperature < $1.temperature })?.time
    }

    var temperatureChartXDomain: ClosedRange<Date>? {
        let calendar = chartCalendar
        let referenceDate = snapshot.currentObservationTime
            ?? snapshot.hourlyTemperatures.first?.time
            ?? snapshot.sunrise
            ?? snapshot.sunset

        guard
            let referenceDate,
            let startOfDay = calendar.startOfDay(for: referenceDate) as Date?,
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        else {
            return nil
        }

        return startOfDay ... endOfDay
    }

    var temperatureChartYDomain: ClosedRange<Double>? {
        chartYDomain(for: temperatureChartPoints)
    }

    var next24HourTemperatureChartXDomain: ClosedRange<Date>? {
        guard
            let observationTime = snapshot.currentObservationTime,
            let start = roundedDownToThreeHourBoundary(observationTime)
        else {
            return nil
        }

        return start ... start.addingTimeInterval(24 * 60 * 60)
    }

    var next24HourTemperatureChartYDomain: ClosedRange<Double>? {
        chartYDomain(for: next24HourTemperatureChartPoints)
    }

    var next24HourPrecipitationChartPoints: [TemperatureChartPoint] {
        next24HourHourlyPrecipitationProbabilities.map { point in
            TemperatureChartPoint(time: point.time, temperature: point.probability)
        }
    }

    var next24HourPrecipitationChartTimeMarkers: [TimeMarker] {
        snapshot.currentObservationTime.map { [TimeMarker(kind: .current, time: $0)] } ?? []
    }

    var next24HourPrecipitationChartXDomain: ClosedRange<Date>? {
        next24HourTemperatureChartXDomain
    }

    var next24HourPrecipitationChartYDomain: ClosedRange<Double>? {
        guard !next24HourPrecipitationChartPoints.isEmpty else {
            return nil
        }

        return 0 ... 100
    }

    var next24HourWindChartPoints: [TemperatureChartPoint] {
        next24HourHourlyWindSpeeds.map { point in
            TemperatureChartPoint(time: point.time, temperature: displayWindSpeedValue(point.speed))
        }
    }

    var next24HourWindChartTimeMarkers: [TimeMarker] {
        snapshot.currentObservationTime.map { [TimeMarker(kind: .current, time: $0)] } ?? []
    }

    var next24HourWindChartXDomain: ClosedRange<Date>? {
        next24HourTemperatureChartXDomain
    }

    var next24HourWindChartYDomain: ClosedRange<Double>? {
        chartYDomain(for: next24HourWindChartPoints)
    }

    var next10DayForecastChartPoints: [DailyForecastChartPoint] {
        snapshot.dailyForecasts.prefix(5).map { forecast in
            DailyForecastChartPoint(
                date: forecast.date,
                highTemperature: displayTemperatureValue(forecast.highTemperature),
                lowTemperature: displayTemperatureValue(forecast.lowTemperature),
                precipitationProbability: forecast.precipitationProbability,
                condition: forecast.condition
            )
        }
    }

    var next10DayTemperatureChartYDomain: ClosedRange<Double>? {
        let values = next10DayForecastChartPoints.flatMap { [Double($0.highTemperature), Double($0.lowTemperature)] }
        guard !values.isEmpty else {
            return nil
        }

        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max(2, ceil((high - low) * 0.1))
        return (low - padding) ... (high + padding)
    }

    var chartTimeZoneIdentifier: String? {
        snapshot.timezoneIdentifier
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

    func refreshButtonHelpText(at referenceDate: Date) -> String {
        if isLoading {
            return L10n.tr("Weather is currently loading.")
        }

        guard let lastCheckAt else {
            return L10n.tr("Refresh weather")
        }

        let secondsSinceLastCheck = referenceDate.timeIntervalSince(lastCheckAt)
        if secondsSinceLastCheck < 60 {
            let remainingSeconds = max(1, Int((60 - secondsSinceLastCheck).rounded(.up)))
            return L10n.format("Refresh available in %lld seconds.", remainingSeconds)
        }

        return L10n.tr("Refresh weather")
    }

    func refreshWeather() async {
        await refreshWeather(after: nil)
    }

    private func refreshWeather(after initialDelay: Duration?) async {
        if let initialDelay {
            await sleep(initialDelay)

            if Task.isCancelled {
                return
            }
        }

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

    func selectLocation(at index: Int) {
        guard savedLocations.indices.contains(index), savedLocations[index] != nil else {
            return
        }

        selectedLocationIndex = index
        persistLocationState()
        resetForLocationChange()
    }

    func canDeleteLocation(at index: Int) -> Bool {
        guard savedLocations.indices.contains(index), savedLocations[index] != nil else {
            return false
        }

        return savedLocations.compactMap { $0 }.count > 1
    }

    func deleteLocation(at index: Int) {
        guard canDeleteLocation(at: index) else {
            return
        }

        let wasSelectedLocation = selectedLocationIndex == index
        savedLocations[index] = nil

        if wasSelectedLocation {
            selectedLocationIndex = savedLocations.firstIndex(where: { $0 != nil }) ?? 0
        }

        persistLocationState()

        if wasSelectedLocation {
            resetForLocationChange()
        }
    }

    func addLocation(at index: Int, name: String, latitudeText: String, longitudeText: String) throws {
        guard savedLocations.indices.contains(index) else {
            throw LocationInputError.invalidSlot
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw LocationInputError.emptyName
        }

        guard
            let latitude = Double(latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
            (-90 ... 90).contains(latitude)
        else {
            throw LocationInputError.invalidLatitude
        }

        guard
            let longitude = Double(longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
            (-180 ... 180).contains(longitude)
        else {
            throw LocationInputError.invalidLongitude
        }

        saveLocation(SavedLocation(name: trimmedName, latitude: latitude, longitude: longitude), at: index)
    }

    func detectCurrentLocation() async throws -> SavedLocation {
        try await deviceLocationProvider.detectLocation()
    }

    func searchLocation(query: String) async throws -> SavedLocation {
        try await searchLocationProvider.searchLocation(query: query)
    }

    func addDetectedLocation(_ location: SavedLocation, at index: Int) throws {
        guard savedLocations.indices.contains(index) else {
            throw LocationInputError.invalidSlot
        }

        saveLocation(location, at: index)
    }

    func toggleMenuPresentation() {
        isMenuPresented.toggle()
    }

    func formatLastCheckText(referenceDate: Date? = nil, using formatter: DateFormatter? = nil) -> String {
        guard let lastCheckAt else {
            return L10n.tr("Last checked: --")
        }

        let referenceDate = referenceDate ?? now()
        if referenceDate.timeIntervalSince(lastCheckAt) < 60 {
            return L10n.tr("Last checked: <1 min ago")
        }

        let formatter = formatter ?? Self.makeTimeFormatter(timeZoneIdentifier: nil)
        return L10n.format("Last checked: %@", formatter.string(from: lastCheckAt))
    }

    func formatSunriseText(using formatter: DateFormatter? = nil) -> String {
        L10n.format("Sunrise: %@", formatTime(snapshot.sunrise, using: formatter))
    }

    func formatSunsetText(using formatter: DateFormatter? = nil) -> String {
        L10n.format("Sunset: %@", formatTime(snapshot.sunset, using: formatter))
    }

    func formatWindText() -> String {
        L10n.format("Wind: %@", formatWindSpeedValue())
    }

    func formatHumidityText() -> String {
        L10n.format("Humidity: %@", formatPercent(snapshot.humidity))
    }

    func formatPrecipitationText() -> String {
        L10n.format("Precipitation: %@", formatPercent(snapshot.precipitationChance))
    }

    func temperatureChartMarkerLabel(for marker: TimeMarker) -> String {
        switch marker.kind {
        case .sunrise:
            return L10n.tr("Sunrise")
        case .current:
            return L10n.tr("Now")
        case .sunset:
            return L10n.tr("Sunset")
        }
    }

    func temperatureChartValueText(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        return "\(value)°"
    }

    func precipitationChartValueText(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        return "\(value)%"
    }

    func windChartValueText(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        return "\(value)"
    }

    var windChartUnitText: String {
        switch temperatureUnit {
        case .fahrenheit:
            return L10n.tr("mph")
        case .celsius:
            return L10n.tr("km/h")
        }
    }

    func temperatureChartTimeText(_ date: Date) -> String {
        let formatter = Self.makeChartMarkerTimeFormatter(timeZoneIdentifier: snapshot.timezoneIdentifier)
        return formatter.string(from: date)
    }

    func temperatureChartHourLabelText(_ date: Date) -> String {
        let hour = chartCalendar.component(.hour, from: date)

        if hour == 0 {
            return L10n.tr("Midnight")
        }

        if hour == 12 {
            return L10n.tr("Noon")
        }

        let displayHour = hour > 12 ? hour - 12 : hour
        return "\(displayHour)"
    }

    func next10DayLabelText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.appLocale
        formatter.timeZone = chartCalendar.timeZone
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    func next10DayDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.appLocale
        formatter.timeZone = chartCalendar.timeZone
        formatter.dateFormat = "E M/d"
        return formatter.string(from: date)
    }

    private func formatPercent(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        return "\(value)%"
    }

    private func formatWindSpeedValue() -> String {
        guard let windSpeed = snapshot.windSpeed else {
            return "--"
        }

        let displayedWindSpeed = displayWindSpeedValue(windSpeed)
        switch temperatureUnit {
        case .fahrenheit:
            return "\(displayedWindSpeed) \(L10n.tr("mph"))"
        case .celsius:
            return "\(displayedWindSpeed) \(L10n.tr("km/h"))"
        }
    }

    private func displayWindSpeedValue(_ value: Int) -> Int {
        switch temperatureUnit {
        case .fahrenheit:
            return value
        case .celsius:
            return Int((Double(value) * 1.60934).rounded())
        }
    }

    private var currentLocation: SavedLocation {
        savedLocations[selectedLocationIndex] ?? WeatherSettings.defaultPrimaryLocation
    }

    private func resetForLocationChange() {
        lastCheckAt = nil

        if settings.usesPlaceholderWeather {
            isLoading = false
            snapshot = .placeholder
            return
        }

        if let cachedEntry = cachedEntryForCurrentLocation() {
            isLoading = false
            snapshot = cachedEntry.snapshot
            lastCheckAt = cachedEntry.checkedAt
            startRefreshLoop(showLoadingState: false, initialDelay: cacheRefreshDelay(from: cachedEntry.checkedAt))
        } else {
            startRefreshLoop(showLoadingState: true)
        }
    }

    private func saveLocation(_ location: SavedLocation, at index: Int) {
        savedLocations[index] = location
        selectedLocationIndex = index
        persistLocationState()
        resetForLocationChange()
    }

    private func persistLocationState() {
        if let encodedLocations = try? JSONEncoder().encode(savedLocations) {
            defaults.set(encodedLocations, forKey: WeatherSettings.savedLocationsKey)
        }
        defaults.set(selectedLocationIndex, forKey: WeatherSettings.selectedLocationIndexKey)
        defaults.set(currentLocation.name, forKey: WeatherSettings.locationNameKey)
        defaults.set(currentLocation.latitude, forKey: WeatherSettings.latitudeKey)
        defaults.set(currentLocation.longitude, forKey: WeatherSettings.longitudeKey)
        defaults.synchronize()
    }

    private func startRefreshLoop(showLoadingState: Bool, initialDelay: Duration? = nil) {
        refreshTask?.cancel()

        if showLoadingState {
            isLoading = true
        }

        refreshTask = Task { [weak self] in
            await self?.refreshWeather(after: initialDelay)
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
            let location = currentLocation
            let snapshot = try await weatherService.fetchCurrentWeather(
                latitude: location.latitude,
                longitude: location.longitude
            )
            let checkedAt = now()
            lastCheckAt = checkedAt
            cache(snapshot: snapshot, checkedAt: checkedAt, for: location)
            return .success(snapshot)
        } catch let error as WeatherServiceError {
            lastCheckAt = now()
            return .failure(error)
        } catch {
            lastCheckAt = now()
            return .failure(.requestFailed)
        }
    }

    private func restoreCachedWeatherIfFreshForCurrentLocation() {
        if let cachedEntry = cachedEntryForCurrentLocation() {
            isLoading = false
            snapshot = cachedEntry.snapshot
            lastCheckAt = cachedEntry.checkedAt
            startRefreshLoop(showLoadingState: false, initialDelay: cacheRefreshDelay(from: cachedEntry.checkedAt))
        } else {
            startRefreshLoop(showLoadingState: false)
        }
    }

    private func cachedEntryForCurrentLocation(referenceDate: Date? = nil) -> CachedWeatherEntry? {
        cachedEntry(for: currentLocation, referenceDate: referenceDate)
    }

    private func cachedEntry(for location: SavedLocation, referenceDate: Date? = nil) -> CachedWeatherEntry? {
        let referenceDate = referenceDate ?? now()
        guard let entry = cachedWeatherByLocation[cacheKey(for: location)] else {
            return nil
        }

        guard referenceDate.timeIntervalSince(entry.checkedAt) < Self.cacheFreshnessInterval else {
            return nil
        }

        return entry
    }

    private func cacheRefreshDelay(from checkedAt: Date) -> Duration? {
        let age = now().timeIntervalSince(checkedAt)
        let remaining = Self.cacheFreshnessInterval - age
        guard remaining > 0 else {
            return nil
        }

        return .seconds(Int(remaining.rounded(.up)))
    }

    private func cache(snapshot: WeatherSnapshot, checkedAt: Date, for location: SavedLocation) {
        cachedWeatherByLocation[cacheKey(for: location)] = CachedWeatherEntry(snapshot: snapshot, checkedAt: checkedAt)
        persistCachedWeather()
    }

    private func persistCachedWeather() {
        if let data = try? JSONEncoder().encode(cachedWeatherByLocation) {
            defaults.set(data, forKey: WeatherSettings.cachedWeatherByLocationKey)
        }
    }

    private func cacheKey(for location: SavedLocation) -> String {
        "\(location.name)|\(location.latitude)|\(location.longitude)"
    }

    private static func decodeCachedWeather(from data: Data?) -> [String: CachedWeatherEntry]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([String: CachedWeatherEntry].self, from: data)
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

        return "\(displayTemperatureValue(value))°"
    }

    private func displayTemperatureValue(_ value: Int) -> Int {
        switch temperatureUnit {
        case .fahrenheit:
            return value
        case .celsius:
            return Int((((Double(value) - 32) * 5) / 9).rounded())
        }
    }

    private func roundedDownToThreeHourBoundary(_ date: Date) -> Date? {
        var components = chartCalendar.dateComponents([.year, .month, .day, .hour], from: date)
        components.hour = ((components.hour ?? 0) / 3) * 3
        components.minute = 0
        components.second = 0
        return chartCalendar.date(from: components)
    }

    private var currentDayHourlyTemperatures: [WeatherSnapshot.HourlyTemperature] {
        guard
            let domain = temperatureChartXDomain
        else {
            return snapshot.hourlyTemperatures
        }

        return snapshot.hourlyTemperatures.filter {
            domain.contains($0.time)
        }
    }

    private var next24HourHourlyTemperatures: [WeatherSnapshot.HourlyTemperature] {
        guard let domain = next24HourTemperatureChartXDomain else {
            return []
        }

        return snapshot.hourlyTemperatures.filter { domain.contains($0.time) }
    }

    private var next24HourHourlyPrecipitationProbabilities: [WeatherSnapshot.HourlyPrecipitationProbability] {
        guard let domain = next24HourPrecipitationChartXDomain else {
            return []
        }

        return snapshot.hourlyPrecipitationProbabilities.filter { domain.contains($0.time) }
    }

    private var next24HourHourlyWindSpeeds: [WeatherSnapshot.HourlyWindSpeed] {
        guard let domain = next24HourWindChartXDomain else {
            return []
        }

        return snapshot.hourlyWindSpeeds.filter { domain.contains($0.time) }
    }

    private func chartYDomain(for points: [TemperatureChartPoint]) -> ClosedRange<Double>? {
        let values = points.map(\.temperature)
        guard !values.isEmpty else {
            return nil
        }

        let low = Double(values.min() ?? 0)
        let high = Double(values.max() ?? 0)
        let padding = max(2, ceil((high - low) * 0.1))
        return (low - padding) ... (high + padding)
    }

    private func formatTime(_ value: Date?, using formatter: DateFormatter? = nil) -> String {
        guard let value else {
            return "--"
        }

        let formatter = formatter ?? Self.makeTimeFormatter(timeZoneIdentifier: snapshot.timezoneIdentifier)
        return formatter.string(from: value)
    }

    private func formatRelativeDayTime(_ value: Date?) -> String {
        guard let value else {
            return "--"
        }

        let timeText = formatTime(value)

        guard let referenceDate = snapshot.currentObservationTime else {
            return timeText
        }

        if chartCalendar.isDate(value, inSameDayAs: referenceDate) {
            return "\(timeText) \(L10n.tr("Today"))"
        }

        if let tomorrow = chartCalendar.date(byAdding: .day, value: 1, to: referenceDate),
           chartCalendar.isDate(value, inSameDayAs: tomorrow) {
            return "\(timeText) \(L10n.tr("Tomorrow"))"
        }

        return timeText
    }

    private var next24HourSunriseTime: Date? {
        guard let domain = next24HourTemperatureChartXDomain else {
            return nil
        }

        return snapshot.sunriseTimes.first(where: { domain.contains($0) })
    }

    private var next24HourSunsetTime: Date? {
        guard let domain = next24HourTemperatureChartXDomain else {
            return nil
        }

        return snapshot.sunsetTimes.first(where: { domain.contains($0) })
    }

    private static func makeTimeFormatter(timeZoneIdentifier: String?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = timeZone
        }
        return formatter
    }

    private static func makeChartMarkerTimeFormatter(timeZoneIdentifier: String?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateStyle = .none
        formatter.dateFormat = "h:mm a"
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = timeZone
        }
        return formatter
    }

    private static var appLocale: Locale {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("--ui-testing") || processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return Locale(identifier: "en_US_POSIX")
        }

        return Locale.autoupdatingCurrent
    }

    private var chartCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier = snapshot.timezoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }
}
