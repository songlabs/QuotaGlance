import Foundation

enum AppLocalization {
    static func string(
        _ key: String,
        defaultValue: String? = nil,
        locale: Locale,
        arguments: [CVarArg] = []
    ) -> String {
        let format = localizedBundle(for: locale).localizedString(
            forKey: key,
            value: defaultValue,
            table: nil
        )
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func localizedBundle(for locale: Locale) -> Bundle {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let candidates = [identifier, locale.language.languageCode?.identifier].compactMap { $0 }
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return Bundle.main
    }
}
