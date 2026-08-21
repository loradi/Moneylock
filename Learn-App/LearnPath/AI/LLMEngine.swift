import Foundation
import CoreMLLLM

struct LLMMessage: Sendable, Equatable {
    enum Role: String, Sendable {
        case user, assistant, system
    }
    let role: Role
    let content: String
}

protocol ModelProvider: Sendable {
    func load(onProgress: @escaping @Sendable (String) -> Void) async throws
    func generate(messages: [LLMMessage], maxTokens: Int) async throws -> String
    func stream(messages: [LLMMessage], maxTokens: Int) async throws
        -> AsyncStream<String>
    func reset()
}

enum LLMError: LocalizedError {
    case notLoaded
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "El modelo no está cargado."
        case .emptyResponse:
            return "El modelo devolvió una respuesta vacía. Inténtalo de nuevo."
        }
    }
}

final class LLMEngine: ModelProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var llm: CoreMLLLM?
    private var _isLoading = false

    var isLoading: Bool {
        lock.withLock { _isLoading }
    }

    func load(onProgress: @escaping @Sendable (String) -> Void) async throws {
        if let existing = lock.withLock({ llm }) {
            onProgress("Modelo ya cargado")
            _ = existing
            return
        }
        lock.withLock { _isLoading = true }
        defer { lock.withLock { _isLoading = false } }
        let loaded = try await CoreMLLLM.load(
            repo: "gemma4-e2b",
            onProgress: onProgress)
        lock.withLock { llm = loaded }
    }

    func generate(messages: [LLMMessage], maxTokens: Int) async throws -> String {
        guard let llm = lock.withLock({ llm }) else { throw LLMError.notLoaded }
        let coreMessages = messages.map { message in
            CoreMLLLM.Message(
                role: message.role == .system ? .system
                    : message.role == .assistant ? .assistant : .user,
                content: message.content)
        }
        let output = try await llm.generate(coreMessages, maxTokens: maxTokens)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
        return trimmed
    }

    func stream(messages: [LLMMessage], maxTokens: Int) async throws
        -> AsyncStream<String> {
        guard let llm = lock.withLock({ llm }) else { throw LLMError.notLoaded }
        let coreMessages = messages.map { message in
            CoreMLLLM.Message(
                role: message.role == .system ? .system
                    : message.role == .assistant ? .assistant : .user,
                content: message.content)
        }
        return try await llm.stream(coreMessages, maxTokens: maxTokens)
    }

    func reset() {
        lock.withLock { llm?.reset() }
    }

    func unload() {
        lock.withLock { llm = nil }
    }
}

extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}