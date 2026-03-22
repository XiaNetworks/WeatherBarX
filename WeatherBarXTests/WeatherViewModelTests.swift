import XCTest
import SwiftUI
@testable import WeatherBarX

private final class FixtureBundleToken {}

private func fixture(named name: String) -> Data {
    let bundle = Bundle(for: FixtureBundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
        XCTFail("Missing fixture: \(name).json")
        return Data()
    }

    do {
        return try Data(contentsOf: url)
    } catch {
        XCTFail("Failed to load fixture: \(name).json")
        return Data()
    }
}

@MainActor
final class WeatherViewModelTests: XCTestCase {
    private var originalAppleLanguages: Any?
    private var originalAppleLocale: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        originalAppleLanguages = defaults.object(forKey: "AppleLanguages")
        originalAppleLocale = defaults.object(forKey: "AppleLocale")
        defaults.set(["en"], forKey: "AppleLanguages")
        defaults.set("en_US_POSIX", forKey: "AppleLocale")
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        if let originalAppleLanguages {
            defaults.set(originalAppleLanguages, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        if let originalAppleLocale {
            defaults.set(originalAppleLocale, forKey: "AppleLocale")
        } else {
            defaults.removeObject(forKey: "AppleLocale")
        }
        originalAppleLanguages = nil
        originalAppleLocale = nil
        super.tearDown()
    }

    func testJSONResponseDecodesIntoWeatherModelCorrectly() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: fixture(named: "current-cloudy-day"))

        XCTAssertEqual(snapshot.temperature, 72)
        XCTAssertEqual(snapshot.summary, "Cloudy")
        XCTAssertEqual(snapshot.condition, .cloudy)
        XCTAssertTrue(snapshot.isDaylight)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "h:mm a"

