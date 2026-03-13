import CoreLocation
import Foundation
import ServiceManagement

struct WeatherSnapshot: Codable, Equatable {
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
struct LocationSlot: Identifiable, Equatable {
    let index: Int
    let location: SavedLocation?

    var id: Int { index }

    var title: String {
        location?.name ?? "Add Location"
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
            return "Enter a location name."
        case .invalidLatitude:
            return "Enter a latitude between -90 and 90."
        case .invalidLongitude:
            return "Enter a longitude between -180 and 180."
        case .invalidSlot:
            return "Unable to save this location slot."
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
            throw LocationInputError.detectionFailed("Enter a ZIP code or city name to search.")
        }

        let placemarks = try await geocoder.geocodeAddressString(trimmedQuery)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw LocationInputError.detectionFailed("No matching location was found.")
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
            throw LocationInputError.detectionFailed("Allow location access in System Settings to detect your current location.")
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
            continuation?.resume(throwing: LocationInputError.detectionFailed("Unable to determine your current location."))
            continuation = nil
            return
        }

        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: LocationInputError.detectionFailed("Unable to determine your current location."))
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(throwing: LocationInputError.detectionFailed("Allow location access in System Settings to detect your current location."))
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
