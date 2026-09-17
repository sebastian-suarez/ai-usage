//
//  AI_usageApp.swift
//  AI usage
//
//  Created by Sebastian Suarez on 7/18/26.
//

import Foundation
import SwiftUI

@main
struct AI_usageApp: App {
    @State private var store: UsageStore

    init() {
        let store = UsageStore(
            providers: ProviderRegistry.defaultProviders(),
            defaults: .standard
        )
        _store = State(initialValue: store)

        // Unit tests run inside the app host; keep their provider traffic fully stubbed.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            store.startAutoRefresh()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            LimitsPanel(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
