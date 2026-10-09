import SwiftUI

@main
struct SDCardOrganizerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        // Aplikacja w pasku menu — zawsze działa w tle.
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            if model.isCopying {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    Text("\(Int(model.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                }
            } else {
                Label("SD Organizer", systemImage: model.volumeMonitor.removableVolumes.isEmpty ? "externaldrive" : "externaldrive.fill.badge.checkmark")
            }
        }

        // Pełne okno aplikacji.
        WindowGroup("SD Card Organizer", id: "main") {
            MainWindow(model: model)
                .frame(minWidth: 680, minHeight: 560)
        }

        // Okno ustawień.
        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 420)
        }
    }
}

