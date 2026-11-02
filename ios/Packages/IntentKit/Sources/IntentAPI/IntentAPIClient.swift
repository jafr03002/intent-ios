import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenAPIRuntime
import OpenAPIURLSession

/// Generated schema types, e.g. `IntentSchemas.WorkoutStats`.
public typealias IntentSchemas = Components.Schemas

/// The app's entry point to the Express API.
///
/// `api` is the generated client (one method per operationId in lib/api-spec/openapi.yaml):
///
///     let intent = IntentAPIClient(environment: .production, tokenProvider: { try await auth.sessionToken() })
///     switch try await intent.api.getWorkoutStats() {
///     case .ok(let ok): let stats = try ok.body.json
///     case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
///     }
public struct IntentAPIClient: Sendable {
    public let environment: IntentEnvironment
    public let api: Client

    public var baseURL: URL { environment.baseURL }

    /// - Parameters:
    ///   - tokenProvider: the Clerk session token, nil when signed out.
    ///   - transport: override for tests (a mock `ClientTransport`); defaults to URLSession.
    ///   - timeout: per-request timeout in seconds. AI generation runs as polled jobs, so
    ///     no single request should take long.
    public init(
        environment: IntentEnvironment = .production,
        tokenProvider: @escaping IntentTokenProvider = { nil },
        transport: (any ClientTransport)? = nil,
        timeout: TimeInterval = 30
    ) {
        self.environment = environment
        self.api = Client(
            serverURL: environment.baseURL,
            configuration: Configuration(dateTranscoder: ServerDateTranscoder()),
            transport: transport ?? Self.urlSessionTransport(timeout: timeout),
            middlewares: [BearerTokenMiddleware(tokenProvider: tokenProvider)]
        )
    }

    private static func urlSessionTransport(timeout: TimeInterval) -> URLSessionTransport {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSessionTransport(configuration: .init(session: URLSession(configuration: config)))
    }

    // MARK: - Health

    /// Result of `GET /healthz` (no auth). Never throws, so a debug screen can show any outcome.
    public struct HealthProbe: Sendable {
        public var baseURL: URL
        /// HTTP status, nil when there was no response.
        public var statusCode: Int?
        /// `status` from the body (`"ok"`) on a 200.
        public var status: String?
        public var latency: Duration
        public var error: IntentAPIError?

        public var isHealthy: Bool { statusCode == 200 && status == "ok" }
    }

    public func probeHealth() async -> HealthProbe {
        let clock = ContinuousClock()
        let start = clock.now
        var probe = HealthProbe(baseURL: baseURL, latency: .zero)
        do {
            switch try await api.healthCheck() {
            case .ok(let ok):
                probe.statusCode = 200
                probe.status = try ok.body.json.status
            case .undocumented(let code, let payload):
                probe.statusCode = code
                probe.error = await IntentAPIError.undocumented(statusCode: code, payload)
            }
        } catch {
            let mapped = IntentAPIError.from(error)
            if case .http(let code, _) = mapped { probe.statusCode = code }
            probe.error = mapped
        }
        probe.latency = clock.now - start
        return probe
    }
}

/// ISO 8601 dates the way the server reads and writes them: JavaScript's
/// `toISOString()` (`2026-11-01T20:54:29.123Z`). Decoding also accepts no fractional
/// seconds. Only `format: date-time` fields use this (today just
/// `WorkoutLogInput.startedAt`); `format: date` fields stay `String` ("YYYY-MM-DD").
struct ServerDateTranscoder: DateTranscoder {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    func encode(_ date: Date) throws -> String { Self.fractional.format(date) }

    func decode(_ string: String) throws -> Date {
        if let date = try? Self.fractional.parse(string) { return date }
        return try Self.whole.parse(string)
    }
}
