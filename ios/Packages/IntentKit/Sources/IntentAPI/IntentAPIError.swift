import Foundation
import OpenAPIRuntime

/// What went wrong with an API call, in terms a screen can act on.
public enum IntentAPIError: Error, Sendable, Equatable {
    /// 401: no or expired Clerk session. The server answers `{ "error": "Unauthorized" }`.
    case unauthorized
    /// Any other status the operation does not document (or a documented non-2xx the
    /// caller chose not to handle). `message` is the server's `{ "error": "..." }`, if any.
    case http(statusCode: Int, message: String?)
    /// No HTTP response at all: offline, DNS, TLS, timeout, or a body that did not decode.
    case transport(String)

    /// Builds the error for a generated `.undocumented(statusCode:_:)` output,
    /// reading the server's `{ "error": "..." }` body when there is one.
    public static func undocumented(statusCode: Int, _ payload: UndocumentedPayload) async -> IntentAPIError {
        if statusCode == 401 { return .unauthorized }
        var message: String?
        if let body = payload.body, let data = try? await Data(collecting: body, upTo: 64 * 1024) {
            message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? String(data: data, encoding: .utf8).map { String($0.prefix(500)) }
        }
        return .http(statusCode: statusCode, message: message)
    }

    /// Maps anything a generated client call throws into an `IntentAPIError`.
    public static func from(_ error: any Error) -> IntentAPIError {
        if let error = error as? IntentAPIError { return error }
        if let error = error as? ClientError {
            if let status = error.response?.status.code {
                return status == 401 ? .unauthorized : .http(statusCode: status, message: nil)
            }
            return .transport(String(describing: error.underlyingError))
        }
        return .transport(String(describing: error))
    }

    private struct ErrorBody: Decodable { let error: String }
}

extension IntentAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Not signed in"
        case .http(let code, let message): message.map { "HTTP \(code): \($0)" } ?? "HTTP \(code)"
        case .transport(let detail): "Network error: \(detail)"
        }
    }
}
