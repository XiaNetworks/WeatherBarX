import XCTest
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

    func testLaunchAtLoginToggleUpdatesButtonState() {
        let launchAtLoginManager = MockLaunchAtLoginManager(isEnabled: false)
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
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

    func testTemperatureUnitToggleConvertsDisplayedTemperatures() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.temperatureUnitButtonText, "°F")
        XCTAssertEqual(viewModel.temperatureText, "72°")
        XCTAssertEqual(viewModel.highDetailText, "High: 76° at --")
        XCTAssertEqual(viewModel.lowDetailText, "Low: 64° at --")

        viewModel.toggleTemperatureUnit()

        XCTAssertEqual(viewModel.temperatureUnitButtonText, "°C")
        XCTAssertEqual(viewModel.temperatureText, "22°")
        XCTAssertEqual(viewModel.highDetailText, "High: 24° at --")
        XCTAssertEqual(viewModel.lowDetailText, "Low: 18° at --")
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

        clock.current = clock.current.addingTimeInterval(60)
        XCTAssertTrue(viewModel.isRefreshButtonEnabled)
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
    }

    func testSettingsDefaultsLoadCorrectly() {
        let defaults = makeDefaults()

        let settings = WeatherSettings(defaults: defaults)

        XCTAssertEqual(settings.locationName, "Washington, DC")
        XCTAssertEqual(settings.latitude, 38.9072)
        XCTAssertEqual(settings.longitude, -77.0369)
        XCTAssertFalse(settings.usesPlaceholderWeather)
        XCTAssertEqual(settings.temperatureUnit, .fahrenheit)
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

