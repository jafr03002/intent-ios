import SwiftUI

/// Lets a screen hide the shell's tab bar while it is on screen (the web hides the
/// bottom nav on full-screen flows like the weekly check-in). Any view in a tab's
/// NavigationStack - including pushed destinations - can opt in with
/// `.hidesIntentTabBar()`; MainTabView reads the preference.
struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func hidesIntentTabBar(_ hidden: Bool = true) -> some View {
        preference(key: HidesTabBarKey.self, value: hidden)
    }
}
