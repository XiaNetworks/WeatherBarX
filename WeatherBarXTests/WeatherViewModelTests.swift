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
