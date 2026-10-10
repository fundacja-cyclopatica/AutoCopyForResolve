import AppKit
import SDCardOrganizerCore

/// Obraz i kolor ikony aplikacji w pasku menu według ustawień.
///
/// Ikony systemowe są „szablonowe” (template): bez wymuszonego koloru macOS sam rysuje je
/// na biało na ciemnym pasku menu i na czarno na jasnym.
enum MenuBarIcon {
    /// Wysokość ikony w pasku menu (punkty).
    static let height: CGFloat = 18

    private static let accent = NSColor(red: 249/255, green: 169/255, blue: 2/255, alpha: 1)
    private static var customCache: (path: String, isTemplate: Bool, image: NSImage)?

    /// Ikona systemowa jako szablon (kolor dopasowany do paska menu).
    static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "SD Card Organizer")
        image?.isTemplate = true
        return image
    }

    /// Własna ikona przeskalowana do wysokości paska menu (z pamięcią podręczną).
    static func customImage(at path: String, isTemplate: Bool) -> NSImage? {
        if let cached = customCache, cached.path == path, cached.isTemplate == isTemplate {
            return cached.image
        }
        guard let source = NSImage(contentsOfFile: path),
              source.size.width > 0, source.size.height > 0,
              let image = source.copy() as? NSImage else {
            return nil
        }
        let aspect = source.size.width / source.size.height
        image.size = NSSize(width: min(height * aspect, height * 2), height: height)
        image.isTemplate = isTemplate
        customCache = (path, isTemplate, image)
        return image
    }

    /// Wymuszony kolor ikony; `nil` — kolor dopasowany do paska menu.
    static func tint(for style: MenuBarIconStyle, hasCards: Bool) -> NSColor? {
        switch style {
        case .automatic, .custom: return nil
        case .white: return .white
        case .black: return .black
        case .accent: return hasCards ? accent : nil
        }
    }
}
