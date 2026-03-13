import XCTest
@testable import WeatherBarX

@MainActor
final class WeatherViewModelTests: XCTestCase {
    func testPlaceholderTemperatureFormatsCorrectly() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.temperatureText, "72°")
    }

    func testPlaceholderStateProducesExpectedStatusBarText() {
        let viewModel = makePlaceholderViewModel()

        XCTAssertEqual(viewModel.menuBarTitle, "☀️ 72°")
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

    func testWeatherCodeMapsToRainCondition() {
        let condition = WeatherCondition(weatherCode: 61, isDaylight: true)

        XCTAssertEqual(condition.symbol, "🌧️")
        XCTAssertEqual(condition.iconName, "cloud.rain.fill")
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

    func testNetworkErrorUsesWifiSlashAfterConfiguredRetries() async {
        let service = SequencedWeatherService(results: [
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
            .failure(.networkUnavailable),
        ])
        var recordedSleeps: [Duration] = []
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [.seconds(10), .seconds(20), .seconds(30)],
            postErrorRetryDelays: [],
            sleep: { duration in
                recordedSleeps.append(duration)
            }
        )

        await viewModel.refreshWeather()

        XCTAssertEqual(recordedSleeps, [.seconds(10), .seconds(20), .seconds(30)])
        XCTAssertEqual(viewModel.conditionIconName, "wifi.slash")
        XCTAssertEqual(viewModel.temperatureText, "--")
        XCTAssertEqual(viewModel.summaryText, "Network unavailable")
    }

    func testAPIErrorUsesCloudSlashAfterConfiguredRetries() async {
        let service = SequencedWeatherService(results: [
            .failure(.requestFailed),
            .failure(.requestFailed),
            .failure(.requestFailed),
            .failure(.requestFailed),
        ])
        var recordedSleeps: [Duration] = []
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [.seconds(10), .seconds(20), .seconds(30)],
            postErrorRetryDelays: [],
            sleep: { duration in
                recordedSleeps.append(duration)
            }
        )

        await viewModel.refreshWeather()

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
        var recordedSleeps: [Duration] = []
        let viewModel = WeatherViewModel(
            defaults: makeDefaults(),
            snapshot: .placeholder,
            weatherService: service,
            refreshOnInit: false,
            retryDelays: [.seconds(10), .seconds(20), .seconds(30)],
            postErrorRetryDelays: [.seconds(120), .seconds(180), .seconds(300)],
            sleep: { duration in
                recordedSleeps.append(duration)
            }
        )

        await viewModel.refreshWeather()

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
