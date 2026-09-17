import AppKit
import ServiceManagement
import SwiftUI

struct LimitsPanel: View {
    let store: UsageStore

    @State private var loginItem = LoginItemModel()
    @State private var viewedProviderID: String

    init(store: UsageStore) {
        self.store = store
        _viewedProviderID = State(
            initialValue: store.selection?.providerID ?? store.providers.first?.id ?? ""
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Provider", selection: $viewedProviderID) {
                ForEach(store.providers, id: \.id) { provider in
                    Text(provider.displayName)
                        .tag(provider.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Divider()

            providerContent

            Divider()

            loginItemControls

            footer
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            loginItem.refresh()

            if let selectedProviderID = store.selection?.providerID,
               store.providers.contains(where: { $0.id == selectedProviderID }) {
                viewedProviderID = selectedProviderID
            }

            Task {
                await store.refreshAll()
            }
        }
    }

    @ViewBuilder
    private var providerContent: some View {
        switch store.providerStates[viewedProviderID] ?? .loading {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading usage…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96)

        case let .connected(limits, _):
            if limits.isEmpty {
                Text("No usage limits are available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                VStack(spacing: 0) {
                    ForEach(limits) { limit in
                        Button {
                            store.select(providerID: viewedProviderID, limitID: limit.id)
                        } label: {
                            LimitRow(
                                limit: limit,
                                isSelected: store.selection == LimitSelection(
                                    providerID: viewedProviderID,
                                    limitID: limit.id
                                )
                            )
                        }
                        .buttonStyle(.plain)

                        if limit.id != limits.last?.id {
                            Divider()
                        }
                    }
                }
            }

        case let .disconnected(message):
            Text(message)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 96)
        }
    }

    private var loginItemControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Start at login",
                isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(loginItem.needsApproval)

            if loginItem.needsApproval {
                HStack(spacing: 4) {
                    Text("Turned off in System Settings.")
                    Button("Open Login Items…") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let message = loginItem.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if case let .connected(_, asOf) = store.providerStates[viewedProviderID] {
                Text("Updated \(asOf, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                Task {
                    await store.refreshAll()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help("Refresh usage")
            .disabled(store.isRefreshing)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
