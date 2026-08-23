import Foundation

enum FormURLEncoder {
    static func data(_ values: [String: String]) -> Data {
        let body = values
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
