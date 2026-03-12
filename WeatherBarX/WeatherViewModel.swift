import Foundation

struct WeatherSnapshot: Equatable {
    let summary: String
    let temperature: Int
    let condition: WeatherCondition

    static let placeholder = WeatherSnapshot(
        summary: "Placeholder weather",
        temperature: 72,
        condition: .placeholder
    )
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var isMenuPresented = false

    let settings: WeatherSettings
    let snapshot: WeatherSnapshot

    init(
        defaults: UserDefaults = .standard,
        snapshot: WeatherSnapshot? = nil
    ) {
        let settings = WeatherSettings(defaults: defaults)
        self.settings = settings
        self.snapshot = snapshot ?? .placeholder
    }

    var locationName: String {
        settings.locationName
    }

    var summaryText: String {
        snapshot.summary
    }

    var temperatureText: String {
        "\(snapshot.temperature)\u{00B0}"
    }

    var conditionSymbol: String {
        snapshot.condition.symbol
    }

    var conditionIconName: String {
        snapshot.condition.iconName
    }

    var menuBarTitle: String {
        "\(conditionSymbol) \(temperatureText)"
    }

    func toggleMenuPresentation() {
        isMenuPresented.toggle()
    }
}
