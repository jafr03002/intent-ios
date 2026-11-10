import IntentDesign
import SwiftUI

/// The storm light behind the top of the calendar (the web reuses the dashboard's
/// `DashboardWash` with `sunX`): grey at the top fading into black, light falling
/// from above the selected day's column and a slowly drifting teal pool under it.
/// A SwiftUI approximation of the WebGL shader - no caustics or grain. The one
/// sanctioned "glow" in Sessions (dashboard top + calendar top only).
struct CalendarWash: View {
    /// 0...1 across the screen: the selected column's centre.
    var sunX: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let drift = CGFloat(sin(t * 0.21)) * 0.025
                let breathe = 1 + CGFloat(sin(t * 0.33)) * 0.06
                ZStack {
                    // The ground: grey at the top, into black.
                    LinearGradient(
                        stops: [
                            .init(color: Color(.sRGB, red: 0.184, green: 0.208, blue: 0.220), location: 0),
                            .init(color: Color(.sRGB, red: 0.106, green: 0.133, blue: 0.141), location: 0.38),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                    // Shafts from a source above the screen, over the selected column.
                    EllipticalGradient(
                        colors: [Color(.sRGB, red: 0.78, green: 0.86, blue: 0.88).opacity(0.22), .clear],
                        center: UnitPoint(x: 0.5, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.55)
                        .frame(width: w * 0.9, height: h * 1.3)
                        .position(x: w * sunX, y: h * 0.05)
                    // The teal pool behind the grid's top rows.
                    EllipticalGradient(
                        colors: [Color.intent.sessionsCyan.opacity(0.30), Color.intent.sessionsCyan.opacity(0.08), .clear],
                        center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: w * 1.1 * breathe, height: h * 0.62 * breathe)
                        .position(x: w * (0.5 + (sunX - 0.5) * 0.85 + drift), y: h * 0.36)
                        .blendMode(.screen)
                }
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .animation(.spring(response: 0.9, dampingFraction: 0.9), value: sunX)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
