import Foundation

/// Buduje ścieżki i strukturę katalogów projektu na dysku docelowym.
///
/// Struktura:
/// ```
/// <destinationRoot>/<YYYY-MM-DD>_<NazwaProjektu>/
///   ├── Video/
///   ├── Audio/
///   ├── Zdjęcia/
///   └── DaVinci/
///       └── <YYYY-MM-DD>_<NazwaProjektu>.drp
/// ```
public struct ProjectLayout {
    public let root: URL
    public let videoDir: URL
    public let audioDir: URL
    public let photoDir: URL
    public let daVinciDir: URL
    public let projectName: String
    public let date: Date

    public init(destinationRoot: String, projectName: String, date: Date = Date()) {
        let safeName = ProjectLayout.sanitize(projectName)
        let folderName = ProjectLayout.folderName(projectName: safeName, date: date)
        let base = URL(fileURLWithPath: destinationRoot, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)

        self.root = base
        self.projectName = safeName
        self.date = date
        self.videoDir = base.appendingPathComponent("Video", isDirectory: true)
        self.audioDir = base.appendingPathComponent("Audio", isDirectory: true)
        self.photoDir = base.appendingPathComponent("Zdjęcia", isDirectory: true)
        self.daVinciDir = base.appendingPathComponent("DaVinci", isDirectory: true)
    }

    /// Usuwa znaki niedozwolone w nazwach katalogów (macOS toleruje więcej niż Windows,
    /// ale zachowujemy bezpieczny podzbiór znaków).
    public static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: invalid).joined(separator: "-")
        return components.isEmpty ? "Projekt" : components
    }

    /// Nazwa folderu projektu: `YYYY-MM-DD_Nazwa`.
    public static func folderName(projectName: String, date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return "\(df.string(from: date))_\(projectName)"
    }

    /// Odczytuje datę i nazwę z nazwy folderu projektu (`YYYY-MM-DD_Nazwa`).
    /// Zwraca `nil` dla folderów, które nie są projektami tej aplikacji.
    public static func parseFolderName(_ folderName: String) -> (date: Date, name: String)? {
        guard folderName.count > 11 else { return nil }
        let separator = folderName.index(folderName.startIndex, offsetBy: 10)
        guard folderName[separator] == "_" else { return nil }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let date = df.date(from: String(folderName[..<separator])) else { return nil }

        let name = String(folderName[folderName.index(after: separator)...])
        guard !name.isEmpty else { return nil }
        return (date, name)
    }

    /// Tworzy wszystkie katalogi projektu na dysku.
    public func createDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: videoDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: photoDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: daVinciDir, withIntermediateDirectories: true)
    }

    /// Zwraca katalog docelowy dla danej kategorii, opcjonalnie z podfolderem kamery/zastosowania.
    public func targetDirectory(for category: MediaCategory, cameraLabel: String? = nil) -> URL {
        let baseDir: URL
        switch category {
        case .video: baseDir = videoDir
        case .audio: baseDir = audioDir
        case .photo: baseDir = photoDir
        }

        guard let label = cameraLabel, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return baseDir
        }
        let safeLabel = ProjectLayout.sanitize(label)
        return baseDir.appendingPathComponent(safeLabel, isDirectory: true)
    }

    /// Ścieżka pliku projektu DaVinci Resolve.
    public func drpFileURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let name = "\(df.string(from: date))_\(projectName).drp"
        return daVinciDir.appendingPathComponent(name)
    }

    /// Ścieżka manifestu JSON z metadanymi projektu (zawsze tworzona, nawet bez szablonu .drp).
    public func manifestURL() -> URL {
        daVinciDir.appendingPathComponent("project_manifest.json")
    }
}
