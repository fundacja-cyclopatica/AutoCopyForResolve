import Foundation
import AppKit
import Combine
import SDCardOrganizerCore

/// Kontroler ikony w pasku menu systemowym (NSStatusItem).
/// - Lewy przycisk myszy: wysuwa / chowa panel z kartami (jak widget)
/// - Prawy przycisk myszy: menu podręczne (status kart, panel, ustawienia, historia, zakończenie)
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
        Publishers.Merge4(
            model.$cardConfigs.map { _ in () },
            model.$isGlobalCopying.map { _ in () },
            model.$overallProgress.map { _ in () },
            model.$settings.map { _ in () }
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

        let settings = model.settings
        let hasCards = !model.cardConfigs.isEmpty

        var image: NSImage?
        if settings.menuBarIconStyle == .custom, let path = settings.customMenuBarIconPath {
            image = MenuBarIcon.customImage(at: path, isTemplate: settings.customMenuBarIconIsTemplate)
        }
        if image == nil {
            if model.isGlobalCopying {
                image = MenuBarIcon.symbol("arrow.triangle.2.circlepath.circle.fill")
            } else {
                image = MenuBarIcon.symbol(hasCards ? "sdcard.fill" : "sdcard")
            }
        }
        button.image = image
        button.imagePosition = .imageLeading
        button.title = model.isGlobalCopying ? " \(Int(model.overallProgress * 100))%" : ""
        // Bez wymuszonego koloru ikona szablonowa jest biała na ciemnym pasku i czarna na jasnym.
        button.contentTintColor = MenuBarIcon.tint(for: settings.menuBarIconStyle, hasCards: hasCards)
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

        let showPanelItem = NSMenuItem(title: "Pokaż panel kart", action: #selector(showPanelAction), keyEquivalent: "")
        showPanelItem.target = self
        menu.addItem(showPanelItem)

        let openSettingsItem = NSMenuItem(title: "Ustawienia…", action: #selector(openSettingsAction), keyEquivalent: ",")
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        let openHistoryItem = NSMenuItem(title: "Historia zgrań…", action: #selector(openHistoryAction), keyEquivalent: "")
        openHistoryItem.target = self
        menu.addItem(openHistoryItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Zakończ", action: #selector(quitAppAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func showPanelAction() {
        panelController.show()
    }

    @objc private func openSettingsAction() {
        panelController.hide()
        model.showSettingsWindow(tab: .settings)
    }

    @objc private func openHistoryAction() {
        panelController.hide()
        model.showSettingsWindow(tab: .history)
    }

    @objc private func quitAppAction() {
        NSApplication.shared.terminate(nil)
    }
}
