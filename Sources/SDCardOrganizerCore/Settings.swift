import Foundation

/// Trwałe ustawienia aplikacji, zapisywane jako JSON w Application Support.
public struct Settings: Codable, Equatable {
    /// Ścieżka do dysku/folderu docelowego, na który zgrywane są materiały.
    public var destinationRoot: String

    /// Wybrane rozszerzenia plików (bez kropki, małymi literami), np. ["mov", "mp4", "cr2", "nef"].
    /// Specjalna wartość "*" oznacza "wszystkie pliki".
    public var enabledExtensions: Set<String>

    /// Rozdzielczość projektu DaVinci Resolve, np. "1920x1080".
    public var resolution: String

    /// Liczba klatek na sekundę projektu DaVinci Resolve.
    public var frameRate: Double

    /// Czy po skopiowaniu porównywać checksum plików (wolniejsze, ale pewniejsze).
    public var verifyChecksums: Bool

    /// Ścieżka do wzorcowego pliku .drp używanego jako szablon projektu.
    /// Jeśli nil, projekt tworzy folder + manifest JSON zamiast pliku .drp.
    public var drpTemplatePath: String?

    public init(
        destinationRoot: String = "",
        enabledExtensions: Set<String> = ["mov", "mp4", "mxf", "braw", "r3d", "cr2", "cr3", "nef", "arw", "dng", "jpg", "jpeg", "png", "wav", "mp3", "aac"],
        resolution: String = "1920x1080",
        frameRate: Double = 25,
        verifyChecksums: Bool = false,
        drpTemplatePath: String? = nil
    ) {
        self.destinationRoot = destinationRoot
        self.enabledExtensions = enabledExtensions
        self.resolution = resolution
        self.frameRate = frameRate
        self.verifyChecksums = verifyChecksums
        self.drpTemplatePath = drpTemplatePath
    }

    /// Domyślna ścieżka pliku ustawień w katalogu Application Support użytkownika.
    public static func defaultSettingsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SDCardOrganizer", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

/// Ładowanie i zapisywanie ustawień na dysku.
public struct SettingsStore {
    public static func load(from url: URL = Settings.defaultSettingsURL()) throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Settings()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Settings.self, from: data)
    }

    public static func save(_ settings: Settings, to url: URL = Settings.defaultSettingsURL()) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
