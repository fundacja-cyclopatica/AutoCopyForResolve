import AppKit
import QuartzCore
import SwiftUI

/// Panel bez ramki, który może przyjmować klawiaturę (pole nazwy projektu, Esc),
/// nie aktywując przy tym aplikacji — DaVinci Resolve zostaje na pierwszym planie.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Panel wysuwany z prawej krawędzi ekranu pod ikoną w pasku menu (jak widget).
///
/// - pojawia się nad wszystkimi oknami, na każdym biurku i nad aplikacjami na pełnym ekranie,
/// - chowa się po kliknięciu poza panelem (w innej aplikacji, na biurku lub w oknie głównym),
///   a także po „Zamknij”, Esc albo ponownym kliknięciu ikony,
/// - dopasowuje wysokość do treści (liczby kart) z płynną animacją, trzymając górną krawędź
///   pod paskiem menu; gdy treść nie mieści się na ekranie, karty się przewijają.
final class StatusPanelController {
    private let model: AppModel
    private let panel: FloatingPanel
    private let screenProvider: () -> NSScreen?
    private var contentHeight: CGFloat = 420
    private(set) var isVisible = false
    /// Trwa okno systemowe otwarte z panelu (wybór folderu, alert) — kliknięcia w nim
    /// nie mogą chować panelu.
    private var isPresentingModal = false
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    /// Wywoływane po pokazaniu / schowaniu panelu (np. do podświetlenia ikony).
    var onVisibilityChange: ((Bool) -> Void)?

    private static let screenMargin: CGFloat = 8
    private static let slideDuration: TimeInterval = 0.28
    private static let resizeDuration: TimeInterval = 0.3

    /// - Parameter screenProvider: ekran, na którym jest ikona w pasku menu.
    init(model: AppModel, screenProvider: @escaping () -> NSScreen?) {
        self.model = model
        self.screenProvider = screenProvider
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelTheme.width, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let root = MenuBarPanelView(
            model: model,
            onClose: { [weak self] in self?.hide() },
            onHeightChange: { [weak self] height in self?.updateContentHeight(height) },
            performModal: { [weak self] action in self?.performModal(action) }
        )
        let hosting = NSHostingView(rootView: root)
        // Rozmiar okna ustala kontroler (animacja wysokości), nie SwiftUI.
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible, let screen = screenProvider() ?? NSScreen.main else { return }
        isVisible = true

        let target = targetFrame(height: contentHeight, on: screen)
        var start = target
        start.origin.x = screen.frame.maxX + 4
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        animate(duration: Self.slideDuration, timing: .easeOut) {
            self.panel.animator().setFrame(target, display: true)
            self.panel.animator().alphaValue = 1
        } completion: {
            self.panel.invalidateShadow()
        }
        startMonitoringOutsideClicks()
        onVisibilityChange?(true)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        stopMonitoringOutsideClicks()

        var end = panel.frame
        end.origin.x = (panel.screen ?? NSScreen.main)?.frame.maxX ?? end.maxX
        end.origin.x += 4
        animate(duration: Self.slideDuration, timing: .easeIn) {
            self.panel.animator().setFrame(end, display: true)
            self.panel.animator().alphaValue = 0
        } completion: {
            // Panel mógł zostać ponownie otwarty w trakcie animacji.
            if !self.isVisible {
                self.panel.orderOut(nil)
            }
        }
        onVisibilityChange?(false)
    }

    /// Okna systemowe (wybór folderu, alerty) mają niższy poziom niż panel — na czas ich
    /// wyświetlania panel schodzi na zwykły poziom, żeby ich nie zasłaniać.
    func performModal(_ action: () -> Void) {
        isPresentingModal = true
        defer { isPresentingModal = false }
        panel.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        action()
        panel.level = .statusBar
        if isVisible {
            panel.orderFrontRegardless()
        }
    }

    // MARK: – Kliknięcia poza panelem

    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Kliknięcia w innych aplikacjach i na biurku.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self, !self.isPresentingModal else { return }
            self.hide()
        }

        // Kliknięcia w oknach tej aplikacji. Panel chowamy tylko przy kliknięciu w zwykłe
        // okno (okno główne) — nie w sam panel, jego menu rozwijane ani ikonę w pasku menu
        // (ikona sama przełącza panel).
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, !self.isPresentingModal,
                  let window = event.window,
                  window !== self.panel,
                  window.canBecomeMain else {
                return event
            }
            self.hide()
            return event
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        globalClickMonitor = nil
        localClickMonitor = nil
    }

    // MARK: – Wysokość

    private func updateContentHeight(_ height: CGFloat) {
        let rounded = ceil(height)
        guard rounded > 0, abs(rounded - contentHeight) > 0.5 else { return }
        contentHeight = rounded
        guard isVisible, let screen = panel.screen ?? screenProvider() ?? NSScreen.main else { return }

        let target = targetFrame(height: rounded, on: screen)
        animate(duration: Self.resizeDuration, timing: .easeInEaseOut) {
            self.panel.animator().setFrame(target, display: true)
        } completion: {
            self.panel.invalidateShadow()
        }
    }

    /// Prawy górny róg obszaru roboczego ekranu, tuż pod paskiem menu.
    private func targetFrame(height: CGFloat, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let maxHeight = visible.height - 2 * Self.screenMargin
        let panelHeight = min(height, maxHeight)
        return NSRect(
            x: visible.maxX - PanelTheme.width - Self.screenMargin,
            y: visible.maxY - Self.screenMargin - panelHeight,
            width: PanelTheme.width,
            height: panelHeight
        )
    }

    private func animate(
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName,
        changes: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            context.allowsImplicitAnimation = true
            changes()
        } completionHandler: {
            completion()
        }
    }
}
