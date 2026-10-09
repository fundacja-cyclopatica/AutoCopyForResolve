import SwiftUI

@main
struct SDCardOrganizerApp: App {
    @StateObject private var model: AppModel
    private var menuBarController: MenuBarController

    init() {
        let appModel = AppModel()
        _model = StateObject(wrappedValue: appModel)
        self.menuBarController = MenuBarController(model: appModel)
    }

    var body: some Scene {
        // Pełne okno aplikacji.
        WindowGroup("SD Card Organizer", id: "main") {
            MainWindow(model: model)
                .frame(minWidth: 680, minHeight: 560)
                .onReceive(NotificationCenter.default.publisher(for: AppModel.showMainWindowNotification)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.canBecomeKey {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
        }

        // Okno ustawień.
        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 420)
        }
    }
}

