import Foundation

enum JSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISO8601DateParser.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
            }
            return date
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }
}

/// The backend sends UTC instants like `2026-10-20T17:55:46.104058Z`. The fraction
/// can have 0, 3, 6 or 9 digits (Java prints only what is needed) and
/// `ISO8601DateFormatter` is unreliable beyond milliseconds, so the fraction is
/// normalised to milliseconds before parsing.
enum ISO8601DateParser {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        guard let dot = string.firstIndex(of: ".") else {
            return withoutFraction.date(from: string)
        }

        let afterDot = string.index(after: dot)
        let digitsEnd = string[afterDot...].firstIndex(where: { !$0.isNumber }) ?? string.endIndex
        let digits = string[afterDot..<digitsEnd]
        guard !digits.isEmpty else { return nil }

        let millis = String((digits + "000").prefix(3))
        let normalised = string[..<dot] + "." + millis + string[digitsEnd...]
        return withFraction.date(from: String(normalised))
    }
}