        XCTAssertEqual(snapshot.highTemperature, 76)
        XCTAssertEqual(snapshot.highTemperatureAt.map(formatter.string(from:)), "3:00 PM")
        XCTAssertEqual(snapshot.lowTemperature, 61)
        XCTAssertEqual(snapshot.lowTemperatureAt.map(formatter.string(from:)), "3:00 AM")
        XCTAssertEqual(snapshot.sunrise.map(formatter.string(from:)), "7:15 AM")
        XCTAssertEqual(snapshot.sunset.map(formatter.string(from:)), "7:05 PM")
        XCTAssertEqual(snapshot.currentObservationTime.map(formatter.string(from:)), "2:00 PM")
        XCTAssertEqual(snapshot.hourlyTemperatures.count, 8)
        XCTAssertEqual(snapshot.hourlyTemperatures.first?.temperature, 61)
        XCTAssertEqual(snapshot.hourlyTemperatures.last?.temperature, 68)
    }

    func testSunriseSunsetPayloadUsesDayIconDuringDaylight() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: fixture(named: "current-clear-day"))

        XCTAssertTrue(snapshot.isDaylight)
        XCTAssertEqual(snapshot.condition.iconName(isDaylight: snapshot.isDaylight), "sun.max.fill")
    }

    func testSunriseSunsetPayloadUsesNightIconAfterSunset() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: fixture(named: "current-clear-night"))

        XCTAssertFalse(snapshot.isDaylight)
        XCTAssertEqual(snapshot.condition.iconName(isDaylight: snapshot.isDaylight), "moon.stars.fill")
    }

    func testSunriseSunsetPayloadTreatsSunsetAsNightBoundary() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: fixture(named: "current-sunset-boundary"))

        XCTAssertFalse(snapshot.isDaylight)
        XCTAssertEqual(snapshot.condition.iconName(isDaylight: snapshot.isDaylight), "cloud.moon.fill")
    }

    func testWeatherServiceReturnsParsedDomainModelFromSamplePayload() async throws {
        URLProtocolStub.responseProvider = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.open-meteo.com/v1/forecast")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return .success((response, fixture(named: "current-rain")))
        }

        let snapshot = try await makeWeatherService().fetchCurrentWeather(latitude: 38.9072, longitude: -77.0369)

        XCTAssertEqual(snapshot.temperature, 71)
        XCTAssertEqual(snapshot.condition, .rain)
        XCTAssertEqual(snapshot.summary, "Rain")
        XCTAssertEqual(snapshot.windSpeed, 12)
        XCTAssertEqual(snapshot.humidity, 68)
        XCTAssertEqual(snapshot.precipitationChance, 55)
        XCTAssertTrue(snapshot.isDaylight)
    }

    func testWeatherServiceReturnsNetworkUnavailableOnTimeout() async {
        URLProtocolStub.responseProvider = { _ in
            .failure(URLError(.timedOut))
        }

        await XCTAssertThrowsErrorAsync(try await makeWeatherService().fetchCurrentWeather(latitude: 38.9072, longitude: -77.0369)) { error in
            XCTAssertEqual(error as? WeatherServiceError, .networkUnavailable)
        }
    }

    func testWeatherServiceReturnsNetworkUnavailableWhenOffline() async {
        URLProtocolStub.responseProvider = { _ in
            .failure(URLError(.notConnectedToInternet))
        }

        await XCTAssertThrowsErrorAsync(try await makeWeatherService().fetchCurrentWeather(latitude: 38.9072, longitude: -77.0369)) { error in
            XCTAssertEqual(error as? WeatherServiceError, .networkUnavailable)
        }
    }

    func testWeatherServiceReturnsRequestFailedForBadHTTPStatus() async {
        URLProtocolStub.responseProvider = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.open-meteo.com/v1/forecast")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return .success((response, Data()))
        }

        await XCTAssertThrowsErrorAsync(try await makeWeatherService().fetchCurrentWeather(latitude: 38.9072, longitude: -77.0369)) { error in
            XCTAssertEqual(error as? WeatherServiceError, .requestFailed)
        }
    }

    func testTemperatureConversionLogicIsCorrect() {
        XCTAssertEqual(OpenMeteoWeatherService.roundedTemperature(from: 72.4), 72)
        XCTAssertEqual(OpenMeteoWeatherService.roundedTemperature(from: 72.5), 73)
        XCTAssertEqual(OpenMeteoWeatherService.roundedTemperature(from: -1.6), -2)
    }

    func testWeatherConditionMappingWorksForClear() {
        let condition = WeatherCondition(weatherCode: 0, isDaylight: true)

        XCTAssertEqual(condition, .clear)
        XCTAssertEqual(condition.iconName(isDaylight: true), "sun.max.fill")
    }

    func testWeatherConditionMappingWorksForCloudy() {
        let condition = WeatherCondition(weatherCode: 3, isDaylight: true)

        XCTAssertEqual(condition, .cloudy)
        XCTAssertEqual(condition.iconName(isDaylight: true), "cloud.fill")
    }

    func testWeatherConditionMappingWorksForRain() {
        let condition = WeatherCondition(weatherCode: 61, isDaylight: true)

        XCTAssertEqual(condition, .rain)
        XCTAssertEqual(condition.iconName(isDaylight: true), "cloud.rain.fill")
    }

    func testWeatherConditionMappingWorksForSnow() {
        let condition = WeatherCondition(weatherCode: 71, isDaylight: true)

        XCTAssertEqual(condition, .snow)
        XCTAssertEqual(condition.iconName(isDaylight: true), "cloud.snow.fill")
    }

    func testFailedNetworkResponseProducesErrorState() async {
        let service = SequencedWeatherService(results: [
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
        ])
        let sleepRecorder = SleepRecorder()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [.seconds(10), .seconds(20), .seconds(30)],
            postErrorRetryDelays: [],
            sleep: { duration in
                await sleepRecorder.record(duration)
            }
        )

        await viewModel.refreshWeather()

        let recordedSleeps = await sleepRecorder.values
        XCTAssertEqual(recordedSleeps, [.seconds(10), .seconds(20), .seconds(30)])
        XCTAssertEqual(viewModel.conditionIconName, "wifi.slash")
        XCTAssertEqual(viewModel.temperatureText, "--")
        XCTAssertEqual(viewModel.summaryText, "Network unavailable")
    }

    func testStaleOrMissingDataIsHandledSafely() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: fixture(named: "current-missing-sunrise"))

        XCTAssertEqual(snapshot.temperature, 64)
        XCTAssertEqual(snapshot.condition, .clear)
        XCTAssertTrue(snapshot.isDaylight)
        XCTAssertEqual(snapshot.summary, "Clear sky")
    }

    func testDecodeFailsForMalformedAPIResponse() {
        let malformedData = fixture(named: "error-response")

        XCTAssertThrowsError(try OpenMeteoWeatherService.decodeSnapshot(from: malformedData)) { error in
            XCTAssertEqual(error as? WeatherServiceError, .decodeFailed)
        }
    }

    func testPlaceholderTemperatureFormatsCorrectly() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.temperatureText, "72°")
    }

    func testDefaultLocationSlotsIncludeWashingtonNorthPoleAndSouthPole() {
        let settings = WeatherSettings(defaults: makeDefaults())

        XCTAssertEqual(settings.savedLocations.count, 3)
        XCTAssertEqual(settings.savedLocations[0], WeatherSettings.defaultPrimaryLocation)
        XCTAssertEqual(settings.savedLocations[1], WeatherSettings.defaultNorthPoleLocation)
        XCTAssertEqual(settings.savedLocations[2], WeatherSettings.defaultSouthPoleLocation)
        XCTAssertEqual(settings.selectedLocationIndex, 0)
    }

    func testDetectCurrentLocationReturnsProviderLocation() async throws {
        let detectedLocation = SavedLocation(name: "Cupertino, CA", latitude: 37.3318, longitude: -122.0312)
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            deviceLocationProvider: MockDeviceLocationProvider(result: .success(detectedLocation)),
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        let location = try await viewModel.detectCurrentLocation()

        XCTAssertEqual(location, detectedLocation)
    }

    func testSearchLocationReturnsProviderLocation() async throws {
        let searchedLocation = SavedLocation(name: "San Francisco, CA", latitude: 37.7749, longitude: -122.4194)
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            searchLocationProvider: MockSearchLocationProvider(result: .success(searchedLocation)),
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        let location = try await viewModel.searchLocation(query: "94103")

        XCTAssertEqual(location, searchedLocation)
    }

    func testDetectedLocationCanBeSavedIntoSlot() throws {
        let defaults = makeDefaults()
        let detectedLocation = SavedLocation(name: "Cupertino, CA", latitude: 37.3318, longitude: -122.0312)
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        try viewModel.addDetectedLocation(detectedLocation, at: 1)

        XCTAssertEqual(viewModel.locationName, "Cupertino, CA")
        XCTAssertEqual(viewModel.savedLocations[1], detectedLocation)
        XCTAssertEqual(WeatherSettings(defaults: defaults).savedLocations[1], detectedLocation)
    }

    func testAddingLocationToEmptySlotPersistsAndSelectsIt() throws {
        let defaults = makeDefaults()
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        try viewModel.addLocation(at: 1, name: "New York, NY", latitudeText: "40.7128", longitudeText: "-74.0060")

        XCTAssertEqual(viewModel.locationName, "New York, NY")
        XCTAssertEqual(viewModel.selectedLocationIndex, 1)
        XCTAssertEqual(viewModel.savedLocations[1], SavedLocation(name: "New York, NY", latitude: 40.7128, longitude: -74.0060))

        let reloadedSettings = WeatherSettings(defaults: defaults)
        XCTAssertEqual(reloadedSettings.selectedLocationIndex, 1)
        XCTAssertEqual(reloadedSettings.savedLocations[1], SavedLocation(name: "New York, NY", latitude: 40.7128, longitude: -74.0060))
    }

    func testSelectingSavedAlternateLocationUpdatesCurrentLocation() throws {
        let defaults = makeDefaults()
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        try viewModel.addLocation(at: 1, name: "Boston, MA", latitudeText: "42.3601", longitudeText: "-71.0589")
        viewModel.selectLocation(at: 0)

        XCTAssertEqual(viewModel.locationName, "Washington, DC")
        XCTAssertEqual(viewModel.selectedLocationIndex, 0)

        let reloadedSettings = WeatherSettings(defaults: defaults)
        XCTAssertEqual(reloadedSettings.selectedLocationIndex, 0)
        XCTAssertEqual(reloadedSettings.locationName, "Washington, DC")
    }

    func testSelectingLocationUsesFreshCachedWeatherBeforeFetching() async {
        let defaults = makeDefaults()
        let cachedSnapshot = WeatherSnapshot(
            summary: "Cloudy",
            temperature: 44,
            condition: .cloudy,
            isDaylight: true,
            sunrise: nil,
            sunset: nil,
            highTemperature: 49,
            highTemperatureAt: nil,
            lowTemperature: 38,
            lowTemperatureAt: nil
        )
        let cachedAt = Date(timeIntervalSince1970: 1_731_447_600)
        let clock = MutableNowBox(cachedAt.addingTimeInterval(5 * 60))
        let service = CountingWeatherService(snapshotByCoordinate: [
            coordinateKey(latitude: WeatherSettings.defaultLatitude, longitude: WeatherSettings.defaultLongitude): .placeholder,
        ])
        persistCachedWeather(defaults: defaults, entries: [
            cacheKey(for: WeatherSettings.defaultPrimaryLocation): CachedWeatherEntry(snapshot: cachedSnapshot, checkedAt: cachedAt),
        ])
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            now: { clock.current }
        )

        viewModel.selectLocation(at: 0)

        let fetchCount = await service.fetchCount(latitude: WeatherSettings.defaultLatitude, longitude: WeatherSettings.defaultLongitude)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.summaryText, "Cloudy")
        XCTAssertEqual(viewModel.temperatureText, "44°")
        XCTAssertEqual(fetchCount, 0)
    }

    func testSelectingLocationFetchesWhenCachedWeatherIsOlderThanFifteenMinutes() async {
        let defaults = makeDefaults()
        let staleSnapshot = WeatherSnapshot(
            summary: "Cloudy",
            temperature: 44,
            condition: .cloudy,
            isDaylight: true,
            sunrise: nil,
            sunset: nil,
            highTemperature: 49,
            highTemperatureAt: nil,
            lowTemperature: 38,
            lowTemperatureAt: nil
        )
        let freshSnapshot = WeatherSnapshot(
            summary: "Clear sky",
            temperature: 51,
            condition: .clear,
            isDaylight: true,
            sunrise: nil,
            sunset: nil,
            highTemperature: 55,
            highTemperatureAt: nil,
            lowTemperature: 40,
            lowTemperatureAt: nil
        )
        let cachedAt = Date(timeIntervalSince1970: 1_731_447_600)
        let clock = MutableNowBox(cachedAt.addingTimeInterval(16 * 60))
        let service = CountingWeatherService(snapshotByCoordinate: [
            coordinateKey(latitude: WeatherSettings.defaultLatitude, longitude: WeatherSettings.defaultLongitude): freshSnapshot,
        ])
        persistCachedWeather(defaults: defaults, entries: [
            cacheKey(for: WeatherSettings.defaultPrimaryLocation): CachedWeatherEntry(snapshot: staleSnapshot, checkedAt: cachedAt),
        ])
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [],
            postErrorRetryDelays: [],
            successRefreshDelay: { .seconds(600) },
            now: { clock.current }
        )

        viewModel.selectLocation(at: 0)
        await waitUntil { !viewModel.isLoading }
        let fetchCount = await service.fetchCount(latitude: WeatherSettings.defaultLatitude, longitude: WeatherSettings.defaultLongitude)

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(viewModel.summaryText, "Clear sky")
        XCTAssertEqual(viewModel.temperatureText, "51°")
    }

    func testDeletingSavedAlternateLocationClearsItsSlotAndPersists() {
        let defaults = makeDefaults()
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertTrue(viewModel.canDeleteLocation(at: 1))

        viewModel.deleteLocation(at: 1)

        XCTAssertNil(viewModel.savedLocations[1])
        let persistedData = defaults.data(forKey: WeatherSettings.savedLocationsKey)
        XCTAssertNotNil(persistedData)
        let persistedLocations = persistedData.flatMap { try? JSONDecoder().decode([SavedLocation?].self, from: $0) }
        XCTAssertNotNil(persistedLocations)
        XCTAssertNil(persistedLocations?[1])

        let reloadedSettings = WeatherSettings(defaults: defaults)
        XCTAssertNil(reloadedSettings.savedLocations[1])
    }

    func testDeletingPrimaryLocationPersistsWhenAnotherLocationIsSelected() {
        let defaults = makeDefaults()
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        viewModel.selectLocation(at: 1)
        XCTAssertTrue(viewModel.canDeleteLocation(at: 0))

        viewModel.deleteLocation(at: 0)

        XCTAssertNil(viewModel.savedLocations[0])
        XCTAssertEqual(viewModel.selectedLocationIndex, 1)

        let persistedData = defaults.data(forKey: WeatherSettings.savedLocationsKey)
        XCTAssertNotNil(persistedData)
        let persistedLocations = persistedData.flatMap { try? JSONDecoder().decode([SavedLocation?].self, from: $0) }
        XCTAssertNotNil(persistedLocations)
        XCTAssertNil(persistedLocations?[0])

        let reloadedSettings = WeatherSettings(defaults: defaults)
        XCTAssertNil(reloadedSettings.savedLocations[0])
        XCTAssertEqual(reloadedSettings.savedLocations[1], WeatherSettings.defaultNorthPoleLocation)
        XCTAssertEqual(reloadedSettings.selectedLocationIndex, 1)
    }

    func testLaunchAtLoginToggleUpdatesButtonState() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: WeatherSettings.hasInitializedLaunchAtLoginKey)
        let launchAtLoginManager = MockLaunchAtLoginManager(isEnabled: false)
        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            launchAtLoginManager: launchAtLoginManager,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertFalse(viewModel.isLaunchAtLoginEnabled)

        viewModel.toggleLaunchAtLogin()

        XCTAssertTrue(viewModel.isLaunchAtLoginEnabled)
        XCTAssertEqual(launchAtLoginManager.setEnabledCalls, [true])
    }

    func testFirstLaunchEnablesLaunchAtLoginByDefault() {
        let defaults = makeDefaults()
        let launchAtLoginManager = MockLaunchAtLoginManager(isEnabled: false)

        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            launchAtLoginManager: launchAtLoginManager,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertTrue(viewModel.isLaunchAtLoginEnabled)
        XCTAssertEqual(launchAtLoginManager.setEnabledCalls, [true])
        XCTAssertTrue(defaults.bool(forKey: WeatherSettings.hasInitializedLaunchAtLoginKey))
    }

    func testSubsequentLaunchDoesNotReenableLaunchAtLogin() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: WeatherSettings.hasInitializedLaunchAtLoginKey)
        let launchAtLoginManager = MockLaunchAtLoginManager(isEnabled: false)

        let viewModel = WeatherViewModel(
            defaults: defaults,
            snapshot: .placeholder,
            launchAtLoginManager: launchAtLoginManager,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertFalse(viewModel.isLaunchAtLoginEnabled)
        XCTAssertTrue(launchAtLoginManager.setEnabledCalls.isEmpty)
    }

    func testTemperatureUnitToggleConvertsDisplayedTemperatures() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.temperatureUnitButtonText, "°F")
        XCTAssertEqual(viewModel.temperatureText, "72°")
        XCTAssertEqual(viewModel.highDetailText, "High: 76° at --")
        XCTAssertEqual(viewModel.lowDetailText, "Low: 64° at --")
        XCTAssertEqual(viewModel.windInlineText, "--")

        viewModel.toggleTemperatureUnit()

        XCTAssertEqual(viewModel.temperatureUnitButtonText, "°C")
        XCTAssertEqual(viewModel.temperatureText, "22°")
        XCTAssertEqual(viewModel.highDetailText, "High: 24° at --")
        XCTAssertEqual(viewModel.lowDetailText, "Low: 18° at --")
        XCTAssertEqual(viewModel.windInlineText, "--")
    }

    func testTemperatureChartPointsConvertWithSelectedUnit() {
        let lowTime = Date(timeIntervalSince1970: 1_731_447_600)
        let currentTime = Date(timeIntervalSince1970: 1_731_451_200)
        let highTime = Date(timeIntervalSince1970: 1_731_454_800)
        let snapshot = WeatherSnapshot(
            summary: "Cloudy",
            temperature: 72,
            condition: .cloudy,
            isDaylight: true,
            timezoneIdentifier: "America/New_York",
            currentObservationTime: currentTime,
            sunrise: nil,
            sunset: nil,
            highTemperature: 76,
            highTemperatureAt: highTime,
            lowTemperature: 64,
            lowTemperatureAt: lowTime,
            hourlyTemperatures: [
                .init(time: lowTime, temperature: 64),
                .init(time: currentTime, temperature: 72),
                .init(time: highTime, temperature: 76),
            ]
        )
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: snapshot,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertEqual(viewModel.temperatureChartPoints.map(\.temperature), [64, 72, 76])
        XCTAssertEqual(viewModel.temperatureChartHigh, 76)
        XCTAssertEqual(viewModel.temperatureChartHighAt, highTime)
        XCTAssertEqual(viewModel.temperatureChartLow, 64)
        XCTAssertEqual(viewModel.temperatureChartLowAt, lowTime)

        viewModel.toggleTemperatureUnit()

        XCTAssertEqual(viewModel.temperatureChartPoints.map(\.temperature), [18, 22, 24])
        XCTAssertEqual(viewModel.temperatureChartHigh, 24)
        XCTAssertEqual(viewModel.temperatureChartHighAt, highTime)
        XCTAssertEqual(viewModel.temperatureChartLow, 18)
        XCTAssertEqual(viewModel.temperatureChartLowAt, lowTime)
    }

    func testTodayAndNext24HourTemperatureChartsUseDifferentRanges() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let todayEarly = formatter.date(from: "2024-11-11 00:00")!
        let currentTime = formatter.date(from: "2024-11-11 14:00")!
        let todayLate = formatter.date(from: "2024-11-11 23:00")!
        let tomorrowMidnight = formatter.date(from: "2024-11-12 00:00")!
        let tomorrowMorning = formatter.date(from: "2024-11-12 08:00")!
        let tomorrowNoon = formatter.date(from: "2024-11-12 12:00")!
        let tomorrowLate = formatter.date(from: "2024-11-12 15:00")!
        let nextSunrise = formatter.date(from: "2024-11-12 07:00")!
        let nextSunset = formatter.date(from: "2024-11-12 17:00")!

        let snapshot = WeatherSnapshot(
            summary: "Cloudy",
            temperature: 72,
            condition: .cloudy,
            isDaylight: true,
            timezoneIdentifier: "America/New_York",
            currentObservationTime: currentTime,
            sunrise: formatter.date(from: "2024-11-11 06:45"),
            sunset: formatter.date(from: "2024-11-11 17:05"),
            sunriseTimes: [
                formatter.date(from: "2024-11-11 06:45")!,
                nextSunrise,
            ],
            sunsetTimes: [
                formatter.date(from: "2024-11-11 17:05")!,
                nextSunset,
            ],
            highTemperature: 76,
            highTemperatureAt: todayLate,
            lowTemperature: 64,
            lowTemperatureAt: todayEarly,
            hourlyTemperatures: [
                .init(time: todayEarly, temperature: 64),
                .init(time: currentTime, temperature: 72),
                .init(time: todayLate, temperature: 76),
                .init(time: tomorrowMidnight, temperature: 71),
                .init(time: tomorrowMorning, temperature: 67),
                .init(time: tomorrowNoon, temperature: 70),
                .init(time: tomorrowLate, temperature: 73),
            ]
        )

        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: snapshot,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertEqual(viewModel.temperatureChartXDomain?.lowerBound, formatter.date(from: "2024-11-11 00:00"))
        XCTAssertEqual(viewModel.temperatureChartXDomain?.upperBound, formatter.date(from: "2024-11-12 00:00"))
        XCTAssertEqual(viewModel.temperatureChartPoints.map(\.time), [todayEarly, currentTime, todayLate, tomorrowMidnight])
        XCTAssertEqual(viewModel.next24HourTemperatureChartXDomain?.lowerBound, formatter.date(from: "2024-11-11 12:00"))
        XCTAssertEqual(viewModel.next24HourTemperatureChartXDomain?.upperBound, formatter.date(from: "2024-11-12 12:00"))
        XCTAssertEqual(viewModel.next24HourTemperatureChartPoints.map(\.time), [currentTime, todayLate, tomorrowMidnight, tomorrowMorning, tomorrowNoon])
        XCTAssertEqual(viewModel.next24HourTemperatureChartHigh, 76)
        XCTAssertEqual(viewModel.next24HourTemperatureChartHighAt, todayLate)
        XCTAssertEqual(viewModel.next24HourTemperatureChartLow, 67)
        XCTAssertEqual(viewModel.next24HourTemperatureChartLowAt, tomorrowMorning)
        XCTAssertEqual(
            viewModel.next24HourTemperatureChartTimeMarkers.map(\.time),
            [currentTime, formatter.date(from: "2024-11-11 17:05")!, nextSunrise]
        )
        XCTAssertEqual(normalizedWhitespace(viewModel.next24HourHighDetailText), "High: 76° at 11:00 PM Today")
        XCTAssertEqual(normalizedWhitespace(viewModel.next24HourLowDetailText), "Low: 67° at 8:00 AM Tomorrow")
        XCTAssertEqual(normalizedWhitespace(viewModel.next24HourSunriseText), "Sunrise: 7:00 AM Tomorrow")
        XCTAssertEqual(normalizedWhitespace(viewModel.next24HourSunsetText), "Sunset: 5:05 PM Today")
    }

    func testNext24HourPrecipitationChartUsesRollingWindow() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let currentTime = formatter.date(from: "2024-11-11 14:00")!
        let todayLate = formatter.date(from: "2024-11-11 23:00")!
        let tomorrowMorning = formatter.date(from: "2024-11-12 08:00")!
        let tomorrowNoon = formatter.date(from: "2024-11-12 12:00")!
        let tomorrowLate = formatter.date(from: "2024-11-12 15:00")!

        let snapshot = WeatherSnapshot(
            summary: "Cloudy",
            temperature: 72,
            condition: .cloudy,
            isDaylight: true,
            timezoneIdentifier: "America/New_York",
            currentObservationTime: currentTime,
            sunrise: nil,
            sunset: nil,
            highTemperature: nil,
            highTemperatureAt: nil,
            lowTemperature: nil,
            lowTemperatureAt: nil,
            hourlyPrecipitationProbabilities: [
                .init(time: formatter.date(from: "2024-11-11 11:00")!, probability: 25),
                .init(time: currentTime, probability: 40),
                .init(time: todayLate, probability: 55),
                .init(time: tomorrowMorning, probability: 35),
                .init(time: tomorrowNoon, probability: 60),
                .init(time: tomorrowLate, probability: 20),
            ]
        )

        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: snapshot,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertEqual(viewModel.next24HourPrecipitationChartXDomain?.lowerBound, formatter.date(from: "2024-11-11 12:00"))
        XCTAssertEqual(viewModel.next24HourPrecipitationChartXDomain?.upperBound, formatter.date(from: "2024-11-12 12:00"))
        XCTAssertEqual(viewModel.next24HourPrecipitationChartPoints.map(\.temperature), [40, 55, 35, 60])
        XCTAssertEqual(viewModel.next24HourPrecipitationChartPoints.map(\.time), [currentTime, todayLate, tomorrowMorning, tomorrowNoon])
        XCTAssertEqual(viewModel.next24HourPrecipitationChartYDomain, 0 ... 100)
        XCTAssertEqual(viewModel.next24HourPrecipitationChartTimeMarkers.map(\.time), [currentTime])
    }

    func testNext24HourWindChartUsesRollingWindow() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let currentTime = formatter.date(from: "2024-11-11 14:00")!
        let todayLate = formatter.date(from: "2024-11-11 23:00")!
        let tomorrowMorning = formatter.date(from: "2024-11-12 08:00")!
        let tomorrowNoon = formatter.date(from: "2024-11-12 12:00")!
        let tomorrowLate = formatter.date(from: "2024-11-12 15:00")!

        let snapshot = WeatherSnapshot(
            summary: "Cloudy",
            temperature: 72,
            condition: .cloudy,
            isDaylight: true,
            timezoneIdentifier: "America/New_York",
            currentObservationTime: currentTime,
            sunrise: nil,
            sunset: nil,
            highTemperature: nil,
            highTemperatureAt: nil,
            lowTemperature: nil,
            lowTemperatureAt: nil,
            hourlyWindSpeeds: [
                .init(time: formatter.date(from: "2024-11-11 11:00")!, speed: 8),
                .init(time: currentTime, speed: 12),
                .init(time: todayLate, speed: 10),
                .init(time: tomorrowMorning, speed: 14),
                .init(time: tomorrowNoon, speed: 9),
                .init(time: tomorrowLate, speed: 6),
            ]
        )

        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: snapshot,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertEqual(viewModel.next24HourWindChartXDomain?.lowerBound, formatter.date(from: "2024-11-11 12:00"))
        XCTAssertEqual(viewModel.next24HourWindChartXDomain?.upperBound, formatter.date(from: "2024-11-12 12:00"))
        XCTAssertEqual(viewModel.next24HourWindChartPoints.map(\.temperature), [12, 10, 14, 9])
        XCTAssertEqual(viewModel.next24HourWindChartPoints.map(\.time), [currentTime, todayLate, tomorrowMorning, tomorrowNoon])
        XCTAssertEqual(viewModel.next24HourWindChartTimeMarkers.map(\.time), [currentTime])

        viewModel.toggleTemperatureUnit()

        XCTAssertEqual(viewModel.next24HourWindChartPoints.map(\.temperature), [19, 16, 23, 14])
    }

    func testNext10DayForecastChartPointsConvertWithSelectedUnit() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"

        let snapshot = WeatherSnapshot(
            summary: "Cloudy",
            temperature: 72,
            condition: .cloudy,
            isDaylight: true,
            timezoneIdentifier: "America/New_York",
            currentObservationTime: formatter.date(from: "2024-11-11"),
            sunrise: nil,
            sunset: nil,
            highTemperature: nil,
            highTemperatureAt: nil,
            lowTemperature: nil,
            lowTemperatureAt: nil,
            dailyForecasts: [
                .init(date: formatter.date(from: "2024-11-11")!, highTemperature: 70, lowTemperature: 55, precipitationProbability: 20, condition: .cloudy),
                .init(date: formatter.date(from: "2024-11-12")!, highTemperature: 74, lowTemperature: 58, precipitationProbability: 45, condition: .rain),
            ]
        )

        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: snapshot,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )

        XCTAssertEqual(viewModel.next10DayForecastChartPoints.map(\.highTemperature), [70, 74])
        XCTAssertEqual(viewModel.next10DayForecastChartPoints.map(\.lowTemperature), [55, 58])
        XCTAssertEqual(viewModel.next10DayForecastChartPoints.map(\.precipitationProbability), [20, 45])
        XCTAssertEqual(viewModel.next10DayForecastChartPoints.map(\.condition), [.cloudy, .rain])

        viewModel.toggleTemperatureUnit()

        XCTAssertEqual(viewModel.next10DayForecastChartPoints.map(\.highTemperature), [21, 23])
        XCTAssertEqual(viewModel.next10DayForecastChartPoints.map(\.lowTemperature), [13, 14])
        XCTAssertEqual(viewModel.next10DayForecastChartPoints.map(\.precipitationProbability), [20, 45])
        XCTAssertEqual(viewModel.next10DayDateText(formatter.date(from: "2024-11-11")!), "Mon 11/11")
    }

    func testTemperatureChartLabelAlignmentUsesLeadingNearLeftEdge() {
        let alignment = TemperatureChartLabelAlignmentResolver.alignment(
            forRunStartingAt: 0,
            endingAt: 0,
            pointCount: 8
        )

        XCTAssertEqual(alignment, .leading)
    }

    func testTemperatureChartLabelAlignmentUsesTrailingNearRightEdge() {
        let alignment = TemperatureChartLabelAlignmentResolver.alignment(
            forRunStartingAt: 6,
            endingAt: 7,
            pointCount: 8
        )

        XCTAssertEqual(alignment, .trailing)
    }

    func testTemperatureChartLabelAlignmentUsesCenterAwayFromEdges() {
        let alignment = TemperatureChartLabelAlignmentResolver.alignment(
            forRunStartingAt: 3,
            endingAt: 4,
            pointCount: 8
        )

        XCTAssertEqual(alignment, .center)
    }

    func testPlaceholderStateProducesExpectedStatusItemValues() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.conditionIconName, "sun.max.fill")
        XCTAssertEqual(viewModel.temperatureText, "72°")
        XCTAssertEqual(viewModel.highDetailText, "High: 76° at --")
        XCTAssertEqual(viewModel.lowDetailText, "Low: 64° at --")
    }

    func testPlaceholderConditionMapsToCorrectIconName() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.conditionIconName, "sun.max.fill")
    }

    func testRefreshButtonIsDisabledForOneMinuteAfterLastCheck() async {
        let clock = MutableNowBox(Date(timeIntervalSince1970: 1_731_447_660))
        let sleepRecorder = SleepRecorder()
        let taskBox = TaskBox()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false,
            retryDelays: [],
            postErrorRetryDelays: [],
            successRefreshDelay: { .seconds(600) },
            now: { clock.current },
            sleep: { duration in
                await sleepRecorder.record(duration)
                taskBox.task?.cancel()
            }
        )

        taskBox.task = Task {
            await viewModel.refreshWeather()
        }
        await taskBox.task?.value

        XCTAssertFalse(viewModel.isRefreshButtonEnabled)
        XCTAssertEqual(viewModel.refreshButtonHelpText(at: clock.current), "Refresh available in 60 seconds.")

        clock.current = clock.current.addingTimeInterval(60)
        XCTAssertTrue(viewModel.isRefreshButtonEnabled)
        XCTAssertEqual(viewModel.refreshButtonHelpText(at: clock.current), "Refresh weather")
    }

    func testLastCheckTextFormatsUsingRecordedCheckTime() async {
        let fixedDate = Date(timeIntervalSince1970: 1_731_447_600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm"

        let sleepRecorder = SleepRecorder()
        let taskBox = TaskBox()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false,
            retryDelays: [],
            postErrorRetryDelays: [],
            successRefreshDelay: { .seconds(600) },
            now: { fixedDate },
            sleep: { duration in
                await sleepRecorder.record(duration)
                taskBox.task?.cancel()
            }
        )

        taskBox.task = Task {
            await viewModel.refreshWeather()
        }
        await taskBox.task?.value

        let recordedSleeps = await sleepRecorder.values
        XCTAssertEqual(recordedSleeps, [.seconds(600)])
        XCTAssertEqual(viewModel.formatLastCheckText(referenceDate: fixedDate.addingTimeInterval(30), using: formatter), "Last checked: <1 min ago")
        XCTAssertEqual(viewModel.formatLastCheckText(referenceDate: fixedDate.addingTimeInterval(90), using: formatter), "Last checked: \(formatter.string(from: fixedDate))")
        XCTAssertEqual(viewModel.formatSunriseText(using: formatter), "Sunrise: --")
        XCTAssertEqual(viewModel.formatSunsetText(using: formatter), "Sunset: --")
        XCTAssertEqual(viewModel.formatHumidityText(), "Humidity: --")
        XCTAssertEqual(viewModel.formatPrecipitationText(), "Precipitation: --")
        XCTAssertEqual(viewModel.formatWindText(), "Wind: --")
        XCTAssertEqual(viewModel.windInlineText, "--")
        XCTAssertEqual(viewModel.precipitationInlineText, "--")
        XCTAssertEqual(viewModel.humidityInlineText, "--")
    }

    func testHourlyExtremaUseHourlyTemperatureTimes() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: fixture(named: "current-rain"))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "h:mm a"

        XCTAssertEqual(snapshot.highTemperature, 75)
        XCTAssertEqual(snapshot.highTemperatureAt.map(formatter.string(from:)), "3:00 PM")
        XCTAssertEqual(snapshot.lowTemperature, 63)
        XCTAssertEqual(snapshot.lowTemperatureAt.map(formatter.string(from:)), "3:00 AM")
        XCTAssertEqual(snapshot.windSpeed, 12)
        XCTAssertEqual(snapshot.humidity, 68)
        XCTAssertEqual(snapshot.precipitationChance, 55)
    }

    func testWeatherDetailTextFormatsSunriseSunsetAndRange() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: fixture(named: "current-rain"))
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: snapshot,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "h:mm a"

        XCTAssertEqual(normalizedWhitespace(viewModel.highDetailText), "High: 75° at 3:00 PM")
        XCTAssertEqual(normalizedWhitespace(viewModel.lowDetailText), "Low: 63° at 3:00 AM")
        XCTAssertEqual(viewModel.formatSunriseText(using: formatter), "Sunrise: 7:15 AM")
        XCTAssertEqual(viewModel.formatSunsetText(using: formatter), "Sunset: 7:05 PM")
        XCTAssertEqual(viewModel.humidityText, "Humidity: 68%")
        XCTAssertEqual(viewModel.precipitationText, "Precipitation: 55%")
        XCTAssertEqual(viewModel.windText, "Wind: 12 mph")
        XCTAssertEqual(viewModel.windInlineText, "12 mph")
        XCTAssertEqual(viewModel.precipitationInlineText, "55%")
        XCTAssertEqual(viewModel.humidityInlineText, "68%")

        viewModel.toggleTemperatureUnit()

        XCTAssertEqual(viewModel.windText, "Wind: 19 km/h")
        XCTAssertEqual(viewModel.windInlineText, "19 km/h")
        XCTAssertEqual(viewModel.humidityText, "Humidity: 68%")
        XCTAssertEqual(viewModel.precipitationText, "Precipitation: 55%")
        XCTAssertEqual(viewModel.precipitationInlineText, "55%")
        XCTAssertEqual(viewModel.humidityInlineText, "68%")
    }

    func testSettingsDefaultsLoadCorrectly() {
        let defaults = makeDefaults()

        let settings = WeatherSettings(defaults: defaults)

        XCTAssertEqual(settings.locationName, "Washington, DC")
        XCTAssertEqual(settings.latitude, 38.9072)
        XCTAssertEqual(settings.longitude, -77.0369)
        XCTAssertFalse(settings.usesPlaceholderWeather)
        XCTAssertEqual(settings.temperatureUnit, .fahrenheit)
        XCTAssertEqual(settings.savedLocations.count, 3)
        XCTAssertEqual(settings.savedLocations[1], WeatherSettings.defaultNorthPoleLocation)
        XCTAssertEqual(settings.savedLocations[2], WeatherSettings.defaultSouthPoleLocation)
        XCTAssertEqual(settings.selectedLocationIndex, 0)
    }

    func testClearConditionUsesMoonIconAtNight() {
        let condition = WeatherCondition(weatherCode: 0, isDaylight: false)

        XCTAssertEqual(condition.iconName(isDaylight: false), "moon.stars.fill")
    }

    func testPartlyCloudyConditionUsesMoonCloudIconAtNight() {
        let condition = WeatherCondition(weatherCode: 1, isDaylight: false)

        XCTAssertEqual(condition.iconName(isDaylight: false), "cloud.moon.fill")
    }

    func testLiveRefreshStartsInLoadingState() {
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: PendingWeatherService(),
            refreshOnInit: true,
            postErrorRetryDelays: []
        )

        XCTAssertTrue(viewModel.isLoading)
    }

    func testLoadingStateDoesNotExposePlaceholderValues() {
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: PendingWeatherService(),
            refreshOnInit: true,
            postErrorRetryDelays: []
        )

        XCTAssertEqual(viewModel.summaryText, "Loading weather...")
        XCTAssertEqual(viewModel.temperatureText, "--")
        XCTAssertEqual(viewModel.highDetailText, "High: -- at --")
        XCTAssertEqual(viewModel.lowDetailText, "Low: -- at --")
        XCTAssertEqual(viewModel.sunriseText, "Sunrise: --")
        XCTAssertEqual(viewModel.sunsetText, "Sunset: --")
        XCTAssertEqual(viewModel.humidityText, "Humidity: --")
        XCTAssertEqual(viewModel.precipitationText, "Precipitation: --")
        XCTAssertEqual(viewModel.windText, "Wind: --")
        XCTAssertEqual(viewModel.windInlineText, "--")
        XCTAssertEqual(viewModel.precipitationInlineText, "--")
        XCTAssertEqual(viewModel.humidityInlineText, "--")
    }

    func testRefreshUpdatesViewModelStateFromLoadingToSuccess() async {
        let updatedSnapshot = WeatherSnapshot(
            summary: "Clear sky",
            temperature: 66,
            condition: .clear,
            isDaylight: true,
            sunrise: nil,
            sunset: nil,
            highTemperature: 70,
            highTemperatureAt: nil,
            lowTemperature: 55,
            lowTemperatureAt: nil
        )
        let service = GatedWeatherService()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: true,
            retryDelays: [],
            postErrorRetryDelays: [],
            successRefreshDelay: { .seconds(600) }
        )

        XCTAssertTrue(viewModel.isLoading)

        await service.resume(with: .success(updatedSnapshot))
        await waitUntil { !viewModel.isLoading }

        XCTAssertEqual(viewModel.temperatureText, "66°")
        XCTAssertEqual(viewModel.summaryText, "Clear sky")
        XCTAssertEqual(viewModel.conditionIconName, "sun.max.fill")
    }

    func testRefreshUpdatesViewModelStateFromLoadingToError() async {
        let service = GatedWeatherService()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: true,
            retryDelays: [],
            postErrorRetryDelays: []
        )

        XCTAssertTrue(viewModel.isLoading)

        await service.resume(with: .failure(.networkUnavailable))
        await waitUntil { !viewModel.isLoading }

        XCTAssertEqual(viewModel.temperatureText, "--")
        XCTAssertEqual(viewModel.summaryText, "Network unavailable")
        XCTAssertEqual(viewModel.conditionIconName, "wifi.slash")
    }

    func testSuccessfulRefreshSchedulesRandomDelayBetweenCycles() async {
        let updatedSnapshot = WeatherSnapshot(
            summary: "Clear sky",
            temperature: 66,
            condition: .clear,
            isDaylight: true,
            sunrise: nil,
            sunset: nil,
            highTemperature: 70,
            highTemperatureAt: nil,
            lowTemperature: 55,
            lowTemperatureAt: nil
        )
        let service = SequencedWeatherService(results: [
            .success(updatedSnapshot),
            .success(.placeholder),
        ])
        let sleepRecorder = SleepRecorder()
        let taskBox = TaskBox()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [],
            postErrorRetryDelays: [],
            successRefreshDelay: { .seconds(720) },
            sleep: { duration in
                await sleepRecorder.record(duration)
                taskBox.task?.cancel()
            }
        )

        taskBox.task = Task {
            await viewModel.refreshWeather()
        }
        await taskBox.task?.value

        let recordedSleeps = await sleepRecorder.values
        XCTAssertEqual(recordedSleeps, [.seconds(720)])
        XCTAssertEqual(viewModel.temperatureText, "66°")
    }

    func testAPIErrorUsesCloudSlashAfterConfiguredRetries() async {
        let service = SequencedWeatherService(results: [
            .failure(.requestFailed),
            .failure(.requestFailed),
            .failure(.requestFailed),
            .failure(.requestFailed),
        ])
        let sleepRecorder = SleepRecorder()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [.seconds(10), .seconds(20), .seconds(30)],
            postErrorRetryDelays: [],
            sleep: { duration in
                await sleepRecorder.record(duration)
            }
        )

        await viewModel.refreshWeather()

        let recordedSleeps = await sleepRecorder.values
        XCTAssertEqual(recordedSleeps, [.seconds(10), .seconds(20), .seconds(30)])
        XCTAssertEqual(viewModel.conditionIconName, "cloud.slash")
        XCTAssertEqual(viewModel.temperatureText, "--")
        XCTAssertEqual(viewModel.summaryText, "Weather API unavailable")
    }

    func testPostErrorRetryCadenceUsesTwoThreeAndThenFiveMinutes() async {
        let service = SequencedWeatherService(results: [
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .success(.placeholder),
        ])
        let sleepRecorder = SleepRecorder()
        let taskBox = TaskBox()
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [.seconds(10), .seconds(20), .seconds(30)],
            postErrorRetryDelays: [.seconds(120), .seconds(180), .seconds(300)],
            successRefreshDelay: { .seconds(600) },
            sleep: { duration in
                await sleepRecorder.record(duration)
                if duration == .seconds(600) {
                    taskBox.task?.cancel()
                }
            }
        )

        taskBox.task = Task {
            await viewModel.refreshWeather()
        }
        await taskBox.task?.value

        let recordedSleeps = await sleepRecorder.values
        XCTAssertEqual(
            recordedSleeps,
            [.seconds(10), .seconds(20), .seconds(30), .seconds(120), .seconds(180), .seconds(300), .seconds(300), .seconds(600)]
        )
        XCTAssertEqual(viewModel.temperatureText, "72°")
    }

    private func makeWeatherService() -> OpenMeteoWeatherService {
        addTeardownBlock {
            URLProtocolStub.reset()
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return OpenMeteoWeatherService(session: session)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "\(name)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makePlaceholderViewModel() -> WeatherViewModel {
        WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: MockWeatherService(),
            refreshOnInit: false
        )
    }

}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static var responseProvider: (@Sendable (URLRequest) -> Result<(HTTPURLResponse, Data), Error>)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responseProvider = Self.responseProvider else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch responseProvider(request) {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        responseProvider = nil
    }
}

