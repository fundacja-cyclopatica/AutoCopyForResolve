import Foundation

/// Generuje unikalne nazwy plików, gdy dwie karty zawierają pliki o identycznych nazwach.
///
/// Strategia: `nazwa.ext` -> `nazwa_1.ext` -> `nazwa_2.ext` ...
public struct UniqueNamer {
    /// Podaje ścieżkę pliku docelowego, która nie koliduje z żadnym istniejącym plikiem
    /// w katalogu docelowym. Nie tworzy pliku — tylko wylicza wolną nazwę.
    public static func uniqueURL(for url: URL, in directory: URL, existingNames: Set<String>) -> URL {
        let fileManager = FileManager.default

        var candidate = directory.appendingPathComponent(url.lastPathComponent)
        var index = 1

        while existingNames.contains(candidate.lastPathComponent) || fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(suffixedName(for: url, index: index))
            index += 1
        }
        return candidate
    }

    /// Nazwa pliku z sufiksem kolizji: `nazwa.ext` -> `nazwa_<index>.ext`.
    public static func suffixedName(for url: URL, index: Int) -> String {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        return ext.isEmpty ? "\(base)_\(index)" : "\(base)_\(index).\(ext)"
    }
}
