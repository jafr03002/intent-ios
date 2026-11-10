import SwiftUI

/// The storm light behind the top of the calendar: the web reuses the dashboard's
/// `DashboardWash` with `sunX`, and so does this - the same live shader (LiveWash),
/// its light falling over the selected day's column. The one sanctioned "glow" in
/// Sessions (dashboard top + calendar top only).
struct CalendarWash: View {
    /// 0...1 across the screen: the selected column's centre.
    var sunX: CGFloat

    var body: some View {
        LiveWash(sunX: sunX)
            .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
    }
}