private final class TaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

private func persistCachedWeather(defaults: UserDefaults, entries: [String: CachedWeatherEntry]) {
    let data = try? JSONEncoder().encode(entries)
    defaults.set(data, forKey: WeatherSettings.cachedWeatherByLocationKey)
}

private func cacheKey(for location: SavedLocation) -> String {
    "\(location.name)|\(location.latitude)|\(location.longitude)"
}

private func coordinateKey(latitude: Double, longitude: Double) -> String {
    "\(latitude),\(longitude)"
}

private final class MutableNowBox: @unchecked Sendable {
    var current: Date

    init(_ current: Date) {
        self.current = current
    }
}

private actor SleepRecorder {
    private var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }

    var values: [Duration] {
        durations
    }
}

private actor GatedWeatherService: WeatherServing {
    private var continuation: CheckedContinuation<Result<WeatherSnapshot, WeatherServiceError>, Never>?

    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }

        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func resume(with result: Result<WeatherSnapshot, WeatherServiceError>) async {
        while continuation == nil {
            await Task.yield()
        }

        continuation?.resume(returning: result)
        continuation = nil
    }
}

private struct MockWeatherService: WeatherServing {
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        .placeholder
    }
}

private struct MockDeviceLocationProvider: DeviceLocationProviding {
    let result: Result<SavedLocation, Error>

