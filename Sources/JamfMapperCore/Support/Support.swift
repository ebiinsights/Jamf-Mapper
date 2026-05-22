import CryptoKit
import Foundation

public extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }

    func decodedJSONObject() throws -> Any {
        try JSONSerialization.jsonObject(with: self, options: [.fragmentsAllowed])
    }

    func decodedDictionary() -> [String: Any]? {
        (try? decodedJSONObject()) as? [String: Any]
    }
}

public extension String {
    var stableIdentifier: String {
        let data = Data(utf8)
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    var urlQueryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

public enum JamfMapperError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case missingToken
    case keychain(OSStatus)
    case unsupportedPayload
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The Jamf URL is invalid."
        case .invalidResponse:
            "Jamf returned a response the app could not understand."
        case let .httpStatus(status, message):
            "Jamf returned HTTP \(status): \(message)"
        case .missingToken:
            "Jamf did not return an OAuth access token."
        case let .keychain(status):
            "Keychain operation failed with status \(status)."
        case .unsupportedPayload:
            "This Jamf payload is not supported by the current mapper."
        case let .notFound(name):
            "\(name) was not found."
        }
    }
}

public enum JSONValueReader {
    public static func string(_ object: Any?, keys: [String]) -> String? {
        for key in keys {
            if let value = value(object, path: key.split(separator: ".").map(String.init)) {
                if let string = value as? String, !string.isEmpty { return string }
                if let int = value as? Int { return String(int) }
                if let number = value as? NSNumber { return number.stringValue }
            }
        }
        return nil
    }

    public static func int(_ object: Any?, keys: [String]) -> Int? {
        for key in keys {
            if let value = value(object, path: key.split(separator: ".").map(String.init)) {
                if let int = value as? Int { return int }
                if let string = value as? String, let int = Int(string) { return int }
                if let number = value as? NSNumber { return number.intValue }
            }
        }
        return nil
    }

    public static func bool(_ object: Any?, keys: [String]) -> Bool? {
        for key in keys {
            if let value = value(object, path: key.split(separator: ".").map(String.init)) {
                if let bool = value as? Bool { return bool }
                if let string = value as? String {
                    if ["true", "enabled", "yes"].contains(string.lowercased()) { return true }
                    if ["false", "disabled", "no"].contains(string.lowercased()) { return false }
                }
                if let number = value as? NSNumber { return number.boolValue }
            }
        }
        return nil
    }

    public static func array(_ object: Any?, keys: [String]) -> [[String: Any]] {
        if let items = object as? [[String: Any]] {
            return items
        }
        if let item = object as? [String: Any], keys.isEmpty {
            return [item]
        }
        for key in keys {
            guard let value = value(object, path: key.split(separator: ".").map(String.init)) else { continue }
            if let items = value as? [[String: Any]] { return items }
            if let item = value as? [String: Any] { return [item] }
        }
        return []
    }

    public static func value(_ object: Any?, path: [String]) -> Any? {
        guard !path.isEmpty else { return object }
        if let array = object as? [Any], path.count == 1 {
            return array
        }
        guard let dictionary = object as? [String: Any] else { return nil }
        let head = path[0]
        guard let next = dictionary[head] else { return nil }
        return value(next, path: Array(path.dropFirst()))
    }

    public static func unwrapJamfRoot(_ dictionary: [String: Any], expected: String) -> [String: Any] {
        if let nested = dictionary[expected] as? [String: Any] {
            return nested
        }
        return dictionary
    }

    public static func allDictionaries(named key: String, in object: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let direct = dictionary[key] as? [String: Any] { results.append(direct) }
                if let directArray = dictionary[key] as? [[String: Any]] { results.append(contentsOf: directArray) }
                for child in dictionary.values { walk(child) }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        return results
    }
}
