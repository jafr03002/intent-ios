#if canImport(SwiftUI) // Apple-only module; compiles empty on Linux so `swift test` works in WSL
import CoreText
import Foundation
import os

/// Intent's "Sessions" design system: a native port of TrainientAppDesign.md and
/// artifacts/traintent/src/theme/tokens.ts.
///
/// - Colours: `Color.intent.card`, `.foregroundStyle(.intent.mutedForeground)`,
///   `IntentColorToken` (the token table, named as on the web).
/// - Shape and spacing: `IntentRadius`, `IntentSpacing`, `IntentMetrics`.
/// - Type: `.intentText(.screenTitle)` / `Font.intent(15, .medium)`. Inter only,
///   so call `IntentDesign.registerFonts()` once at launch.
/// - Components: `IntentPage`, `IntentPageHeader`, `IntentCard`, the pill button
///   styles, `IntentOptionCard`, `IntentPill`, `IntentBadge`, `IntentIconButton`,
///   `IntentGroupedSection` + `IntentGroupedRow`, `IntentDivider`, `IntentTabBar`.
public enum IntentDesign {
    static let log = Logger(subsystem: "com.jakobfreij.Intent", category: "design")

    /// Registers the bundled Inter faces with Core Text for this process. SwiftPM
    /// resources can't use Info.plist `UIAppFonts`, so this must run before any
    /// `Font.intent` text renders. Safe to call any number of times, from any thread:
    /// the work runs once and later calls return the first result.
    ///
    /// - Returns: `true` when every Inter weight the type scale uses is available.
    @discardableResult
    public static func registerFonts() -> Bool {
        fontRegistration
    }

    /// Whether Inter is registered (without trying to register it).
    public static var fontsAvailable: Bool {
        IntentFontWeight.allCases.allSatisfy { isInstalled($0.postScriptName) }
    }

    private static let fontRegistration: Bool = {
        let bundle = Bundle.module
        // `.process` flattens resources into the bundle root; look in Fonts/ too in
        // case a toolchain keeps the folder.
        let urls = (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        if urls.isEmpty {
            log.error("Inter: no .ttf files found in \(bundle.bundlePath, privacy: .public)")
            return false
        }

        for url in urls {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                log.debug("Inter: registered \(url.lastPathComponent, privacy: .public)")
                continue
            }
            let cfError = error?.takeRetainedValue()
            let code = cfError.map { CFErrorGetCode($0) } ?? 0
            if code == CTFontManagerError.alreadyRegistered.rawValue {
                continue
            }
            let message = cfError.map { CFErrorCopyDescription($0) as String } ?? "unknown error"
            log.error("Inter: failed to register \(url.lastPathComponent, privacy: .public): \(message, privacy: .public)")
        }

        let missing = IntentFontWeight.allCases.map(\.postScriptName).filter { !isInstalled($0) }
        if missing.isEmpty {
            log.info("Inter: registered \(urls.count) faces, all weights available")
            return true
        }
        log.error("Inter: missing after registration: \(missing.joined(separator: ", "), privacy: .public); text falls back to the system font")
        return false
    }()

    /// Core Text substitutes a fallback font for unknown names, so compare the
    /// PostScript name of what it actually returned.
    private static func isInstalled(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }
}
#endif
