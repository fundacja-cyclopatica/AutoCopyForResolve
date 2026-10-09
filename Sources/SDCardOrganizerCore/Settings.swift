import Foundation

/// Trwałe ustawienia aplikacji, zapisywane jako JSON w Application Support.
public struct Settings: Codable, Equatable {
    /// Domyślna lista rozszerzeń
    public static let defaultExtensions: Set<String> = [
        // Wideo
        "mov", "mp4", "mxf", "braw", "r3d", "m4v", "avi", "mkv", "mpg", "mpeg", "mts", "m2ts", "crm", "lrf",
        // Zdjęcia i RAW (Sony ARW, Canon CR2/CR3, Nikon NEF, Fuji RAF, DNG itp.)
        "jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "dng", "arw", "srf", "sr2",
        "cr2", "cr3", "crw", "nef", "nrw", "rw2", "orf", "ori", "raf", "pef", "gpr", "raw", "rwl",
        // Audio
        "wav", "mp3", "aac", "aiff", "aif", "m4a", "flac"
    ]

    /// Domyślne presety podpisów kamer
    public static let defaultCameraPresets: [String] = [
        "Kamera A", "Kamera B", "Kamera C", "Dron", "GoPro", "Audio"
    ]

    /// Ścieżka do dysku/folderu docelowego, na który zgrywane są materiały.
    public var destinationRoot: String

    /// Wybrane rozszerzenia plików (bez kropki, małymi literami).
    public var enabledExtensions: Set<String>

    /// Konfigurowalna lista presetów podpisów kamer ("chmurek")
    public var cameraPresets: [String]

    /// Opcje automatycznego otwierania aplikacji po zgraniu
    public var openInDaVinciResolve: Bool
    public var openInLightroom: Bool

    /// Rozdzielczość projektu DaVinci Resolve, np. "1920x1080".
    public var resolution: String

    /// Liczba klatek na sekundę projektu DaVinci Resolve.
    public var frameRate: Double

    /// Czy po skopiowaniu porównywać checksum plików (wolniejsze, ale pewniejsze).
    public var verifyChecksums: Bool

    /// Ścieżka do wzorcowego pliku .drp używanego jako szablon projektu.
    public var drpTemplatePath: String?

    public init(
        destinationRoot: String = "",
        enabledExtensions: Set<String> = Settings.defaultExtensions,
        cameraPresets: [String] = Settings.defaultCameraPresets,
        openInDaVinciResolve: Bool = false,
        openInLightroom: Bool = false,
        resolution: String = "1920x1080",
        frameRate: Double = 25,
        verifyChecksums: Bool = false,
        drpTemplatePath: String? = nil
    ) {
        self.destinationRoot = destinationRoot
        self.enabledExtensions = enabledExtensions
        self.cameraPresets = cameraPresets
        self.openInDaVinciResolve = openInDaVinciResolve
        self.openInLightroom = openInLightroom
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
        var settings = (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
        if settings.enabledExtensions.isEmpty {
            settings.enabledExtensions = Settings.defaultExtensions
        }
        if settings.cameraPresets.isEmpty {
            settings.cameraPresets = Settings.defaultCameraPresets
        }
        return settings
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
