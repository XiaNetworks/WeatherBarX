import XCTest
@testable import weatherX

@MainActor
final class WeatherViewModelTests: XCTestCase {
    func testPlaceholderTemperatureFormatsCorrectly() {
        let viewModel = WeatherViewModel(defaults: makeDefaults())

        XCTAssertEqual(viewModel.temperatureText, "72°")
    }

    func testPlaceholderStateProducesExpectedStatusBarText() {
        let viewModel = WeatherViewModel(defaults: makeDefaults())

        XCTAssertEqual(viewModel.menuBarTitle, "☀️ 72°")
    }

    func testPlaceholderConditionMapsToCorrectIconName() {
        let viewModel = WeatherViewModel(defaults: makeDefaults())

        XCTAssertEqual(viewModel.conditionIconName, "sun.max.fill")
    }

    func testSettingsDefaultsLoadCorrectly() {
        let defaults = makeDefaults()

        let settings = WeatherSettings(defaults: defaults)

        XCTAssertEqual(settings.locationName, "WeatherX")
        XCTAssertTrue(settings.usesPlaceholderWeather)
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
}
