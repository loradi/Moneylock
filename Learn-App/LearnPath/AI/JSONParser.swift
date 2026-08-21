import Foundation

enum JSONParsingError: LocalizedError {
    case noJSONFound
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noJSONFound:
            return "No JSON was found in the model's response."
        case .decodeFailed(let detail):
            return "Couldn't decode the JSON: \(detail)"
        }
    }
}

enum JSONParser {

    /// Extracts the first valid JSON from the model's response.
    /// Scans from the first "{" or "[" to its matching balanced close,
    /// tolerating loose text around it.
    ///
    /// On-device models often emit unescaped newlines or tabs inside
    /// string values (e.g. in multi-sentence descriptions), which breaks
    /// JSONSerialization even when the braces are balanced. Those control
    /// characters are escaped on the fly.
    static func extractJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }
        let startIndex = first
        let openChar = trimmed[first]
        let closeChar: Character = openChar == "{" ? "}" : "]"
        var depth = 0
        var inString = false
        var escaped = false
        var result = ""

        for index in trimmed[startIndex...].indices {
            let char = trimmed[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                switch char {
                case "\n": result.append("\\n")
                case "\r": result.append("\\r")
                case "\t": result.append("\\t")
                default: result.append(char)
                }
                continue
            }
            switch char {
            case "\"":
                inString = true
            case openChar:
                depth += 1
            case closeChar:
                depth -= 1
                result.append(char)
                if depth == 0 {
                    return result
                }
                continue
            default:
                break
            }
            result.append(char)
        }
        return nil
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let json = extractJSON(from: text) else {
            throw JSONParsingError.noJSONFound
        }
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw JSONParsingError.decodeFailed(error.localizedDescription)
        }
    }
}