    func detectLocation() async throws -> SavedLocation {
        switch result {
        case .success(let location):
            return location
        case .failure(let error):
            throw error
        }
    }
}

private struct MockSearchLocationProvider: SearchLocationProviding {
    let result: Result<SavedLocation, Error>

    func searchLocation(query: String) async throws -> SavedLocation {
        switch result {
        case .success(let location):
            return location
        case .failure(let error):
            throw error
        }
    }
}

private final class MockLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var isEnabled: Bool
    private(set) var setEnabledCalls: [Bool] = []

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        isEnabled = enabled
    }
}

private struct PendingWeatherService: WeatherServing {
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        try? await Task.sleep(for: .seconds(60))
        return .placeholder
    }
}

private actor CountingWeatherService: WeatherServing {
    private let snapshotByCoordinate: [String: WeatherSnapshot]
    private var countsByCoordinate: [String: Int] = [:]

    init(snapshotByCoordinate: [String: WeatherSnapshot]) {
        self.snapshotByCoordinate = snapshotByCoordinate
    }

    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        let key = coordinateKey(latitude: latitude, longitude: longitude)
        countsByCoordinate[key, default: 0] += 1
        return snapshotByCoordinate[key] ?? .placeholder
    }

    func fetchCount(latitude: Double, longitude: Double) -> Int {
        countsByCoordinate[coordinateKey(latitude: latitude, longitude: longitude), default: 0]
    }
}

private final class SequencedWeatherService: WeatherServing {
    private var results: [Result<WeatherSnapshot, WeatherServiceError>]

    init(results: [Result<WeatherSnapshot, WeatherServiceError>]) {
        self.results = results
    }

    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        guard !results.isEmpty else {
            return .placeholder
        }

        let result = results.removeFirst()
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

private func normalizedWhitespace(_ value: String) -> String {
    value.replacingOccurrences(of: "\u{202F}", with: " ")
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while !condition() {
        if DispatchTime.now().uptimeNanoseconds > deadline {
            XCTFail("Timed out waiting for condition")
            return
        }

        await Task.yield()
    }
}
