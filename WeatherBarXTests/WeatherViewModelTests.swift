import XCTest
@testable import WeatherBarX

@MainActor
final class WeatherViewModelTests: XCTestCase {
    func testJSONResponseDecodesIntoWeatherModelCorrectly() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: sampleResponse(
            temperature: 72.4,
            weatherCode: 3,
            currentTime: "2026-03-12T14:00",
            sunrise: ["2026-03-12T07:15"],
            sunset: ["2026-03-12T19:05"]
        ))

        XCTAssertEqual(snapshot.temperature, 72)
        XCTAssertEqual(snapshot.summary, "Cloudy")
        XCTAssertEqual(snapshot.condition, .cloudy)
        XCTAssertTrue(snapshot.isDaylight)
    }

    func testSunriseSunsetPayloadUsesDayIconDuringDaylight() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: sampleResponse(
            temperature: 68.2,
            weatherCode: 0,
            currentTime: "2026-03-12T14:00",
            sunrise: ["2026-03-12T07:15"],
            sunset: ["2026-03-12T19:05"]
        ))

        XCTAssertTrue(snapshot.isDaylight)
        XCTAssertEqual(snapshot.condition.iconName(isDaylight: snapshot.isDaylight), "sun.max.fill")
    }

    func testSunriseSunsetPayloadUsesNightIconAfterSunset() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: sampleResponse(
            temperature: 57.9,
            weatherCode: 0,
            currentTime: "2026-03-12T21:00",
            sunrise: ["2026-03-12T07:15"],
            sunset: ["2026-03-12T19:05"]
        ))

        XCTAssertFalse(snapshot.isDaylight)
        XCTAssertEqual(snapshot.condition.iconName(isDaylight: snapshot.isDaylight), "moon.stars.fill")
    }

    func testSunriseSunsetPayloadTreatsSunsetAsNightBoundary() throws {
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: sampleResponse(
            temperature: 61.0,
            weatherCode: 1,
            currentTime: "2026-03-12T19:05",
            sunrise: ["2026-03-12T07:15"],
            sunset: ["2026-03-12T19:05"]
        ))

        XCTAssertFalse(snapshot.isDaylight)
        XCTAssertEqual(snapshot.condition.iconName(isDaylight: snapshot.isDaylight), "cloud.moon.fill")
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
        let snapshot = try OpenMeteoWeatherService.decodeSnapshot(from: sampleResponse(
            temperature: 63.6,
            weatherCode: 0,
            currentTime: "2026-03-12T02:00",
            sunrise: [],
            sunset: []
        ))

        XCTAssertEqual(snapshot.temperature, 64)
        XCTAssertEqual(snapshot.condition, .clear)
        XCTAssertTrue(snapshot.isDaylight)
        XCTAssertEqual(snapshot.summary, "Clear sky")
    }

    func testDecodeFailsForMalformedAPIResponse() {
        let malformedData = Data("{\"timezone\":\"America/New_York\"}".utf8)

        XCTAssertThrowsError(try OpenMeteoWeatherService.decodeSnapshot(from: malformedData)) { error in
            XCTAssertEqual(error as? WeatherServiceError, .decodeFailed)
        }
    }

    func testPlaceholderTemperatureFormatsCorrectly() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.temperatureText, "72°")
    }

    func testPlaceholderStateProducesExpectedStatusItemValues() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.conditionIconName, "sun.max.fill")
        XCTAssertEqual(viewModel.temperatureText, "72°")
    }

    func testPlaceholderConditionMapsToCorrectIconName() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.conditionIconName, "sun.max.fill")
    }

    func testSettingsDefaultsLoadCorrectly() {
        let defaults = makeDefaults()

        let settings = WeatherSettings(defaults: defaults)

        XCTAssertEqual(settings.locationName, "Washington, DC")
        XCTAssertEqual(settings.latitude, 38.9072)
        XCTAssertEqual(settings.longitude, -77.0369)
        XCTAssertFalse(settings.usesPlaceholderWeather)
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
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [.seconds(10), .seconds(20), .seconds(30)],
            postErrorRetryDelays: [.seconds(120), .seconds(180), .seconds(300)],
            sleep: { duration in
                await sleepRecorder.record(duration)
            }
        )

        await viewModel.refreshWeather()

        let recordedSleeps = await sleepRecorder.values
        XCTAssertEqual(
            recordedSleeps,
            [.seconds(10), .seconds(20), .seconds(30), .seconds(120), .seconds(180), .seconds(300), .seconds(300)]
        )
        XCTAssertEqual(viewModel.temperatureText, "72°")
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

    private func sampleResponse(
        temperature: Double,
        weatherCode: Int,
        currentTime: String,
        sunrise: [String],
        sunset: [String],
        timezone: String = "America/New_York"
    ) -> Data {
        let sunriseJSON = sunrise.map { "\"\($0)\"" }.joined(separator: ",")
        let sunsetJSON = sunset.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {
          "timezone": "\(timezone)",
          "current": {
            "time": "\(currentTime)",
            "temperature_2m": \(temperature),
            "weather_code": \(weatherCode)
          },
          "daily": {
            "sunrise": [\(sunriseJSON)],
            "sunset": [\(sunsetJSON)]
          }
        }
        """

        return Data(json.utf8)
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

private struct MockWeatherService: WeatherServing {
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        .placeholder
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
