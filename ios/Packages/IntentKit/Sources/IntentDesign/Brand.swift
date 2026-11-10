#if canImport(SwiftUI) // Apple-only module; compiles empty on Linux so `swift test` works in WSL
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// The Intent brand: the white sun (web `src/assets/intent-sun.png`, from
// docs/design/references/intent-logo.png) and the "Intent" wordmark beside it.
// White on transparent, so it sits straight on black or the dashboard wash.

public enum IntentBrand {
    /// The white sun as a template-free `Image` (it is already white). Nil only if
    /// the resource is missing from the bundle.
    @MainActor public static let sunImage: Image? = {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "intent-sun", withExtension: "png")
            ?? bundle.url(forResource: "intent-sun", withExtension: "png", subdirectory: "Images")
        guard let url, let data = try? Data(contentsOf: url) else {
            IntentDesign.log.error("intent-sun.png missing from IntentDesign resources")
            return nil
        }
        #if canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }()
}

/// The white Intent sun at `size` points.
public struct IntentSunMark: View {
    private let size: CGFloat
    public init(size: CGFloat = 20) { self.size = size }

    public var body: some View {
        Group {
            if let image = IntentBrand.sunImage {
                image.resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "sun.max").resizable().scaledToFit().foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The dashboard's `BrandMark`: the 20pt sun and "Intent" in white, 7pt apart.
public struct IntentBrandMark: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 7) {
            IntentSunMark(size: 20)
            Text("Intent")
                .font(.intent(16, .regular))
                .tracking(-0.005 * 16)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Intent")
    }
}
#endif
