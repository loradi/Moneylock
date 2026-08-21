import XCTest
@testable import LearnPath

final class JSONParserTests: XCTestCase {

    func testExtractsJSONFromCleanResponse() {
        let text = #"{"topic": "Física", "levels": []}"#
        XCTAssertEqual(JSONParser.extractJSON(from: text), text)
    }

    func testExtractsJSONFromResponseWithSurroundingText() {
        let text = #"Aquí está tu plan: {"topic": "Física", "levels": []} ¡Éxito!"#
        XCTAssertEqual(
            JSONParser.extractJSON(from: text),
            #"{"topic": "Física", "levels": []}"#)
    }

    func testExtractsJSONWithNestedBraces() {
        let text = #"""
        {"levels": [{"title": "A", "description": "Con {llaves} dentro"}]}
        """#
        XCTAssertEqual(
            JSONParser.extractJSON(from: text),
            #"{"levels": [{"title": "A", "description": "Con {llaves} dentro"}]}"#)
    }

    func testExtractsJSONFromArray() {
        let text = #"[{"a": 1}, {"a": 2}]"#
        XCTAssertEqual(JSONParser.extractJSON(from: text), text)
    }

    func testHandlesStringsWithEscapedQuotes() {
        let text = #"{"prompt": "Dijo \"hola\" y ______", "correct": ["hola"]}"#
        XCTAssertEqual(
            JSONParser.extractJSON(from: text),
            #"{"prompt": "Dijo \"hola\" y ______", "correct": ["hola"]}"#)
    }

    func testReturnsNilWhenNoJSON() {
        XCTAssertNil(JSONParser.extractJSON(from: "solo texto sin JSON"))
    }

    func testDecodePathSkeleton() throws {
        let text = #"""
        {"topic": "Swift", "levels": [
            {"title": "Fundamentos", "description": "Sintaxis básica", "difficulty": 1},
            {"title": "OOP", "description": "Clases y structs", "difficulty": 2}
        ]}
        """#
        let skeleton = try JSONParser.decode(PathSkeleton.self, from: text)
        XCTAssertEqual(skeleton.topic, "Swift")
        XCTAssertEqual(skeleton.levels.count, 2)
        XCTAssertEqual(skeleton.levels[1].difficulty, 2)
    }

    func testDecodeExerciseArray() throws {
        let text = #"""
        [
          {"type": "quiz", "prompt": "¿Qué es X?", "options": ["a","b","c","d"],
           "correctIndex": 0, "explanation": "porque sí"},
          {"type": "fillBlank", "prompt": "El átomo tiene ______",
           "correct": ["electrones"], "explanation": "e"}
        ]
        """#
        let exercises = try JSONParser.decode([Exercise].self, from: text)
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises[0].type, .quiz)
        XCTAssertEqual(exercises[0].correctIndex, 0)
        XCTAssertEqual(exercises[1].type, .fillBlank)
        XCTAssertEqual(exercises[1].correct, ["electrones"])
    }

    func testDecodeFailsOnInvalidJSON() {
        let text = #"{"topic": "incompleto""#
        XCTAssertThrowsError(try JSONParser.decode(PathSkeleton.self, from: text))
    }

    func testDecodeFailsWhenNoJSONFound() {
        XCTAssertThrowsError(try JSONParser.decode(PathSkeleton.self, from: "sin json"))
    }

    func testDecodeSucceedsWithRawNewlineInsideStringValue() throws {
        let text = "{\"topic\": \"Swift\", \"levels\": [{\"title\": \"Intro\", \"description\": \"Linea uno\nLinea dos\", \"difficulty\": 1}]}"
        let skeleton = try JSONParser.decode(PathSkeleton.self, from: text)
        XCTAssertEqual(skeleton.levels.first?.description, "Linea uno\nLinea dos")
    }
}