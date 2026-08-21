import Foundation

enum JSONParsingError: LocalizedError {
    case noJSONFound
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noJSONFound:
            return "No se encontró JSON en la respuesta del modelo."
        case .decodeFailed(let detail):
            return "No se pudo decodificar el JSON: \(detail)"
        }
    }
}

enum JSONParser {

    /// Extrae el primer JSON válido de la respuesta del modelo.
    /// Busca desde el primer "{" o "[" hasta el cierre balanceado
    /// correspondiente, tolerando texto suelto alrededor.
    ///
    /// Los modelos on-device suelen emitir saltos de línea o tabs sin
    /// escapar dentro de valores string (p. ej. en descripciones de
    /// varias frases), lo que rompe JSONSerialization aunque las llaves
    /// estén balanceadas. Se escapan esos caracteres de control al vuelo.
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