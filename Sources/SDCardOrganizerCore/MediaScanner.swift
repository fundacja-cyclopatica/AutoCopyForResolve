import Foundation

/// Kategoria materiału, decydująca o docelowym podkatalogu.
public enum MediaCategory: String, CaseIterable, Codable {
    case video
    case audio
    case photo

    /// Rozszerzenia (bez kropki) przypisane do każdej kategorii.
    public static func extensions(for category: MediaCategory) -> Set<String> {
        MediaFormats.extensions(for: category)
    }

    /// Kategoria dla danego pliku (na podstawie rozszerzenia).
    public static func category(for url: URL) -> MediaCategory? {
        let ext = url.pathExtension.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
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
    public let size: Int64
    public let date: Date
    public let dayString: String // format "yyyy-MM-dd" — klucz wewnętrzny (sortowanie/grupowanie)

    public var id: String { url.path }

    public init(url: URL, category: MediaCategory, size: Int64 = 0, date: Date = Date()) {
        self.url = url
        self.category = category
        self.size = size
        self.date = date

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        self.dayString = df.string(from: date)
    }
}

/// Podsumowanie materiałów z konkretnego dnia.
public struct DaySummary: Identifiable, Hashable {
    public let dayString: String // klucz wewnętrzny "yyyy-MM-dd"
    public let fileCount: Int
    public let videoCount: Int
    public let audioCount: Int
    public let photoCount: Int
    public let totalBytes: Int64

    public var id: String { dayString }

    public init(dayString: String, files: [MediaFile]) {
        self.dayString = dayString
        self.fileCount = files.count
        self.videoCount = files.filter { $0.category == .video }.count
        self.audioCount = files.filter { $0.category == .audio }.count
        self.photoCount = files.filter { $0.category == .photo }.count
        self.totalBytes = files.reduce(0) { $0 + $1.size }
    }

    /// Przyjazny tekst daty do wyświetlenia: "Dzisiaj" / "Wczoraj" / "08.10.2026".
    public var displayText: String {
        let calendar = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        guard let dayDate = df.date(from: dayString) else { return dayString }

        if calendar.isDateInToday(dayDate) { return "Dzisiaj" }
        if calendar.isDateInYesterday(dayDate) { return "Wczoraj" }

        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "dd.MM.yyyy"
        outFormatter.locale = Locale(identifier: "pl_PL")
        return outFormatter.string(from: dayDate)
    }
}

/// Przeszukuje nośnik źródłowy i zwraca pasujące pliki, pogrupowane wg kategorii i dat.
public struct MediaScanner {
    public let filter: FileTypeFilter

    public init(enabledExtensions: Set<String>) {
        self.filter = FileTypeFilter(enabledExtensions: enabledExtensions)
    }

    /// Katalogi systemowe kamer z miniaturami i metadanymi, które nie są materiałem
    /// (np. Sony `M4ROOT/THMBNL` z miniaturami JPG każdego klipu). Porównanie bez
    /// rozróżniania wielkości liter.
    public static let excludedDirectoryNames: Set<String> = ["THMBNL", "AVF_INFO", "CANONMSC"]

    /// Skanuje rekursywnie katalog źródłowy i zwraca pliki pasujące do filtra wraz z datami i rozmiarami.
    public func scan(volumeRoot: URL) throws -> [MediaFile] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey
        ]
        // Nie używamy .skipsPackageDescendants, ponieważ foldery kamer (np. PRIVATE / AVCHD) bywają traktowane jako pakiety
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

        guard let enumerator = FileManager.default.enumerator(
            at: volumeRoot,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return []
        }

        var results: [MediaFile] = []
        for case let url as URL in enumerator {
            if Self.excludedDirectoryNames.contains(url.lastPathComponent.uppercased()),
               (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                enumerator.skipDescendants()
                continue
            }

            let ext = url.pathExtension.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ext.isEmpty else { continue }
            guard filter.isIncluded(url) else { continue }
            guard let category = MediaCategory.category(for: url) else { continue }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let size: Int64
            if let s = values?.fileSize {
                size = Int64(s)
            } else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                size = (attrs?[.size] as? Int64) ?? 0
            }

            let date = extractDate(from: url, resourceValues: values)
            results.append(MediaFile(url: url, category: category, size: size, date: date))
        }
        return results.sorted { $0.date < $1.date }
    }

    /// Pobiera datę z metadanych pliku lub nazwy (np. DSC0001..., DJI_20260606..., VID_20260606...).
    private func extractDate(from url: URL, resourceValues: URLResourceValues?) -> Date {
        if let creationDate = resourceValues?.creationDate {
            return creationDate
        }
        if let modDate = resourceValues?.contentModificationDate {
            return modDate
        }
        if let parsedFromFilename = parseDateFromFilename(url.lastPathComponent) {
            return parsedFromFilename
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let date = attrs[.modificationDate] as? Date {
                return date
            }
            if let date = attrs[.creationDate] as? Date {
                return date
            }
        }
        return Date()
    }

    /// Próbuje sparsować datę z typowych nazw plików kamer (DJI_20260606132901_..., 20260606_..., 2026-06-06...).
    private func parseDateFromFilename(_ filename: String) -> Date? {
        let patterns = [
            "yyyyMMdd_HHmmss",
            "yyyyMMddHHmmss",
            "yyyy-MM-dd_HH-mm-ss",
            "yyyyMMdd",
            "yyyy-MM-dd"
        ]

        let cleaned = filename.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        let parts = cleaned.components(separatedBy: "_")

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        for part in parts {
            for pattern in patterns {
                df.dateFormat = pattern
                if let date = df.date(from: part) {
                    return date
                }
            }
        }
        return nil
    }
}
