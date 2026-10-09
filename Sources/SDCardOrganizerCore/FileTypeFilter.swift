import Foundation

/// Decyduje, czy plik powinien zostać zgrywany na podstawie wybranych rozszerzeń.
public struct FileTypeFilter {
    public let enabledExtensions: Set<String>

    public init(enabledExtensions: Set<String>) {
        // Normalizacja: małe litery, bez kropki.
        self.enabledExtensions = Set(enabledExtensions.map {
            $0.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")
        })
    }

    /// Czy dany plik pasuje do wybranego filtra typów.
    public func isIncluded(_ url: URL) -> Bool {
        if enabledExtensions.contains("*") { return true }
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        return enabledExtensions.contains(ext)
    }

    /// Rozszerzenie (bez kropki, małe litery) pliku.
    public static func normalizedExtension(of url: URL) -> String {
        url.pathExtension.lowercased()
    }
}
