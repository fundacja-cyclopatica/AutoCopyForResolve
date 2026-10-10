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
        // Pełne okno aplikacji. `Window` (a nie `WindowGroup`) gwarantuje jedno okno:
        // ponowne otwarcie z paska menu przywraca je zamiast tworzyć kolejne.
        // Wszystkie ustawienia są w panelu wewnątrz tego okna.
        Window("SD Card Organizer", id: AppModel.mainWindowID) {
            MainWindow(model: model)
                .frame(minWidth: 680, minHeight: 560)
        }
    }
}
