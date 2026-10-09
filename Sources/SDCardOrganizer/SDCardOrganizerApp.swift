import SwiftUI

@main
struct SDCardOrganizerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        // Aplikacja w pasku menu — zawsze działa w tle.
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            Label("SD Organizer", systemImage: "externaldrive.fill")
        }

        // Pełne okno aplikacji.
        WindowGroup("SD Card Organizer", id: "main") {
            MainWindow(model: model)
                .frame(minWidth: 640, minHeight: 520)
        }

        // Okno ustawień.
        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 420)
        }
    }
}
