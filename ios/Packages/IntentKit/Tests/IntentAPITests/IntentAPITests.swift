import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import IntentAPI

/// A `ClientTransport` that records requests and answers with canned JSON.
final class MockTransport: ClientTransport, @unchecked Sendable {
    struct Recorded: Sendable {
        var request: HTTPRequest
        var baseURL: URL
        var operationID: String
    }

    private let lock = NSLock()
    private var _recorded: [Recorded] = []
    private let respond: @Sendable (String) -> (Int, String)

    var recorded: [Recorded] { lock.withLock { _recorded } }

    init(respond: @escaping @Sendable (_ operationID: String) -> (status: Int, json: String)) {
        self.respond = respond
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        lock.withLock { _recorded.append(.init(request: request, baseURL: baseURL, operationID: operationID)) }
        let (status, json) = respond(operationID)
        var fields = HTTPFields()
        fields[.contentType] = "application/json; charset=utf-8"
        return (HTTPResponse(status: .init(code: status), headerFields: fields), HTTPBody(json))
    }
}

@Suite struct IntentAPITests {
    // MARK: Auth middleware

    @Test func addsBearerTokenToAuthenticatedOperations() async throws {
        let transport = MockTransport { _ in (200, #"{"currentWeek":3,"totalLogged":12,"lastSessionDate":null,"streakDays":0}"#) }
        let client = IntentAPIClient(environment: .production, tokenProvider: { "tok_123" }, transport: transport)

        _ = try await client.api.getWorkoutStats()

        let sent = try #require(transport.recorded.first)
        #expect(sent.operationID == "getWorkoutStats")
        #expect(sent.request.headerFields[.authorization] == "Bearer tok_123")
        #expect(sent.request.path == "/workouts/stats")
        #expect(sent.baseURL.absoluteString == "https://trainient-api-server.vercel.app/api")
    }

    @Test func noHeaderWhenSignedOutOrUnauthenticatedOperation() async throws {
        let transport = MockTransport { op in
            op == "healthCheck"
                ? (200, #"{"status":"ok"}"#)
                : (200, #"{"currentWeek":1,"totalLogged":0,"lastSessionDate":null,"streakDays":0}"#)
        }
        let signedOut = IntentAPIClient(tokenProvider: { nil }, transport: transport)
        _ = try await signedOut.api.getWorkoutStats()

        // healthCheck is `security: []`: the token provider is never consulted.
        let throwing = IntentAPIClient(tokenProvider: { throw CancellationError() }, transport: transport)
        let probe = await throwing.probeHealth()

        #expect(transport.recorded.allSatisfy { $0.request.headerFields[.authorization] == nil })
        #expect(probe.isHealthy)
    }

    // MARK: Decoding real response shapes

    @Test func decodesHealthz() async throws {
        let transport = MockTransport { _ in (200, #"{"status":"ok"}"#) }
        let probe = await IntentAPIClient(transport: transport).probeHealth()
        #expect(probe.statusCode == 200)
        #expect(probe.status == "ok")
        #expect(probe.error == nil)
    }

    @Test func decodesWorkoutStats() async throws {
        let transport = MockTransport { _ in (200, #"{"currentWeek":3,"totalLogged":12,"lastSessionDate":"2026-10-30","streakDays":2}"#) }
        let stats = try await IntentAPIClient(transport: transport).api.getWorkoutStats().ok.body.json
        #expect(stats == IntentSchemas.WorkoutStats(currentWeek: 3, totalLogged: 12, lastSessionDate: "2026-10-30", streakDays: 2))
    }

    /// The server's exact "not in calibration" payload (calibrationReview.ts `empty`).
    /// `checks`, `feedbackSummary` and `latestReview` are `oneOf [$ref, null]` in the spec,
    /// which the generator only keeps thanks to ios/scripts/openapi-preprocess.py.
    @Test func decodesCalibrationStatusWithNullableRefs() async throws {
        let json = """
        {"calibrationDay":null,"startDate":null,"reviewOpensOn":null,"lastReviewDate":null,"autoExitOn":null,
         "reviewOpen":false,"nextReviewAvailableOn":null,"paused":false,"autoExitDue":false,"checks":null,
         "sessions":[],"feedbackSummary":null,"latestReview":null,"inCalibration":false,
         "reviewBlockedReason":"not_in_calibration"}
        """
        let transport = MockTransport { _ in (200, json) }
        let status = try await IntentAPIClient(transport: transport).api.getCalibrationStatus().ok.body.json
        #expect(status.inCalibration == false)
        #expect(status.reviewBlockedReason == .notInCalibration)
        #expect(status.checks == nil)
        #expect(status.latestReview == nil)
        #expect(status.sessions.isEmpty)
    }

    // MARK: Errors

    @Test func mapsUndocumentedStatuses() async throws {
        let transport = MockTransport { _ in (401, #"{"error":"Unauthorized"}"#) }
        let output = try await IntentAPIClient(transport: transport).api.getWorkoutStats()
        guard case .undocumented(let code, let payload) = output else {
            Issue.record("expected undocumented, got \(output)")
            return
        }
        #expect(await IntentAPIError.undocumented(statusCode: code, payload) == .unauthorized)

        let failing = MockTransport { _ in (500, #"{"error":"Internal server error"}"#) }
        let probe = await IntentAPIClient(transport: failing).probeHealth()
        #expect(probe.statusCode == 500)
        #expect(probe.error == .http(statusCode: 500, message: "Internal server error"))
    }

    // MARK: Environment + dates

    @Test func environmentBaseURLs() {
        #expect(IntentEnvironment.production.baseURL.absoluteString == "https://trainient-api-server.vercel.app/api")
        #expect(IntentEnvironment.local(URL(string: "http://192.168.1.20:8080")!).baseURL.absoluteString == "http://192.168.1.20:8080/api")
        #expect(IntentEnvironment.custom(URL(string: "https://example.test/api")!).baseURL.absoluteString == "https://example.test/api")
    }

    @Test func datesMatchJavaScriptISOStrings() throws {
        let transcoder = ServerDateTranscoder()
        let date = try transcoder.decode("2026-11-01T20:54:29.123Z")
        #expect(try transcoder.encode(date) == "2026-11-01T20:54:29.123Z")
        #expect(try transcoder.decode("2026-11-01T20:54:29Z").timeIntervalSince1970 == 1_793_566_469)
    }
}
