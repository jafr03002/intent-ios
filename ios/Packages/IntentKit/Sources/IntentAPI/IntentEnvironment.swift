import Foundation

/// Where the API lives. Every case resolves to a base URL that ends in `/api`,
/// matching the spec's `servers: [{ url: /api }]` and Express's `app.use("/api", router)`.
public enum IntentEnvironment: Sendable, Hashable {
    /// The deployed Vercel app (web + API on one origin, see vercel.json / DEPLOY.md).
    case production
    /// A local `artifacts/api-server` dev server, given by its origin, e.g.
    /// `http://192.168.1.20:8080` (a phone cannot reach the PC's `localhost`).
    /// `/api` is appended.
    case local(URL)
    /// Any full base URL, used as-is (include `/api` yourself), e.g. a Vercel preview.
    case custom(URL)

    /// Production origin: the `trainient-api-server` Vercel project's production alias.
    public static let productionOrigin = URL(string: "https://trainient-api-server.vercel.app")!

    /// The API server's default dev port (`PORT` in artifacts/api-server/.env, see dev-api.ps1).
    public static let defaultLocalOrigin = URL(string: "http://localhost:8080")!

    public var baseURL: URL {
        switch self {
        case .production: Self.productionOrigin.appendingPathComponent("api")
        case .local(let origin): origin.appendingPathComponent("api")
        case .custom(let url): url
        }
    }
}
