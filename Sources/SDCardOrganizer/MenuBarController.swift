import Foundation
import AppKit
import Combine
import SDCardOrganizerCore

/// Kontroler ikony w pasku menu systemowym (NSStatusItem).
/// - Lewy przycisk myszy: wysuwa / chowa panel z kartami (jak widget)
/// - Prawy przycisk myszy: menu podręczne (status kart, okno główne, ustawienia, zakończenie)
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()
    private var panelController: StatusPanelController!

    public init(model: AppModel) {
        self.model = model
        super.init()
        setupStatusItem()
        panelController = StatusPanelController(model: model) { [weak self] in
            self?.statusItem.button?.window?.screen
        }
        panelController.onVisibilityChange = { [weak self] _ in
            self?.updateButton()
        }
        model.showPanelAction = { [weak self] in
            self?.panelController.show()
        }
        observeModel()

        // Po uruchomieniu od razu pokaż panel — to główny widok aplikacji.
        DispatchQueue.main.async { [weak self] in
            self?.panelController.show()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        updateButton()

        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
    }

    private func observeModel() {
        // Obserwuj zmiany stanu kart i postępu zgrywania
        Publishers.Merge3(
            model.$cardConfigs.map { _ in () },
            model.$isGlobalCopying.map { _ in () },
            model.$overallProgress.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateButton()
        }
        .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        button.highlight(panelController?.isVisible ?? false)

        if model.isGlobalCopying {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill", accessibilityDescription: "Zgrywanie")
            button.title = " \(Int(model.overallProgress * 100))%"
        } else {
            let symbolName = model.cardConfigs.isEmpty ? "sdcard" : "sdcard.fill"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SD Organizer")
            button.title = ""
        }
        // Musztardowa ikona, gdy są karty do zgrania (jak w projekcie panelu)
        button.contentTintColor = model.cardConfigs.isEmpty
            ? nil
            : NSColor(red: 249/255, green: 169/255, blue: 2/255, alpha: 1)
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            // Prawy przycisk -> Menu kontekstowe
            let menu = buildContextMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            // Po kliknięciu usuwamy przypisane menu, aby lewy przycisk znów wywoływał akcję
            DispatchQueue.main.async {
                self.statusItem.menu = nil
            }
        } else {
            // Lewy przycisk -> wysuń / schowaj panel
            panelController.toggle()
        }
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "SD Card Organizer", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        if model.isGlobalCopying {
            let progressItem = NSMenuItem(title: "⏳ Zgrywanie w toku: \(Int(model.overallProgress * 100))%", action: nil, keyEquivalent: "")
            progressItem.isEnabled = false
            menu.addItem(progressItem)
            menu.addItem(NSMenuItem.separator())
        }

        if model.cardConfigs.isEmpty {
            let noCardsItem = NSMenuItem(title: "Brak podłączonej karty SD", action: nil, keyEquivalent: "")
            noCardsItem.isEnabled = false
            menu.addItem(noCardsItem)
        } else {
            let cardsHeader = NSMenuItem(title: "Wykryte karty (\(model.cardConfigs.count)):", action: nil, keyEquivalent: "")
            cardsHeader.isEnabled = false
            menu.addItem(cardsHeader)

            for config in model.cardConfigs {
                let label = config.cameraLabel.isEmpty ? config.volumeName : "\(config.cameraLabel) (\(config.volumeName))"
                let countText = config.isCopying ? "• zgrywanie…" : "• \(PolishPlural.files(config.filteredFiles.count))"
                let cardItem = NSMenuItem(title: "  💾 \(label) \(countText)", action: nil, keyEquivalent: "")
                cardItem.isEnabled = false
                menu.addItem(cardItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let openMainItem = NSMenuItem(title: "Otwórz okno główne", action: #selector(openMainWindowAction), keyEquivalent: "o")
        openMainItem.target = self
        menu.addItem(openMainItem)

        let openSettingsItem = NSMenuItem(title: "Ustawienia…", action: #selector(openSettingsAction), keyEquivalent: ",")
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Zakończ", action: #selector(quitAppAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openMainWindowAction() {
        openMainWindow()
    }

    @objc private func openSettingsAction() {
        // Ustawienia są panelem w oknie głównym (selektor `showSettingsWindow:` nie działa od macOS 14).
        model.showMainWindow(openingSettings: true)
    }

    @objc private func quitAppAction() {
        NSApplication.shared.terminate(nil)
    }

    private func openMainWindow() {
        model.showMainWindow()
    }
}
