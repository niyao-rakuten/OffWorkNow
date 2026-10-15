import Foundation

/// Independent Foundation client. No UI or persistent API-key storage is involved.
public struct OpenRouterClient: Sendable {
    public struct Configuration: Sendable {
        public var endpoint: URL
        public var apiKey: String
        public var referer: URL?
        public var appTitle: String?
        public var timeout: TimeInterval
        public var maximumEventBytes: Int

        public init(apiKey: String,
                    endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                    referer: URL? = nil, appTitle: String? = nil,
                    timeout: TimeInterval = 120, maximumEventBytes: Int = 1_048_576) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.referer = referer
            self.appTitle = appTitle
            self.timeout = timeout
            self.maximumEventBytes = maximumEventBytes
        }
    }

    private let configuration: Configuration
    public init(configuration: Configuration) { self.configuration = configuration }

    /// Each invocation owns its connection. Cancel the consuming Task to stop the request.
    /// Cancellation while awaiting the next chunk closes the connection.
    /// After an early loop exit, release the stream and its iterator to close the connection.
    public func stream(_ request: OpenRouterRequest,
                       sessionConfiguration: URLSessionConfiguration = .ephemeral) -> AsyncThrowingStream<OpenRouterChunk, Error> {
        AsyncThrowingStream { continuation in
            let session = URLSession(configuration: sessionConfiguration)
            let task = Task {
                defer { session.invalidateAndCancel() }
                do {
                    let urlRequest = try makeURLRequest(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw OpenRouterError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            if body.count >= configuration.maximumEventBytes { break }
                            body.append(byte)
                        }
                        throw OpenRouterError.http(statusCode: http.statusCode, body: String(decoding: body, as: UTF8.self))
                    }
                    let contentType = http.value(forHTTPHeaderField: "Content-Type")
                    guard contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "text/event-stream" else {
                        throw OpenRouterError.unexpectedContentType(contentType)
                    }
                    var parser = SSEParser(maximumEventBytes: configuration.maximumEventBytes)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let payload = try parser.append(byte) else { continue }
                        if payload == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        continuation.yield(try decodeEvent(payload))
                    }
                    throw OpenRouterError.incompleteStream
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    func makeURLRequest(_ request: OpenRouterRequest) throws -> URLRequest {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.messages.isEmpty,
              configuration.timeout.isFinite, configuration.timeout > 0,
              configuration.maximumEventBytes > 0,
              ["https", "http"].contains(configuration.endpoint.scheme?.lowercased() ?? ""),
              configuration.endpoint.host != nil else {
            throw OpenRouterError.invalidRequest("Check API key, model, messages, endpoint and limits")
        }
        var result = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.timeout)
        result.httpMethod = "POST"
        result.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        result.setValue(configuration.referer?.absoluteString, forHTTPHeaderField: "HTTP-Referer")
        result.setValue(configuration.appTitle, forHTTPHeaderField: "X-OpenRouter-Title")
        result.httpBody = try JSONEncoder().encode(request)
        return result
    }

    func decodeEvent(_ payload: String) throws -> OpenRouterChunk {
        let data = Data(payload.utf8)
        let raw: OpenRouterJSON
        do { raw = try JSONDecoder().decode(OpenRouterJSON.self, from: data) }
        catch { throw OpenRouterError.malformedEvent(payload) }
        if case .object(let fields) = raw, let error = fields["error"] {
            if case .object(let details) = error, case .string(let message) = details["message"] {
                throw OpenRouterError.api(code: details["code"], message: message)
            }
            throw OpenRouterError.api(code: nil, message: payload)
        }
        do { return try JSONDecoder().decode(OpenRouterChunk.self, from: data) }
        catch { throw OpenRouterError.malformedEvent(payload) }
    }
}
