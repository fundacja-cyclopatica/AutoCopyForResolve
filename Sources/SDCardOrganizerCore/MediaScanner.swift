import Foundation

/// Kategoria materiału, decydująca o docelowym podkatalogu.
public enum MediaCategory: String, CaseIterable, Codable {
    case video
    case audio
    case photo

    /// Rozszerzenia (bez kropki) przypisane do każdej kategorii.
    public static func extensions(for category: MediaCategory) -> Set<String> {
        switch category {
        case .video: return ["mov", "mp4", "mxf", "braw", "r3d", "m4v", "avi", "mkv", "mpg", "mpeg", "mts", "m2ts"]
        case .audio: return ["wav", "mp3", "aac", "aiff", "aif", "m4a", "flac"]
        case .photo: return ["jpg", "jpeg", "png", "tiff", "tif", "heic", "dng", "cr2", "cr3", "nef", "arw", "rw2", "orf", "raw"]
        }
    }

    /// Kategoria dla danego pliku (na podstawie rozszerzenia).
    public static func category(for url: URL) -> MediaCategory? {
        let ext = url.pathExtension.lowercased()
        if extensions(for: .video).contains(ext) { return .video }
        if extensions(for: .audio).contains(ext) { return .audio }
        if extensions(for: .photo).contains(ext) { return .photo }
        return nil
    }

    /// Nazwa podkatalogu odpowiadająca kategorii.
    public var directoryName: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .photo: return "Zdjęcia"
        }
    }
}

/// Pojedynczy plik materiału wybrany do zgrywania.
public struct MediaFile: Hashable, Identifiable {
    public let url: URL
    public let category: MediaCategory
    public var id: String { url.path }

    public init(url: URL, category: MediaCategory) {
        self.url = url
        self.category = category
    }
}

/// Przeszukuje nośnik źródłowy i zwraca pasujące pliki, pogrupowane wg kategorii.
public struct MediaScanner {
    public let filter: FileTypeFilter

    public init(enabledExtensions: Set<String>) {
        self.filter = FileTypeFilter(enabledExtensions: enabledExtensions)
    }

    /// Skanuje rekursywnie katalog źródłowy i zwraca pliki pasujące do filtra.
    public func scan(volumeRoot: URL) throws -> [MediaFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        guard let enumerator = FileManager.default.enumerator(
            at: volumeRoot,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return []
        }

        var results: [MediaFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            guard filter.isIncluded(url) else { continue }
            guard let category = MediaCategory.category(for: url) else { continue }
            results.append(MediaFile(url: url, category: category))
        }
        return results.sorted { $0.url.path < $1.url.path }
    }
}
