import IntentAPI
import SwiftUI

/// `-IntentScreen api`: calls `GET /healthz` (no auth) and shows the outcome, so a CI
/// screenshot proves generated client -> URLSession -> deployed API works end to end.
struct ApiDebugView: View {
    /// Production first. The second Vercel project also deploys this repo; listed so a
    /// screenshot shows which origin is answering while production's alias is settled.
    private let environments: [(String, IntentEnvironment)] = [
        ("production", .production),
        ("wdts project", .custom(URL(string: "https://trainient-api-server-wdts.vercel.app/api")!)),
    ]

    @State private var probes: [String: IntentAPIClient.HealthProbe] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                Text("API")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(.white)
                ForEach(environments, id: \.0) { name, environment in
                    row(name: name, baseURL: environment.baseURL, probe: probes[name])
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 40)
        }
        .task { await runProbes() }
    }

    private func row(name: String, baseURL: URL, probe: IntentAPIClient.HealthProbe?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name.uppercased())
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(white: 0.55))
            Text(baseURL.absoluteString + "/healthz")
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(Color(white: 0.7))
            Text(summary(probe))
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white)
            if let error = probe?.error {
                Text(error.localizedDescription)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(3)
            }
        }
    }

    private func summary(_ probe: IntentAPIClient.HealthProbe?) -> String {
        guard let probe else { return "checking..." }
        let ms = Int((probe.latency / .milliseconds(1)).rounded())
        let status = probe.statusCode.map { "HTTP \($0)" } ?? "no response"
        let body = probe.status.map { " \"\($0)\"" } ?? ""
        return "\(status)\(body) · \(ms) ms"
    }

    private func runProbes() async {
        // In parallel: CI screenshots a few seconds after launch.
        await withTaskGroup(of: (String, IntentAPIClient.HealthProbe).self) { group in
            for (name, environment) in environments {
                group.addTask { (name, await IntentAPIClient(environment: environment).probeHealth()) }
            }
            for await (name, probe) in group {
                probes[name] = probe
                log(name, probe)
            }
        }
    }

    private func log(_ name: String, _ probe: IntentAPIClient.HealthProbe) {
        appLog.info("""
            healthz \(name, privacy: .public) \(probe.baseURL.absoluteString, privacy: .public): \
            status=\(probe.statusCode ?? -1) body=\(probe.status ?? "-", privacy: .public) \
            latency=\(probe.latency.description, privacy: .public) \
            error=\(probe.error?.localizedDescription ?? "-", privacy: .public)
            """)
    }
}
