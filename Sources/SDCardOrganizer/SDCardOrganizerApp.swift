import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Aplikacja żyje w pasku menu — zamknięcie okna ustawień nie może jej kończyć.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct SDCardOrganizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    private var menuBarController: MenuBarController

    init() {
        let appModel = AppModel()
        _model = StateObject(wrappedValue: appModel)
        self.menuBarController = MenuBarController(model: appModel)
    }

    var body: some Scene {
        // Okno ustawień i historii (otwierane z panelu lub z menu ikony). `Window`, a nie
        // `WindowGroup`, gwarantuje jedno okno — ponowne otwarcie przywraca istniejące.
        // Główną formą pracy jest wysuwany panel z paska menu.
        Window("Ustawienia — SD Card Organizer", id: AppModel.settingsWindowID) {
            SettingsWindow(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}
