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
                if model.isCopying {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            if model.isCopying {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zgrywanie w toku: \(Int(model.progress * 100))%")
                        .font(.subheadline.bold())
                    ProgressView(value: model.progress)
                    Text(model.currentFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                Divider()
            }

            if model.volumeMonitor.removableVolumes.isEmpty {
                Label("Brak podłączonej karty SD", systemImage: "sdcard")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wykryte karty:").font(.caption).foregroundStyle(.secondary)
                    Picker("Karta:", selection: $model.selectedVolume) {
                        ForEach(model.volumeMonitor.removableVolumes) { volume in
                            Text(volume.name).tag(Volume?.some(volume))
                        }
                    }
                    .frame(width: 220)

                    if !model.scanResults.isEmpty && !model.isCopying {
                        Text("\(model.scanResults.count) plików gotowych do zgrania")
                            .font(.caption2)
                            .foregroundStyle(.green)
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

