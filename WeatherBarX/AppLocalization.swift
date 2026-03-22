import Foundation

enum L10n {
    private final class BundleToken {}

    static func tr(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: tr(key),
            locale: Locale.autoupdatingCurrent,
            arguments: arguments
        )
    }

    private static var localizedBundle: Bundle {
        let baseBundle = Bundle(for: BundleToken.self)

        if shouldForceEnglish,
           let englishPath = baseBundle.path(forResource: "en", ofType: "lproj"),
           let englishBundle = Bundle(path: englishPath) {
            return englishBundle
        }

        return baseBundle
    }

    private static var shouldForceEnglish: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("--ui-testing") || processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
