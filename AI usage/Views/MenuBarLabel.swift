import SwiftUI

struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        Text(store.menuBarText)
            .monospacedDigit()
            .accessibilityLabel("AI Usage")
            .accessibilityValue(
                store.menuBarText == "—" ? "Usage unavailable" : "\(store.menuBarText) used"
            )
    }
}
