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

    public init(destinationRoot: String, projectName: String, date: Date = Date()) {
        let safeName = ProjectLayout.sanitize(projectName)
        let folderName = ProjectLayout.folderName(projectName: safeName, date: date)
        let base = URL(fileURLWithPath: destinationRoot, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)

        self.root = base
        self.projectName = safeName
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

    /// Tworzy wszystkie katalogi projektu na dysku.
    public func createDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: videoDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: photoDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: daVinciDir, withIntermediateDirectories: true)
    }

    /// Ścieżka pliku projektu DaVinci Resolve.
    public func drpFileURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let name = "\(df.string(from: Date()))_\(projectName).drp"
        return daVinciDir.appendingPathComponent(name)
    }

    /// Ścieżka manifestu JSON z metadanymi projektu (zawsze tworzona, nawet bez szablonu .drp).
    public func manifestURL() -> URL {
        daVinciDir.appendingPathComponent("project_manifest.json")
    }
}
