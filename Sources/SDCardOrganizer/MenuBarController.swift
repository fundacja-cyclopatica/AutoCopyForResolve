import Foundation
import AppKit
import Combine
import SDCardOrganizerCore

/// Kontroler ikony w pasku menu systemowym (NSStatusItem).
/// - Lewy przycisk myszy: natychmiastowe otwarcie okna głównego
/// - Prawy przycisk myszy: menu podręczne (status kart, ustawienia, zakończenie)
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()

    public init(model: AppModel) {
        self.model = model
        super.init()
        setupStatusItem()
        observeModel()
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

        if model.isGlobalCopying {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill", accessibilityDescription: "Zgrywanie")
            button.title = " \(Int(model.overallProgress * 100))%"
        } else {
            let symbolName = model.cardConfigs.isEmpty ? "externaldrive" : "externaldrive.fill.badge.checkmark"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SD Organizer")
            button.title = ""
        }
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
            // Lewy przycisk -> Natychmiastowe otwarcie okna głównego
            openMainWindow()
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
                let countText = config.isCopying ? "• zgrywanie…" : "• \(config.filteredFiles.count) plików"
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
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitAppAction() {
        NSApplication.shared.terminate(nil)
    }

    private func openMainWindow() {
        NotificationCenter.default.post(name: AppModel.showMainWindowNotification, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}
