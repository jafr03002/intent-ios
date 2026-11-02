import SwiftUI
import IntentDesign
import os

let appLog = Logger(subsystem: "com.jakobfreij.Intent", category: "app")

@main
struct IntentApp: App {
    private let launchScreen: DebugScreen
    @State private var services: AppServices

    init() {
        let screen = DebugScreen.fromLaunchArguments()
        launchScreen = screen
        IntentDesign.registerFonts()
        _services = State(initialValue: AppServices())
        appLog.info("Intent launched, screen=\(screen.rawValue, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            RootView(screen: launchScreen)
                .environment(services)
                .preferredColorScheme(.dark)
        }
    }
}
