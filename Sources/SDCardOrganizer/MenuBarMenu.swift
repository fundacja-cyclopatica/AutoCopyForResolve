import SwiftUI
import AppKit

/// Menu z paska menu — szybki dostęp do najważniejszych akcji i statusu w czasie rzeczywistym.
struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SD Card Organizer")
                    .font(.headline)
                Spacer()
                if model.isGlobalCopying {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            if model.isGlobalCopying {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zgrywanie w toku: \(Int(model.overallProgress * 100))%")
                        .font(.subheadline.bold())
                    ProgressView(value: model.overallProgress)
                }
                .padding(.vertical, 2)
                Divider()
            }

            if model.cardConfigs.isEmpty {
                Label("Brak podłączonej karty SD", systemImage: "sdcard")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wykryte karty (\(model.cardConfigs.count)):").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.cardConfigs) { config in
                        HStack {
                            Image(systemName: "sdcard.fill")
                                .font(.caption)
                                .foregroundStyle(config.isEnabled ? Color.accentColor : Color.secondary)
                            Text("\(config.cameraLabel.isEmpty ? config.volumeName : config.cameraLabel) (\(config.volumeName))")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            if config.isCopying {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("\(config.filteredFiles.count) plików")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Otwórz okno główne", systemImage: "macwindow")
            }

            Button {
                openSettings()
            } label: {
                Label("Ustawienia…", systemImage: "gear")
            }

            Divider()

            Button("Zakończ") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .onReceive(NotificationCenter.default.publisher(for: AppModel.showMainWindowNotification)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

