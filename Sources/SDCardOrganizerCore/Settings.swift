import Foundation

/// Trwałe ustawienia aplikacji, zapisywane jako JSON w Application Support.
public struct Settings: Codable, Equatable {
    /// Domyślna lista rozszerzeń (wszystkie obsługiwane poza podglądami DJI `.LRF`).
    public static let defaultExtensions: Set<String> = MediaFormats.defaultExtensions

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

    /// Czy przy wykrywaniu duplikatów porównywać checksum plików (wolniejsze, ale pewniejsze).
    public var verifyChecksums: Bool

    /// Czy po skopiowaniu weryfikować każdą kopię sumą kontrolną SHA-256 (porównanie z kartą).
    public var verifyCopies: Bool

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
        verifyCopies: Bool = true,
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
        self.verifyCopies = verifyCopies
        self.drpTemplatePath = drpTemplatePath
    }

    private enum CodingKeys: String, CodingKey {
        case destinationRoot, enabledExtensions, cameraPresets, openInDaVinciResolve, openInLightroom,
             resolution, frameRate, verifyChecksums, verifyCopies, drpTemplatePath
    }

    /// Dekodowanie odporne na zmiany formatu: brakujące lub nieprawidłowe pola przyjmują
    /// wartości domyślne, dzięki czemu plik ustawień ze starszej wersji aplikacji nie jest
    /// odrzucany w całości po dodaniu nowego pola.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            try? container.decodeIfPresent(type, forKey: key)
        }

        let defaults = Settings()
        self.destinationRoot = value(String.self, .destinationRoot) ?? defaults.destinationRoot
        self.enabledExtensions = value(Set<String>.self, .enabledExtensions) ?? defaults.enabledExtensions
        self.cameraPresets = value([String].self, .cameraPresets) ?? defaults.cameraPresets
        self.openInDaVinciResolve = value(Bool.self, .openInDaVinciResolve) ?? defaults.openInDaVinciResolve
        self.openInLightroom = value(Bool.self, .openInLightroom) ?? defaults.openInLightroom
        self.resolution = value(String.self, .resolution) ?? defaults.resolution
        self.frameRate = value(Double.self, .frameRate) ?? defaults.frameRate
        self.verifyChecksums = value(Bool.self, .verifyChecksums) ?? defaults.verifyChecksums
        self.verifyCopies = value(Bool.self, .verifyCopies) ?? defaults.verifyCopies
        self.drpTemplatePath = value(String.self, .drpTemplatePath) ?? defaults.drpTemplatePath
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
        var settings: Settings
        do {
            settings = try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            // Plik jest nieczytelny (np. uszkodzony). Zachowaj jego kopię, zanim aplikacja
            // zapisze w tym miejscu ustawienia domyślne.
            backUpUnreadableFile(at: url)
            settings = Settings()
        }
        if settings.cameraPresets.isEmpty {
            settings.cameraPresets = Settings.defaultCameraPresets
        }
        return settings
    }

    /// Kopiuje nieczytelny plik ustawień obok oryginału jako `settings.unreadable-<data>.json`.
    static func backUpUnreadableFile(at url: URL) {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let name = "\(url.deletingPathExtension().lastPathComponent).unreadable-\(df.string(from: Date())).json"
        let backup = url.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.copyItem(at: url, to: backup)
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
