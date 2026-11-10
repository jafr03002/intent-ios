import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Supplies the signed-in user's Clerk session token, or nil when signed out.
/// Kept as a closure so IntentAPI does not depend on IntentAuth; the app passes
/// the auth module's `sessionToken()` here.
public typealias IntentTokenProvider = @Sendable () async throws -> String?

/// Adds `Authorization: Bearer <token>` to every request that needs auth.
///
/// Operations the spec marks `security: []` are skipped, so a health check works
/// signed out and never waits on the token provider.
public struct BearerTokenMiddleware: ClientMiddleware {
    /// operationIds with `security: []` in lib/api-spec/openapi.yaml.
    public static let unauthenticatedOperations: Set<String> = ["healthCheck", "stripeWebhook"]

    private let tokenProvider: IntentTokenProvider

    public init(tokenProvider: @escaping IntentTokenProvider) {
        self.tokenProvider = tokenProvider
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if !Self.unauthenticatedOperations.contains(operationID),
           let token = try await tokenProvider(), !token.isEmpty {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}
